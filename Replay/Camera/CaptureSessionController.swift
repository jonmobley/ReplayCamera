//
//  CaptureSessionController.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

@preconcurrency import AVFoundation
import Combine
import UIKit

/// Owns the capture session, preview layer, rolling buffer, and save flow.
///
/// Intentionally shared across the main actor (UI) and a serial session queue;
/// mutable capture state is touched only on `sessionQueue`.
final class CaptureSessionController: NSObject, ObservableObject, @unchecked Sendable {

    // MARK: - Published UI state

    @MainActor @Published private(set) var bufferedSeconds: TimeInterval = 0
    @MainActor @Published private(set) var isSessionRunning = false
    @MainActor @Published private(set) var isRecording = false
    @MainActor @Published private(set) var isChoosingSave = false
    @MainActor @Published var statusMessage: String?
    @MainActor @Published private(set) var permissionDenied = false
    @MainActor @Published private(set) var isUsingFrontCamera = false
    @MainActor @Published private(set) var resolution: CaptureResolution = .hd
    @MainActor @Published private(set) var frameRate: CaptureFrameRate = .fps30
    @MainActor @Published var zoomFactor: CGFloat = 1
    @MainActor @Published var isTorchOn = false
    @MainActor @Published var isTorchAvailable = false
    @MainActor @Published var isMicMuted = false

    private var didWarnLongRecording = false
    private static let longRecordingWarningSeconds: TimeInterval = 10 * 60

    @MainActor
    var canToggleShutter: Bool {
        isSessionRunning && !isSaveCoolingDown && !permissionDenied && !isChoosingSave
    }

    @MainActor
    var canChangeQuality: Bool {
        isSessionRunning && !isRecording && !isChoosingSave && !permissionDenied
    }

    @MainActor
    var canClip: Bool {
        isRecording && bufferedSeconds >= 0.5 && !isClipping && !isChoosingSave
    }

    @MainActor
    var canCapturePhoto: Bool {
        isRecording && !isCapturingPhoto && !permissionDenied && !isChoosingSave
    }

    @MainActor
    var canFlipCamera: Bool {
        isSessionRunning && !isRecording && !isChoosingSave && !permissionDenied
    }

    @MainActor
    var canToggleTorch: Bool {
        isTorchAvailable && !permissionDenied && !isUsingFrontCamera
    }

    /// Save lengths offered for the frozen take.
    @MainActor
    var availableSaveOptions: [SaveOption] {
        SaveOption.available(forSessionSeconds: pendingSessionSeconds)
    }

    // MARK: - Capture

    let previewLayer = AVCaptureVideoPreviewLayer()
    let sessionQueue: DispatchQueue
    /// Exposed for interruption observers in extensions.
    let captureSession: AVCaptureSession
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let recorder: RollingBufferRecorder

    var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservations = [NSKeyValueObservation]()
    private var lastCaptureRotationAngle: CGFloat?
    private var usingFrontCamera = false
    @MainActor @Published private var isSaveCoolingDown = false
    @MainActor @Published private(set) var isClipping = false
    @MainActor @Published private(set) var isCapturingPhoto = false
    /// Only append samples while armed (session-queue only).
    var isBufferingLocked = false
    /// When true, audio samples are dropped (session-queue).
    var isMicMutedLocked = false
    private var exportTask: Task<Void, Never>?
    private var clipTask: Task<Void, Never>?
    private var didWarnMicDenied = false
    private var pendingSaveSegments: [BufferSegment] = []
    private var pendingSessionSeconds: TimeInterval = 0
    private let clipSeconds: TimeInterval = 30
    var interruptionObservers = [NSObjectProtocol]()
    /// Zoom factor when the current pinch gesture began.
    var pinchZoomBase: CGFloat = 1
    /// Desired quality; may be clamped to what the active camera supports.
    private var desiredQuality = CaptureQualityPreference.load()

    // MARK: - Lifecycle

