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
    @MainActor @Published private(set) var isSaving = false
    @MainActor @Published private(set) var isUsingFrontCamera = false
    @MainActor @Published private(set) var statusMessage: String?
    @MainActor @Published private(set) var permissionDenied = false
    @Published private(set) var bufferLength: BufferLength

    var bufferTarget: TimeInterval { bufferLength.seconds }

    @MainActor
    var canSave: Bool {
        bufferedSeconds >= 0.5 && !isSaving && isSessionRunning
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
    private var usingFrontCamera = false

    // MARK: - Lifecycle

    override init() {
        let length = BufferLength.stored
        let queue = DispatchQueue(label: "com.moxie.Replay.session")
        sessionQueue = queue
        recorder = RollingBufferRecorder(
            queue: queue,
            bufferDuration: length.seconds
        )
        bufferLength = length
        super.init()
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        recorder.onBufferDurationChange = { [weak self] seconds in
            Task { @MainActor in
                self?.bufferedSeconds = seconds
            }
        }
    }

    /// Changes the rolling window length without stopping the session.
    @MainActor
    func setBufferLength(_ length: BufferLength) {
        guard length != bufferLength else { return }
        bufferLength = length
        BufferLength.stored = length
        sessionQueue.async { [weak self] in
            self?.recorder.setBufferDuration(length.seconds)
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

    /// Switches between front and back cameras and resets the buffer.
    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

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
            else { return }

            self.session.addInput(input)
            self.videoDeviceInput = input
            self.usingFrontCamera = nextPosition == .front
            self.applyVideoRotationLocked()
            self.configureRecorderSettingsLocked()
            self.recorder.reset()

            Task { @MainActor in
                self.isUsingFrontCamera = nextPosition == .front
                self.bufferedSeconds = 0
            }
        }
    }

    /// Flushes the open segment, stitches the window, and saves to Photos.
    @MainActor
    func saveReplay() {
        guard canSave, !isSaving else { return }
        isSaving = true
        statusMessage = nil

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.recorder.flushAndSnapshot { segments in
                Task { @MainActor in
                    await self.exportAndSave(segments)
                }
            }
        }
    }

    @MainActor
    private func exportAndSave(_ segments: [BufferSegment]) async {
        do {
            let stitched = try await SegmentStitcher.stitch(segments)
            try await PhotoLibrarySaver.saveVideo(at: stitched)
            try? FileManager.default.removeItem(at: stitched)
            statusMessage = "Saved to Photos"
        } catch {
            statusMessage = error.localizedDescription
        }
        isSaving = false
        scheduleStatusClear()
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

        applyVideoRotationLocked()
        configureRecorderSettingsLocked()
        session.commitConfiguration()
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

    private func applyVideoRotationLocked() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        let isFront = videoDeviceInput?.device.position == .front
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isFront
        }
    }

    private static func requestAccess(for mediaType: AVMediaType) async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: mediaType) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    @MainActor
    private func scheduleStatusClear() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if statusMessage == "Saved to Photos" {
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
