//
//  RollingBufferRecorder.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

@preconcurrency import AVFoundation
import Foundation

/// A finished MP4 segment kept in the rolling window.
struct BufferSegment: Sendable {
    let url: URL
    let duration: TimeInterval
}

/// Continuously encodes capture samples into ~2s MP4 segments and retains
/// only the trailing `bufferDuration` window.
///
/// Call `configure`, `append*`, `flushAndSnapshot`, and `reset` on `queue`.
final class RollingBufferRecorder: NSObject {

    // MARK: - Config

    private(set) var bufferDuration: TimeInterval
    let segmentDuration: TimeInterval
    private let queue: DispatchQueue

    // MARK: - State

    private var segments: [BufferSegment] = []
    private var currentWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var segmentStartPTS: CMTime?
    private var lastVideoPTS: CMTime?
    private var isFinishingSegment = false
    private var videoSettings: [String: Any] = [:]
    private var audioSettings: [String: Any]?
    private var pendingFlush: (([BufferSegment]) -> Void)?

    private let segmentsDirectory: URL

    /// Called on the main queue when reported buffer duration changes.
    var onBufferDurationChange: ((TimeInterval) -> Void)?

    // MARK: - Init

    /// - Parameters:
    ///   - queue: Serial queue used for all recorder work (typically the capture queue).
    ///   - bufferDuration: Trailing window length to keep (default 15s).
    ///   - segmentDuration: Target length of each on-disk segment (default 2s).
    init(
        queue: DispatchQueue,
        bufferDuration: TimeInterval = 15,
        segmentDuration: TimeInterval = 2
    ) {
        self.queue = queue
        self.bufferDuration = bufferDuration
        self.segmentDuration = segmentDuration
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplaySegments", isDirectory: true)
        self.segmentsDirectory = base
        super.init()
        try? FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true
        )
        clearAllSegmentFiles()
    }

    // MARK: - Public

    /// Updates the trailing window length and prunes overflow segments.
    func setBufferDuration(_ duration: TimeInterval) {
        bufferDuration = max(1, duration)
        prune()
        publishDuration()
    }

    /// Configure encoder settings before samples arrive.
    func configure(
        videoSettings: [String: Any],
        audioSettings: [String: Any]?
    ) {
        self.videoSettings = videoSettings
        self.audioSettings = audioSettings
    }

    /// Append a video sample into the rolling buffer.
    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        lastVideoPTS = pts

        if currentWriter == nil, !isFinishingSegment {
            startNewSegment(at: pts)
        }

        if let start = segmentStartPTS {
            let elapsed = CMTimeGetSeconds(CMTimeSubtract(pts, start))
            if elapsed >= segmentDuration, !isFinishingSegment {
                rotateSegment(nextPTS: pts)
            }
        }

        if let input = videoInput,
           input.isReadyForMoreMediaData,
           currentWriter?.status == .writing {
            _ = input.append(sampleBuffer)
        }
        publishDuration()
    }

    /// Append an audio sample into the rolling buffer.
    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let input = audioInput, input.isReadyForMoreMediaData else { return }
        guard currentWriter?.status == .writing else { return }
        _ = input.append(sampleBuffer)
    }

    /// Finishes the open segment, then returns the trailing window snapshot.
    func flushAndSnapshot(completion: @escaping ([BufferSegment]) -> Void) {
        if currentWriter == nil {
            prune()
            completion(segments)
            return
        }
        pendingFlush = completion
        closeOpenSegment()
    }

    /// Tear down the open writer and delete all segment files.
    func reset() {
        pendingFlush = nil
        if currentWriter != nil {
            closeOpenSegment(discard: true)
        } else {
            clearAllSegmentFiles()
            segments.removeAll()
            segmentStartPTS = nil
            lastVideoPTS = nil
            publishDuration()
        }
    }

    // MARK: - Segment lifecycle

    private func startNewSegment(at pts: CMTime) {
        guard !videoSettings.isEmpty else { return }

        let url = segmentsDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

            let vInput = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: videoSettings
            )
            vInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(vInput) else { return }
            writer.add(vInput)

            var aInput: AVAssetWriterInput?
            if let audioSettings {
                let input = AVAssetWriterInput(
                    mediaType: .audio,
                    outputSettings: audioSettings
                )
                input.expectsMediaDataInRealTime = true
                if writer.canAdd(input) {
                    writer.add(input)
                    aInput = input
                }
            }

            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: pts)

            currentWriter = writer
            videoInput = vInput
            audioInput = aInput
            segmentStartPTS = pts
            isFinishingSegment = false
        } catch {
            currentWriter = nil
            videoInput = nil
            audioInput = nil
        }
    }

    private func rotateSegment(nextPTS: CMTime) {
        isFinishingSegment = true
        let finishedURL = currentWriter?.outputURL
        let start = segmentStartPTS ?? nextPTS
        let duration = max(0, CMTimeGetSeconds(CMTimeSubtract(nextPTS, start)))
        let writer = currentWriter

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        currentWriter = nil
        videoInput = nil
        audioInput = nil
        segmentStartPTS = nil

        startNewSegment(at: nextPTS)

        writer?.finishWriting { [weak self] in
            guard let self else { return }
            self.queue.async {
                self.handleFinishedSegment(
                    status: writer?.status,
                    url: finishedURL,
                    duration: duration
                )
            }
        }
    }

    private func closeOpenSegment(discard: Bool = false) {
        guard let writer = currentWriter else {
            deliverPendingFlush()
            return
        }

        isFinishingSegment = true
        let finishedURL = writer.outputURL
        let start = segmentStartPTS
        let end = lastVideoPTS
        var duration: TimeInterval = 0
        if let start, let end {
            duration = max(0, CMTimeGetSeconds(CMTimeSubtract(end, start)))
        }

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        currentWriter = nil
        videoInput = nil
        audioInput = nil
        segmentStartPTS = nil

        writer.finishWriting { [weak self] in
            guard let self else { return }
            self.queue.async {
                if discard {
                    try? FileManager.default.removeItem(at: finishedURL)
                    self.clearAllSegmentFiles()
                    self.segments.removeAll()
                    self.lastVideoPTS = nil
                } else if writer.status == .completed, duration > 0.05 {
                    self.segments.append(
                        BufferSegment(url: finishedURL, duration: duration)
                    )
                    self.prune()
                } else {
                    try? FileManager.default.removeItem(at: finishedURL)
                }
                self.isFinishingSegment = false
                self.publishDuration()
                self.deliverPendingFlush()
            }
        }
    }

    private func handleFinishedSegment(
        status: AVAssetWriter.Status?,
        url: URL?,
        duration: TimeInterval
    ) {
        if status == .completed, let url, duration > 0.05 {
            segments.append(BufferSegment(url: url, duration: duration))
            prune()
        } else if let url {
            try? FileManager.default.removeItem(at: url)
        }
        isFinishingSegment = false
        publishDuration()
    }

    private func deliverPendingFlush() {
        guard let pendingFlush else { return }
        self.pendingFlush = nil
        pendingFlush(segments)
    }

    private func prune() {
        var total = segments.reduce(0.0) { $0 + $1.duration }
        while total > bufferDuration, segments.count > 1 {
            let removed = segments.removeFirst()
            total -= removed.duration
            try? FileManager.default.removeItem(at: removed.url)
        }
    }

    private func publishDuration() {
        var total = segments.reduce(0.0) { $0 + $1.duration }
        if let start = segmentStartPTS, let end = lastVideoPTS {
            total += max(0, CMTimeGetSeconds(CMTimeSubtract(end, start)))
        }
        let reported = min(total, bufferDuration)
        DispatchQueue.main.async { [weak self] in
            self?.onBufferDurationChange?(reported)
        }
    }

    private func clearAllSegmentFiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: segmentsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            try? fm.removeItem(at: file)
        }
    }
}
