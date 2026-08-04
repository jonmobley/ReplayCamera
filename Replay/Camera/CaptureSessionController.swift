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
final class CaptureSessionController: NSObject, ObservableObject {

    // MARK: - Published UI state

    @MainActor @Published private(set) var bufferedSeconds: TimeInterval = 0
    @MainActor @Published private(set) var isSessionRunning = false
    @MainActor @Published private(set) var statusMessage: String?
    @MainActor @Published private(set) var permissionDenied = false
    @MainActor @Published private(set) var isUsingFrontCamera = false

    let bufferTarget = BufferLength.maxBufferSeconds
    let momentStore = MomentStore.shared

    @MainActor
    var canSave: Bool {
        bufferedSeconds >= 0.5 && isSessionRunning && !isSaveCoolingDown
    }

    // MARK: - Capture

    let previewLayer = AVCaptureVideoPreviewLayer()
    private let session = AVCaptureSession()
    private let sessionQueue: DispatchQueue
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let recorder: RollingBufferRecorder

    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservations = [NSKeyValueObservation]()
    private var lastCaptureRotationAngle: CGFloat?
    private var usingFrontCamera = false
    @MainActor @Published private var isSaveCoolingDown = false
    private var exportTask: Task<Void, Never>?

    // MARK: - Lifecycle

    override init() {
        let queue = DispatchQueue(label: "com.moxie.Replay.session")
        sessionQueue = queue
        recorder = RollingBufferRecorder(
            queue: queue,
            bufferDuration: BufferLength.maxBufferSeconds
        )
        super.init()
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        recorder.onBufferDurationChange = { [weak self] seconds in
            Task { @MainActor in
                self?.bufferedSeconds = seconds
            }
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
            sessionQueue.async { [weak self] in
                self?.configureSessionLocked(includeAudio: micOK)
                self?.session.startRunning()
                let running = self?.session.isRunning ?? false
                Task { @MainActor in
                    self?.isSessionRunning = running
                }
            }
        }
    }

    /// Stops capture and clears the rolling buffer.
    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.tearDownRotationCoordinatorLocked()
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.recorder.reset()
            Task { @MainActor in
                self.isSessionRunning = false
                self.bufferedSeconds = 0
            }
        }
    }

    /// One-tap save: instant feedback, then moment + Photos album in background.
    @MainActor
    func saveReplay() {
        guard canSave else { return }

        let trailingSeconds = BufferLength.exportSeconds(buffered: bufferedSeconds)
        beginSaveCooldown()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        statusMessage = "Saved"
        scheduleStatusClear()

        exportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let segments = await self.snapshotSegments()
            guard !segments.isEmpty else {
                self.statusMessage = "Nothing buffered yet."
                self.scheduleStatusClear()
                return
            }

            do {
                let full = try await SegmentStitcher.stitch(
                    segments,
                    trailingSeconds: BufferLength.maxBufferSeconds
                )
                let fullDuration = try await Self.duration(of: full)
                let moment = try self.momentStore.add(
                    from: full,
                    duration: fullDuration
                )
                // Master lives in MomentStore; drop the stitch temp.
                try? FileManager.default.removeItem(at: full)

                let cutURL = try await MomentExporter.exportTrailing(
                    from: moment.fileURL,
                    seconds: trailingSeconds
                )
                try await PhotoLibrarySaver.saveVideo(at: cutURL)
                try? FileManager.default.removeItem(at: cutURL)
            } catch {
                self.statusMessage = error.localizedDescription
                self.scheduleStatusClear()
            }
        }
    }

    /// Exports another length from a frozen moment into the Replay album.
    @MainActor
    func saveMoment(_ moment: ReplayMoment, length: BufferLength) async throws {
        let cut = try await MomentExporter.exportTrailing(
            from: moment.fileURL,
            seconds: length.seconds
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
    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()

            if let current = self.videoDeviceInput {
                self.session.removeInput(current)
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
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(input)
            self.videoDeviceInput = input
            self.usingFrontCamera = nextPosition == .front
            self.configureRecorderSettingsLocked()
            self.session.commitConfiguration()
            self.recorder.reset()
            self.installRotationCoordinatorLocked()

            if let connection = self.videoOutput.connection(with: .video),
               connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = nextPosition == .front
            }

            Task { @MainActor in
                self.isUsingFrontCamera = nextPosition == .front
                self.bufferedSeconds = 0
            }
        }
    }

    // MARK: - Session setup

    private func configureSessionLocked(includeAudio: Bool) {
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else {
            session.sessionPreset = .high
        }

        if session.outputs.isEmpty {
            if session.canAddOutput(videoOutput) {
                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
                session.addOutput(videoOutput)
            }

            if includeAudio, session.canAddOutput(audioOutput) {
                audioOutput.setSampleBufferDelegate(self, queue: sessionQueue)
                session.addOutput(audioOutput)
            }
        }

        if videoDeviceInput == nil,
           let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
           ),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            videoDeviceInput = input
        }

        if includeAudio,
           audioDeviceInput == nil,
           let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput) {
            session.addInput(micInput)
            audioDeviceInput = micInput
        }

        configureRecorderSettingsLocked()
        session.commitConfiguration()
        installRotationCoordinatorLocked()
    }

    private func configureRecorderSettingsLocked() {
        let videoSettings = videoOutput.recommendedVideoSettingsForAssetWriter(
            writingTo: .mp4
        ) ?? [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1920,
            AVVideoHeightKey: 1080
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
                self?.applyCaptureRotation(angle, breakSegment: true)
            }
        }

        let previewObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.new]
        ) { [weak self] coord, _ in
            let angle = coord.videoRotationAngleForHorizonLevelPreview
            DispatchQueue.main.async {
                self?.applyPreviewRotation(angle)
            }
        }

        rotationObservations = [captureObservation, previewObservation]
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
    private func beginSaveCooldown() {
        isSaveCoolingDown = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            isSaveCoolingDown = false
        }
    }

    @MainActor
    private func scheduleStatusClear() {
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
        if output is AVCaptureVideoDataOutput {
            recorder.appendVideo(sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            recorder.appendAudio(sampleBuffer)
        }
    }
}
