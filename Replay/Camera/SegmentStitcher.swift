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

        // Single segment + keep-all: hard-link/copy, no re-encode.
        if segments.count == 1,
           seconds + 0.05 >= segments[0].duration {
            return try duplicate(segments[0].url)
        }

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

        let range = trailingTimeRange(total: cursor, seconds: seconds)
        do {
            try await ReplayAssetExport.exportMP4(
                asset: composition,
                timeRange: range,
                to: outputURL
            )
            return outputURL
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            throw StitchError.exportFailed(message)
        }
    }

    // MARK: - Private

    private static func duplicate(_ url: URL) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Replay-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        do {
            try FileManager.default.linkItem(at: url, to: outputURL)
        } catch {
            try FileManager.default.copyItem(at: url, to: outputURL)
        }
        return outputURL
    }

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