    override init() {
        let queue = DispatchQueue(label: "com.moxie.Replay.session")
        sessionQueue = queue
        captureSession = AVCaptureSession()
        recorder = RollingBufferRecorder(
            queue: queue,
            bufferDuration: BufferLength.maxBufferSeconds,
            retainsFullSession: true
        )
        super.init()
        previewLayer.session = captureSession
        previewLayer.videoGravity = .resizeAspectFill
        recorder.onBufferDurationChange = { [weak self] seconds in
            Task { @MainActor in
                self?.bufferedSeconds = seconds
                self?.warnIfLongRecording(seconds)
            }
        }
        let quality = desiredQuality
        Task { @MainActor in
            self.resolution = quality.resolution
            self.frameRate = quality.frameRate
        }
    }

    /// Requests permissions and starts the capture + buffer pipeline.
    @MainActor
    func start() {
        Task { @MainActor in
            let cameraOK = await Self.requestAccess(for: .video)
            let micOK = await Self.requestAccess(for: .audio)
            guard cameraOK else {
                permissionDenied = true
                statusMessage = "Camera access is required."
                return
            }
            if !micOK, !didWarnMicDenied {
                didWarnMicDenied = true
                statusMessage = "Mic off — clips will be silent."
                scheduleStatusClear()
            }
            installInterruptionObservers()
            sessionQueue.async { [weak self] in
                self?.configureSessionLocked(includeAudio: micOK)
                self?.captureSession.startRunning()
                let running = self?.captureSession.isRunning ?? false
                Task { @MainActor in
                    self?.isSessionRunning = running
                }
            }
        }
    }

