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
    /// When true, finished segments are kept for the whole armed session.
    var retainsFullSession: Bool
    private let queue: DispatchQueue

    // MARK: - State

    private var segments: [BufferSegment] = []
    private var currentWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var segmentStartPTS: CMTime?
    private var lastVideoPTS: CMTime?
    private var isFinishingSegment = false
    private var pendingFinishCount = 0
    /// Bumped on `reset` so in-flight `finishWriting` callbacks are ignored.
    private var generation = 0
    private var videoSettings: [String: Any] = [:]
    private var audioSettings: [String: Any]?
    private var pendingFlush: (([BufferSegment]) -> Void)?
    /// One-shot clip snapshot after sealing the open segment (recording continues).
    private var pendingClip: (([BufferSegment]) -> Void)?
    private var pendingClipSeconds: TimeInterval = 30

    private let segmentsDirectory: URL
    private let exportSnapshotsDirectory: URL

    /// Called on the main queue when reported buffer duration changes.
    var onBufferDurationChange: ((TimeInterval) -> Void)?

    // MARK: - Init

    /// - Parameters:
    ///   - queue: Serial queue used for all recorder work (typically the capture queue).
    ///   - bufferDuration: Trailing window when `retainsFullSession` is false.
    ///   - segmentDuration: Target length of each on-disk segment (default 2s).
    ///   - retainsFullSession: Keep every segment until reset (default true).
    init(
        queue: DispatchQueue,
        bufferDuration: TimeInterval = 30,
        segmentDuration: TimeInterval = 2,
        retainsFullSession: Bool = true
    ) {
        self.queue = queue
        self.bufferDuration = bufferDuration
        self.segmentDuration = segmentDuration
        self.retainsFullSession = retainsFullSession
        let tmp = FileManager.default.temporaryDirectory
        self.segmentsDirectory = tmp.appendingPathComponent(
            "ReplaySegments",
            isDirectory: true
        )
        self.exportSnapshotsDirectory = tmp.appendingPathComponent(
            "ReplayExportSnapshots",
            isDirectory: true
        )
        super.init()
        try? FileManager.default.createDirectory(
            at: segmentsDirectory,
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: exportSnapshotsDirectory,
            withIntermediateDirectories: true
        )
        clearDirectory(segmentsDirectory)
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

        if currentWriter == nil, !isFinishingSegment, pendingFlush == nil {
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

    /// Finishes every in-flight writer, then returns hard-linked copies of the
    /// trailing window so a later `reset` cannot delete files mid-export.
    func flushAndSnapshot(completion: @escaping ([BufferSegment]) -> Void) {
        if let existing = pendingFlush {
            existing([])
        }
        pendingFlush = completion
        if currentWriter != nil {
            closeOpenSegment(discard: false)
        } else {
            tryDeliverPendingFlush()
        }
    }

    /// Seals the open segment, hard-links the trailing `seconds`, and keeps
    /// recording into a new segment. Live session files are left intact.
    func snapshotTrailingClip(
        seconds: TimeInterval,
        completion: @escaping ([BufferSegment]) -> Void
    ) {
        if let existing = pendingClip {
            existing([])
        }
        pendingClipSeconds = max(0.5, seconds)
        pendingClip = completion

        if currentWriter != nil, let pts = lastVideoPTS, !isFinishingSegment {
            rotateSegment(nextPTS: pts)
        }
        tryDeliverPendingClip()
    }

    /// Ends the open segment so the next frame can start with new video settings
    /// (e.g. after an orientation change that swaps frame dimensions).
    func forceRotateSegment() {
        guard let pts = lastVideoPTS, currentWriter != nil, !isFinishingSegment else {
            return
        }
        rotateSegment(nextPTS: pts)
    }

    /// Tear down the open writer and delete all segment files.
    func reset() {
        generation += 1
        if let pending = pendingFlush {
            pendingFlush = nil
            pending([])
        }
        if let clip = pendingClip {
            pendingClip = nil
            clip([])
        }
        if currentWriter != nil {
            closeOpenSegment(discard: true)
        } else {
            clearDirectory(segmentsDirectory)
            segments.removeAll()
            segmentStartPTS = nil
            lastVideoPTS = nil
            isFinishingSegment = pendingFinishCount > 0
            publishDuration()
        }
    }

    /// Deletes an export snapshot directory produced by `flushAndSnapshot`.
    static func cleanupExportSnapshot(_ segments: [BufferSegment]) {
        guard let first = segments.first else { return }
        let dir = first.url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir)
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
        guard let writer = currentWriter else { return }
        let finishedURL = writer.outputURL
        let start = segmentStartPTS ?? nextPTS
        let duration = max(0, CMTimeGetSeconds(CMTimeSubtract(nextPTS, start)))

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        currentWriter = nil
        videoInput = nil
        audioInput = nil
        segmentStartPTS = nil

        startNewSegment(at: nextPTS)
        beginFinish(
            writer: writer,
            url: finishedURL,
            duration: duration,
            discard: false
        )
    }

    private func closeOpenSegment(discard: Bool = false) {
        guard let writer = currentWriter else {
            tryDeliverPendingFlush()
            return
        }

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

        beginFinish(
            writer: writer,
            url: finishedURL,
            duration: duration,
            discard: discard
        )
    }

    private func beginFinish(
        writer: AVAssetWriter,
        url: URL,
        duration: TimeInterval,
        discard: Bool
    ) {
        pendingFinishCount += 1
        isFinishingSegment = true
        let gen = generation

        writer.finishWriting { [weak self] in
            guard let self else { return }
            self.queue.async {
                defer {
                    self.pendingFinishCount = max(0, self.pendingFinishCount - 1)
                    if self.pendingFinishCount == 0 {
                        self.isFinishingSegment = false
                    }
                    self.publishDuration()
                    self.tryDeliverPendingFlush()
                    self.tryDeliverPendingClip()
                }

                guard gen == self.generation else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }

                if discard {
                    try? FileManager.default.removeItem(at: url)
                    self.clearDirectory(self.segmentsDirectory)
                    self.segments.removeAll()
                    self.lastVideoPTS = nil
                    return
                }

                if writer.status == .completed, duration > 0.05 {
                    self.segments.append(
                        BufferSegment(url: url, duration: duration)
                    )
                    self.prune()
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    private func tryDeliverPendingFlush() {
        guard pendingFlush != nil else { return }
        guard pendingFinishCount == 0, currentWriter == nil else { return }

        let completion = pendingFlush
        pendingFlush = nil
        prune()
        let snapshot = makeExportSnapshot(from: segments)
        completion?(snapshot)
    }

    private func tryDeliverPendingClip() {
        guard pendingClip != nil else { return }
        // Allow an open writer (new segment after rotate); only wait on finishes.
        guard pendingFinishCount == 0 else { return }

        let completion = pendingClip
        pendingClip = nil
        let trailing = trailingSegments(seconds: pendingClipSeconds)
        let snapshot = makeExportSnapshot(from: trailing)
        completion?(snapshot)
    }

    /// Finished segments covering the end of the session, oldest → newest.
    private func trailingSegments(seconds: TimeInterval) -> [BufferSegment] {
        guard !segments.isEmpty else { return [] }
        var collected: [BufferSegment] = []
        var total: TimeInterval = 0
        for segment in segments.reversed() {
            collected.insert(segment, at: 0)
            total += segment.duration
            if total >= seconds { break }
        }
        return collected
    }

    /// Hard-links (or copies) segment files so export owns them independently.
    private func makeExportSnapshot(from segments: [BufferSegment]) -> [BufferSegment] {
        guard !segments.isEmpty else { return [] }

        let dir = exportSnapshotsDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        } catch {
            return []
        }

        var snapshot: [BufferSegment] = []
        for segment in segments {
            let dest = dir.appendingPathComponent(segment.url.lastPathComponent)
            do {
                try FileManager.default.linkItem(at: segment.url, to: dest)
                snapshot.append(BufferSegment(url: dest, duration: segment.duration))
            } catch {
                do {
                    try FileManager.default.copyItem(at: segment.url, to: dest)
                    snapshot.append(
                        BufferSegment(url: dest, duration: segment.duration)
                    )
                } catch {
                    continue
                }
            }
        }
        return snapshot
    }

    private func prune() {
        guard !retainsFullSession else { return }
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
        let reported = retainsFullSession ? total : min(total, bufferDuration)
        DispatchQueue.main.async { [weak self] in
            self?.onBufferDurationChange?(reported)
        }
    }

    private func clearDirectory(_ directory: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            try? fm.removeItem(at: file)
        }
    }
}
