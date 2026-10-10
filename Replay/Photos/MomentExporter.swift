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

        // Whole-file keep: hard-link/copy — no export.
        if keep + 0.05 >= total {
            do {
                try FileManager.default.linkItem(at: sourceURL, to: outputURL)
            } catch {
                try FileManager.default.copyItem(at: sourceURL, to: outputURL)
            }
            return outputURL
        }

        do {
            try await ReplayAssetExport.exportMP4(
                asset: asset,
                timeRange: range,
                to: outputURL
            )
            return outputURL
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            throw ExportError.failed(message)
        }
    }
}
