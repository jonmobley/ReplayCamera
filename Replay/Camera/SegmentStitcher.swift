//
//  SegmentStitcher.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Foundation

/// Concatenates rolling buffer segments into a single MP4.
enum SegmentStitcher {

    enum StitchError: LocalizedError {
        case empty
        case compositionFailed
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Nothing buffered yet."
            case .compositionFailed:
                return "Could not assemble the clip."
            case .exportFailed(let message):
                return message
            }
        }
    }

    /// Stitches `segments` and keeps only the trailing `seconds` when possible.
    /// - Parameters:
    ///   - segments: Finished segments covering the rolling window.
    ///   - seconds: Desired clip length from the end of the buffer.
    /// - Returns: File URL of the exported clip (caller may delete after save).
    static func stitch(
        _ segments: [BufferSegment],
        trailingSeconds seconds: TimeInterval
    ) async throws -> URL {
        guard !segments.isEmpty else { throw StitchError.empty }

        let composition = AVMutableComposition()
        guard
            let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else { throw StitchError.compositionFailed }

        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var cursor = CMTime.zero
        for segment in segments {
            let asset = AVURLAsset(url: segment.url)
            let duration = try await asset.load(.duration)
            let timeRange = CMTimeRange(start: .zero, duration: duration)

            if let sourceVideo = try await asset.loadTracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(timeRange, of: sourceVideo, at: cursor)
                let transform = try await sourceVideo.load(.preferredTransform)
                videoTrack.preferredTransform = transform
            }

            if let audioTrack,
               let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                try audioTrack.insertTimeRange(timeRange, of: sourceAudio, at: cursor)
            }

            cursor = CMTimeAdd(cursor, duration)
        }

        guard cursor > .zero else { throw StitchError.empty }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Replay-\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw StitchError.exportFailed("Export session unavailable.")
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.timeRange = trailingTimeRange(
            total: cursor,
            seconds: seconds
        )

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously {
                continuation.resume()
            }
        }

        switch exporter.status {
        case .completed:
            return outputURL
        case .failed:
            let message = exporter.error?.localizedDescription ?? "Export failed."
            throw StitchError.exportFailed(message)
        case .cancelled:
            throw StitchError.exportFailed("Export cancelled.")
        default:
            throw StitchError.exportFailed("Unexpected export status.")
        }
    }

    // MARK: - Private

    private static func trailingTimeRange(
        total: CMTime,
        seconds: TimeInterval
    ) -> CMTimeRange {
        let keep = CMTime(
            seconds: max(0.1, seconds),
            preferredTimescale: 600
        )
        if keep >= total {
            return CMTimeRange(start: .zero, duration: total)
        }
        let start = CMTimeSubtract(total, keep)
        return CMTimeRange(start: start, duration: keep)
    }
}
