//
//  PhotoLibrarySaver.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Photos

/// Saves videos into the Photos library under a Replay album.
enum PhotoLibrarySaver {

    static let albumTitle = "Replay"

    enum SaveError: LocalizedError {
        case denied
        case failed(String)
        case albumUnavailable

        var errorDescription: String? {
            switch self {
            case .denied:
                return "Photos access was denied."
            case .failed(let message):
                return message
            case .albumUnavailable:
                return "Could not add to the Replay album."
            }
        }
    }

    /// Requests library access, saves `fileURL`, and adds it to the Replay album.
    static func saveVideo(at fileURL: URL) async throws {
        let status = await requestReadWriteAccess()
        guard status == .authorized || status == .limited else {
            throw SaveError.denied
        }

        let album = try await fetchOrCreateAlbum()
        let localID = try await createVideoAsset(at: fileURL)
        try await addAsset(localIdentifier: localID, to: album)
    }

    /// Saves still image data into the Replay album.
    static func saveImageData(_ data: Data) async throws {
        let status = await requestReadWriteAccess()
        guard status == .authorized || status == .limited else {
            throw SaveError.denied
        }

        let album = try await fetchOrCreateAlbum()
        let localID = try await createPhotoAsset(data: data)
        try await addAsset(localIdentifier: localID, to: album)
    }

    /// Read/write authorization for album + in-app roll.
    static func requestReadWriteAccess() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current != .notDetermined { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Existing Replay album, if present.
    static func fetchAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumTitle)
        return PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: options
        ).firstObject
    }

    // MARK: - Private

    private static func createVideoAsset(at fileURL: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var placeholder: PHObjectPlaceholder?
            PHPhotoLibrary.shared().performChanges {
                let creation = PHAssetCreationRequest.forAsset()
                creation.addResource(with: .video, fileURL: fileURL, options: nil)
                placeholder = creation.placeholderForCreatedAsset
            } completionHandler: { success, error in
                if success, let id = placeholder?.localIdentifier {
                    continuation.resume(returning: id)
                } else {
                    let message = error?.localizedDescription ?? "Could not save to Photos."
                    continuation.resume(throwing: SaveError.failed(message))
                }
            }
        }
    }

    private static func createPhotoAsset(data: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var placeholder: PHObjectPlaceholder?
            PHPhotoLibrary.shared().performChanges {
                let creation = PHAssetCreationRequest.forAsset()
                creation.addResource(with: .photo, data: data, options: nil)
                placeholder = creation.placeholderForCreatedAsset
            } completionHandler: { success, error in
                if success, let id = placeholder?.localIdentifier {
                    continuation.resume(returning: id)
                } else {
                    let message = error?.localizedDescription ?? "Could not save photo."
                    continuation.resume(throwing: SaveError.failed(message))
                }
            }
        }
    }

    private static func addAsset(
        localIdentifier: String,
        to album: PHAssetCollection
    ) async throws {
        let assets = PHAsset.fetchAssets(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        )
        guard assets.count > 0 else {
            throw SaveError.failed("Saved item unavailable.")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let enqueued = AlbumAddFlag()
            PHPhotoLibrary.shared().performChanges {
                guard let change = PHAssetCollectionChangeRequest(for: album) else {
                    return
                }
                change.addAssets(assets as NSFastEnumeration)
                enqueued.value = true
            } completionHandler: { success, error in
                if success, enqueued.value {
                    continuation.resume()
                } else if success {
                    continuation.resume(throwing: SaveError.albumUnavailable)
                } else {
                    let message = error?.localizedDescription
                        ?? "Could not add to the Replay album."
                    continuation.resume(throwing: SaveError.failed(message))
                }
            }
        }
    }

    private static func fetchOrCreateAlbum() async throws -> PHAssetCollection {
        if let existing = fetchAlbum() { return existing }

        var placeholder: PHObjectPlaceholder?
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCollectionChangeRequest
                    .creationRequestForAssetCollection(withTitle: albumTitle)
                placeholder = request.placeholderForCreatedAssetCollection
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    let message = error?.localizedDescription ?? "Could not create Replay album."
                    continuation.resume(throwing: SaveError.failed(message))
                }
            }
        }

        if let existing = fetchAlbum() { return existing }
        if let placeholder,
           let album = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [placeholder.localIdentifier],
            options: nil
           ).firstObject {
            return album
        }
        throw SaveError.failed("Replay album unavailable.")
    }
}

/// Thread-safe flag for Photos change blocks.
private final class AlbumAddFlag: @unchecked Sendable {
    var value = false
}
