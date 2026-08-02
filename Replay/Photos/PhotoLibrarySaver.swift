//
//  PhotoLibrarySaver.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Photos

/// Saves a local video file into the Photos library.
enum PhotoLibrarySaver {

    enum SaveError: LocalizedError {
        case denied
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .denied:
                return "Photos access was denied."
            case .failed(let message):
                return message
            }
        }
    }

    /// Requests add-only Photos access if needed, then writes `fileURL`.
    static func saveVideo(at fileURL: URL) async throws {
        let status = await requestAddOnlyAccess()
        guard status == .authorized || status == .limited else {
            throw SaveError.denied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(
                    with: .video,
                    fileURL: fileURL,
                    options: nil
                )
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    let message = error?.localizedDescription ?? "Could not save to Photos."
                    continuation.resume(throwing: SaveError.failed(message))
                }
            }
        }
    }

    // MARK: - Private

    private static func requestAddOnlyAccess() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
