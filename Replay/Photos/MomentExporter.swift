//
//  MomentExporter.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Foundation

/// Exports a trailing cut from a frozen moment file.
enum MomentExporter {

    enum ExportError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message):
                return message
            }
        }
    }

    /// Writes the last `seconds` of `sourceURL` to a temp MP4.
    static func exportTrailing(
        from sourceURL: URL,
        seconds: TimeInterval
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let total = CMTimeGetSeconds(duration)
        let keep = min(max(0.1, seconds), total)
        let start = CMTime(
            seconds: max(0, total - keep),
            preferredTimescale: 600
        )
        let range = CMTimeRange(
            start: start,
            duration: CMTime(seconds: keep, preferredTimescale: 600)
        )

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplayCut-\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.failed("Export session unavailable.")
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.timeRange = range
        exporter.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously { continuation.resume() }
        }

        switch exporter.status {
        case .completed:
            return outputURL
        case .failed:
            throw ExportError.failed(
                exporter.error?.localizedDescription ?? "Export failed."
            )
        case .cancelled:
            throw ExportError.failed("Export cancelled.")
        default:
            throw ExportError.failed("Unexpected export status.")
        }
    }
}
