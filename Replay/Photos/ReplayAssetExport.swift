//
//  ReplayAssetExport.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Foundation

/// Fast local MP4 export: passthrough when possible, otherwise a single re-encode.
enum ReplayAssetExport {

    enum ExportError: LocalizedError {
        case unavailable
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Export session unavailable."
            case .failed(let message):
                return message
            }
        }
    }

    /// Exports `asset` (optionally trimmed) to `outputURL` as MP4.
    static func exportMP4(
        asset: AVAsset,
        timeRange: CMTimeRange?,
        to outputURL: URL
    ) async throws {
        let presets = [
            AVAssetExportPresetPassthrough,
            AVAssetExportPresetHEVCHighestQuality,
            AVAssetExportPresetHighestQuality
        ]

        var lastError: String?
        for preset in presets {
            guard let exporter = AVAssetExportSession(
                asset: asset,
                presetName: preset
            ) else { continue }
            guard exporter.supportedFileTypes.contains(.mp4) else { continue }

            exporter.outputURL = outputURL
            exporter.outputFileType = .mp4
            exporter.shouldOptimizeForNetworkUse = false
            if let timeRange {
                exporter.timeRange = timeRange
            }

            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                exporter.exportAsynchronously { cont.resume() }
            }

            switch exporter.status {
            case .completed:
                return
            case .failed:
                lastError = exporter.error?.localizedDescription ?? "Export failed."
                try? FileManager.default.removeItem(at: outputURL)
            case .cancelled:
                throw ExportError.failed("Export cancelled.")
            default:
                lastError = "Unexpected export status."
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        throw ExportError.failed(lastError ?? "Export session unavailable.")
    }
}
