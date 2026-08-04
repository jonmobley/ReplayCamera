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

        var errorDescription: String? {
            switch self {
            case .denied:
                return "Photos access was denied."
            case .failed(let message):
                return message
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let creation = PHAssetCreationRequest.forAsset()
                creation.addResource(with: .video, fileURL: fileURL, options: nil)
                guard
                    let albumChange = PHAssetCollectionChangeRequest(for: album),
                    let placeholder = creation.placeholderForCreatedAsset
                else { return }
                albumChange.addAssets([placeholder] as NSArray)
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