    /// Stops capture and clears the rolling buffer.
    func stop() {
        removeInterruptionObservers()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.tearDownRotationCoordinatorLocked()
            if let device = self.videoDeviceInput?.device, device.hasTorch {
                try? device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
            }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            self.recorder.reset()
            Task { @MainActor in
                self.isSessionRunning = false
                self.isRecording = false
                self.isChoosingSave = false
                self.isTorchOn = false
                self.bufferedSeconds = 0
                self.clearPendingSave()
            }
        }
    }

    /// Idle → start buffering; recording → stop and ask what to save.
    @MainActor
    func toggleShutter() {
        guard canToggleShutter else { return }
        if isRecording {
            stopRecordingForSavePrompt()
        } else {
            startRecording()
        }
    }

    /// Toggles HD ↔ 4K when idle.
    @MainActor
    func toggleResolution() {
        guard canChangeQuality else { return }
        let next: CaptureResolution = resolution == .hd ? .fourK : .hd
        resolution = next
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.desiredQuality.resolution = next
            self.desiredQuality.save()
            self.applyCaptureQualityLocked()
        }
    }

    /// Cycles 24 → 30 → 60 when idle.
    @MainActor
    func cycleFrameRate() {
        guard canChangeQuality else { return }
        let next = frameRate.next
        frameRate = next
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.desiredQuality.frameRate = next
            self.desiredQuality.save()
            self.applyCaptureQualityLocked()
        }
    }

    /// Arms the session buffer after the user settles orientation.
    @MainActor
    private func startRecording() {
        isRecording = true
        bufferedSeconds = 0
        didWarnLongRecording = false
        clearPendingSave()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.installRotationCoordinatorLocked()
            self.configureRecorderSettingsLocked()
            self.recorder.reset()
            self.isBufferingLocked = true
        }
    }

    /// Stops buffering and presents the save sheet once the snapshot is ready.
    @MainActor
    func stopRecordingForSavePrompt() {
        guard isRecording else { return }
        let readySeconds = bufferedSeconds
        isRecording = false
        beginSaveCooldown()

        sessionQueue.async { [weak self] in
            self?.unlockRotationAfterRecordingLocked()
        }

        guard readySeconds >= 0.5 else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            statusMessage = "Too short"
            scheduleStatusClear()
            sessionQueue.async { [weak self] in
                self?.recorder.reset()
            }
            bufferedSeconds = 0
            return
        }

        exportTask?.cancel()
        exportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let segments = await self.snapshotSegments()
            guard !Task.isCancelled else {
                RollingBufferRecorder.cleanupExportSnapshot(segments)
                return
            }
            guard !segments.isEmpty else {
                self.statusMessage = "Nothing buffered yet."
                self.scheduleStatusClear()
                self.sessionQueue.async { self.recorder.reset() }
                self.bufferedSeconds = 0
                return
            }
            self.pendingSaveSegments = segments
            self.pendingSessionSeconds = segments.reduce(0) { $0 + $1.duration }
            self.isChoosingSave = true
        }
    }

    /// Ends an in-progress take when the app resigns or capture is interrupted.
    @MainActor
    func handleExternalInterruption() {
        guard isRecording else { return }
        stopRecordingForSavePrompt()
    }

    /// Restarts the session after a call or background interrupt ends.
    func resumeCaptureIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.videoDeviceInput != nil else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
            let running = self.captureSession.isRunning
            Task { @MainActor in
                self.isSessionRunning = running
            }
        }
    }

    /// User chose Don't Save — discard the frozen take.
    @MainActor
    func discardRecording() {
        guard isChoosingSave || !pendingSaveSegments.isEmpty else { return }
        isChoosingSave = false
        let segments = pendingSaveSegments
        clearPendingSave()
        RollingBufferRecorder.cleanupExportSnapshot(segments)
        sessionQueue.async { [weak self] in
            self?.recorder.reset()
        }
        bufferedSeconds = 0
    }

    /// Cancel / dismiss save sheet — keep a temporary Moment, no Photos export.
    @MainActor
    func keepRecordingAsMoment() {
        guard isChoosingSave else { return }
        let segments = pendingSaveSegments
        let sessionSeconds = max(pendingSessionSeconds, 0.5)
        isChoosingSave = false
        clearPendingSave()

        exportTask?.cancel()
        exportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                RollingBufferRecorder.cleanupExportSnapshot(segments)
                self.sessionQueue.async { self.recorder.reset() }
                self.bufferedSeconds = 0
            }

            guard !segments.isEmpty else { return }

            do {
                let full = try await SegmentStitcher.stitch(
                    segments,
                    trailingSeconds: sessionSeconds
                )
                let fullDuration = try await Self.duration(of: full)
                _ = try MomentStore.shared.add(from: full, duration: fullDuration)
                try? FileManager.default.removeItem(at: full)
                self.statusMessage = "Kept as Moment"
                self.scheduleStatusClear()
            } catch {
                self.statusMessage = error.localizedDescription
                self.scheduleStatusClear()
            }
        }
    }

    /// Exports the frozen take for `option` with feedback after the write finishes.
    @MainActor
    func confirmSave(_ option: SaveOption) {
        guard isChoosingSave else { return }
        let segments = pendingSaveSegments
        let sessionSeconds = max(pendingSessionSeconds, 0.5)
        isChoosingSave = false
        clearPendingSave()

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        statusMessage = "Saving…"

        exportTask?.cancel()
        exportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                RollingBufferRecorder.cleanupExportSnapshot(segments)
                self.sessionQueue.async { self.recorder.reset() }
                self.bufferedSeconds = 0
            }

            guard !segments.isEmpty else {
                self.statusMessage = "Nothing to save."
                self.scheduleStatusClear()
                return
            }

            do {
                // Always stitch the full session first (master / Moment).
                let full = try await SegmentStitcher.stitch(
                    segments,
                    trailingSeconds: sessionSeconds
                )
                let fullDuration = try await Self.duration(of: full)
                let moment = try MomentStore.shared.add(
                    from: full,
                    duration: fullDuration
                )
                let momentURL = MomentStore.shared.fileURL(for: moment)
                try? FileManager.default.removeItem(at: full)

                let exportURL: URL
                if let trailing = option.trailingSeconds,
                   trailing + 0.2 < fullDuration {
                    exportURL = try await MomentExporter.exportTrailing(
                        from: momentURL,
                        seconds: trailing
                    )
                } else {
                    exportURL = try await MomentExporter.exportTrailing(
                        from: momentURL,
                        seconds: fullDuration
                    )
                }

                try await PhotoLibrarySaver.saveVideo(at: exportURL)
                try? FileManager.default.removeItem(at: exportURL)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.statusMessage = "Saved"
                self.scheduleStatusClear()
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                self.statusMessage = error.localizedDescription
                self.scheduleStatusClear()
            }
        }
    }

    private func clearPendingSave() {
        pendingSaveSegments = []
        pendingSessionSeconds = 0
    }

    /// Captures a still photo into the Replay album without stopping recording.
    @MainActor
    func captureStillPhoto() {
        guard canCapturePhoto else { return }
        isCapturingPhoto = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(
                    format: [AVVideoCodecKey: AVVideoCodecType.hevc]
                )
            } else {
                settings = AVCapturePhotoSettings()
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Saves the last 30 seconds without stopping the full session.
    @MainActor
    func saveClipWhileRecording() {
        guard canClip else { return }
        isClipping = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        statusMessage = "Clip saved"
        scheduleStatusClear()

        clipTask?.cancel()
        clipTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isClipping = false }

            let segments = await self.snapshotClipSegments(seconds: self.clipSeconds)
            defer { RollingBufferRecorder.cleanupExportSnapshot(segments) }

            guard !Task.isCancelled else { return }
            guard !segments.isEmpty else {
                self.statusMessage = "Nothing to clip yet."
                self.scheduleStatusClear()
                return
            }

            do {
                let total = segments.reduce(0.0) { $0 + $1.duration }
                let stitched = try await SegmentStitcher.stitch(
                    segments,
                    trailingSeconds: total
                )
                try await PhotoLibrarySaver.saveVideo(at: stitched)
                try? FileManager.default.removeItem(at: stitched)
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                self.statusMessage = error.localizedDescription
                self.scheduleStatusClear()
            }
        }
    }

    private func snapshotClipSegments(seconds: TimeInterval) async -> [BufferSegment] {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [recorder] in
                recorder.snapshotTrailingClip(seconds: seconds) { segments in
                    continuation.resume(returning: segments)
                }
            }
        }
    }

    /// Saves the full frozen moment into the Replay album.
    @MainActor
    func saveMoment(_ moment: ReplayMoment) async throws {
        let cut = try await MomentExporter.exportTrailing(
            from: MomentStore.shared.fileURL(for: moment),
            seconds: moment.duration
        )
        try await PhotoLibrarySaver.saveVideo(at: cut)
        try? FileManager.default.removeItem(at: cut)
    }

    private func snapshotSegments() async -> [BufferSegment] {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [recorder] in
                recorder.flushAndSnapshot { segments in
                    continuation.resume(returning: segments)
                }
            }
        }
    }

    /// Switches between front and back cameras and resets the buffer.
    /// Disabled while recording — flipping would wipe the armed take.
    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isBufferingLocked else { return }
            let keepBuffering = self.isBufferingLocked
            self.captureSession.beginConfiguration()

            if let current = self.videoDeviceInput {
                self.captureSession.removeInput(current)
            }

            let nextPosition: AVCaptureDevice.Position =
                self.usingFrontCamera ? .back : .front
            guard
                let device = AVCaptureDevice.default(
                    .builtInWideAngleCamera,
                    for: .video,
                    position: nextPosition
                ),
                let input = try? AVCaptureDeviceInput(device: device),
                self.captureSession.canAddInput(input)
            else {
                self.captureSession.commitConfiguration()
                return
            }

            self.captureSession.addInput(input)
            self.videoDeviceInput = input
            self.usingFrontCamera = nextPosition == .front
            self.configureRecorderSettingsLocked()
            self.captureSession.commitConfiguration()
            self.recorder.reset()
            self.setZoomFactorLocked(1)
            self.applyCaptureQualityLocked()
            self.publishTorchAvailabilityLocked()
            self.installRotationCoordinatorLocked()
            self.isBufferingLocked = keepBuffering

            if let connection = self.videoOutput.connection(with: .video),
               connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = nextPosition == .front
            }
            if let photoConnection = self.photoOutput.connection(with: .video),
               photoConnection.isVideoMirroringSupported {
                photoConnection.automaticallyAdjustsVideoMirroring = false
                photoConnection.isVideoMirrored = nextPosition == .front
            }

            Task { @MainActor in
                self.isUsingFrontCamera = nextPosition == .front
                self.bufferedSeconds = 0
            }
        }
    }

    // MARK: - Session setup

    private func configureSessionLocked(includeAudio: Bool) {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .inputPriority

        if captureSession.outputs.isEmpty {
            if captureSession.canAddOutput(videoOutput) {
                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
                captureSession.addOutput(videoOutput)
            }

            if includeAudio, captureSession.canAddOutput(audioOutput) {
                audioOutput.setSampleBufferDelegate(self, queue: sessionQueue)
                captureSession.addOutput(audioOutput)
            }

            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            }
        }

        if videoDeviceInput == nil,
           let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
           ),
           let input = try? AVCaptureDeviceInput(device: device),
           captureSession.canAddInput(input) {
            captureSession.addInput(input)
            videoDeviceInput = input
        }

        if includeAudio,
           audioDeviceInput == nil,
           let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           captureSession.canAddInput(micInput) {
            captureSession.addInput(micInput)
            audioDeviceInput = micInput
        }

        captureSession.commitConfiguration()
        applyCaptureQualityLocked()
        publishTorchAvailabilityLocked()
        installRotationCoordinatorLocked()
    }

    /// Picks the best matching device format for desired resolution + fps.
    private func applyCaptureQualityLocked() {
        guard let device = videoDeviceInput?.device else { return }
        let wanted = desiredQuality
        guard
            let match = Self.bestFormat(
                on: device,
                resolution: wanted.resolution,
                frameRate: wanted.frameRate
            )
        else { return }

        do {
            try device.lockForConfiguration()
            device.activeFormat = match.format
            let duration = CMTime(value: 1, timescale: CMTimeScale(match.frameRate.rawValue))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            return
        }

        desiredQuality = CaptureQualityPreference(
            resolution: match.resolution,
            frameRate: match.frameRate
        )
        desiredQuality.save()
        configureRecorderSettingsLocked()

        let applied = desiredQuality
        Task { @MainActor in
            self.resolution = applied.resolution
            self.frameRate = applied.frameRate
        }
    }

    private struct FormatMatch {
        let format: AVCaptureDevice.Format
        let resolution: CaptureResolution
        let frameRate: CaptureFrameRate
    }

    private static func bestFormat(
        on device: AVCaptureDevice,
        resolution: CaptureResolution,
        frameRate: CaptureFrameRate
    ) -> FormatMatch? {
        let resolutionOrder = resolution == .fourK
            ? [CaptureResolution.fourK, .hd]
            : [CaptureResolution.hd, .fourK]
        let rateOrder: [CaptureFrameRate] = [frameRate] + CaptureFrameRate.allCases.filter {
            $0 != frameRate
        }

        for res in resolutionOrder {
            for rate in rateOrder {
                if let format = selectFormat(
                    on: device,
                    width: res.width,
                    height: res.height,
                    fps: rate.rawValue
                ) {
                    return FormatMatch(
                        format: format,
                        resolution: res,
                        frameRate: rate
                    )
                }
            }
        }
        return nil
    }

    private static func selectFormat(
        on device: AVCaptureDevice,
        width: Int32,
        height: Int32,
        fps: Int
    ) -> AVCaptureDevice.Format? {
        let fpsValue = Float64(fps)
        let matches = device.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width == width, dims.height == height else { return false }
            return format.videoSupportedFrameRateRanges.contains { range in
                range.minFrameRate <= fpsValue && fpsValue <= range.maxFrameRate
            }
        }
        // Prefer wider FOV (less cropped tele-style formats).
        return matches.max(
            by: { $0.videoFieldOfView < $1.videoFieldOfView }
        )
    }

    private func configureRecorderSettingsLocked() {
        let fallbackWidth = Int(desiredQuality.resolution.width)
        let fallbackHeight = Int(desiredQuality.resolution.height)
        let videoSettings = videoOutput.recommendedVideoSettingsForAssetWriter(
            writingTo: .mp4
        ) ?? [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: fallbackWidth,
            AVVideoHeightKey: fallbackHeight
        ]

        var audioSettings: [String: Any]?
        if audioDeviceInput != nil {
            audioSettings = audioOutput.recommendedAudioSettingsForAssetWriter(
                writingTo: .mp4
            )
        }
        recorder.configure(videoSettings: videoSettings, audioSettings: audioSettings)
    }

    // MARK: - Orientation

    private func installRotationCoordinatorLocked() {
        guard let device = videoDeviceInput?.device else { return }
        tearDownRotationCoordinatorLocked()

        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: device,
            previewLayer: previewLayer
        )
        rotationCoordinator = coordinator

        applyCaptureRotation(
            coordinator.videoRotationAngleForHorizonLevelCapture,
            breakSegment: false
        )
        applyPreviewRotation(
            coordinator.videoRotationAngleForHorizonLevelPreview
        )

        let captureObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.new]
        ) { [weak self] coord, _ in
            let angle = coord.videoRotationAngleForHorizonLevelCapture
            self?.sessionQueue.async {
                guard let self, !self.isBufferingLocked else { return }
                self.applyCaptureRotation(angle, breakSegment: true)
            }
        }

        let previewObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.new]
        ) { [weak self] coord, _ in
            let angle = coord.videoRotationAngleForHorizonLevelPreview
            self?.sessionQueue.async {
                guard let self, !self.isBufferingLocked else { return }
                DispatchQueue.main.async {
                    self.applyPreviewRotation(angle)
                }
            }
        }

        rotationObservations = [captureObservation, previewObservation]
    }

    /// Ends the recording lock and snaps capture/preview to the current device angle.
    private func unlockRotationAfterRecordingLocked() {
        isBufferingLocked = false
        guard let coordinator = rotationCoordinator else { return }
        applyCaptureRotation(
            coordinator.videoRotationAngleForHorizonLevelCapture,
            breakSegment: false
        )
        let previewAngle = coordinator.videoRotationAngleForHorizonLevelPreview
        DispatchQueue.main.async { [weak self] in
            self?.applyPreviewRotation(previewAngle)
        }
    }

    private func tearDownRotationCoordinatorLocked() {
        rotationObservations.forEach { $0.invalidate() }
        rotationObservations.removeAll()
        rotationCoordinator = nil
        lastCaptureRotationAngle = nil
    }

    private func applyCaptureRotation(_ angle: CGFloat, breakSegment: Bool) {
        guard let connection = videoOutput.connection(with: .video),
              connection.isVideoRotationAngleSupported(angle)
        else { return }

        let angleChanged = lastCaptureRotationAngle != angle
        connection.videoRotationAngle = angle
        lastCaptureRotationAngle = angle

        if let photoConnection = photoOutput.connection(with: .video),
           photoConnection.isVideoRotationAngleSupported(angle) {
            photoConnection.videoRotationAngle = angle
        }

        guard angleChanged else { return }
        configureRecorderSettingsLocked()
        if breakSegment {
            recorder.forceRotateSegment()
        }
    }

    private func applyPreviewRotation(_ angle: CGFloat) {
        guard let connection = previewLayer.connection,
              connection.isVideoRotationAngleSupported(angle)
        else { return }
        connection.videoRotationAngle = angle
    }

    // MARK: - Helpers

    private static func requestAccess(for mediaType: AVMediaType) async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: mediaType) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func duration(of url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let time = try await asset.load(.duration)
        return CMTimeGetSeconds(time)
    }

    @MainActor
    private func warnIfLongRecording(_ seconds: TimeInterval) {
        guard isRecording, !didWarnLongRecording else { return }
        guard seconds >= Self.longRecordingWarningSeconds else { return }
        didWarnLongRecording = true
        statusMessage = "Long recording — watch free storage."
        scheduleStatusClear()
    }

    @MainActor
    private func beginSaveCooldown() {
        isSaveCoolingDown = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            isSaveCoolingDown = false
        }
    }

    @MainActor
    func scheduleStatusClear() {
        let message = statusMessage
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }
}

// MARK: - Sample buffer delegates

extension CaptureSessionController: AVCaptureVideoDataOutputSampleBufferDelegate,
                                    AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isBufferingLocked else { return }
        if output is AVCaptureVideoDataOutput {
            recorder.appendVideo(sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            guard !isMicMutedLocked else { return }
            recorder.appendAudio(sampleBuffer)
        }
    }
}

// MARK: - Still photo

extension CaptureSessionController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            defer { self.isCapturingPhoto = false }

            if let error {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                self.statusMessage = error.localizedDescription
                self.scheduleStatusClear()
                return
            }

            guard let data = photo.fileDataRepresentation() else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                self.statusMessage = "Could not capture photo."
                self.scheduleStatusClear()
                return
            }

            do {
                try await PhotoLibrarySaver.saveImageData(data)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.statusMessage = "Photo saved"
                self.scheduleStatusClear()
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                self.statusMessage = error.localizedDescription
                self.scheduleStatusClear()
            }
        }
    }
}
