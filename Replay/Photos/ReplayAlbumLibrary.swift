//
//  ReplayAlbumLibrary.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Photos
import UIKit

/// Loads videos from the Replay Photos album for the in-app roll.
@MainActor
final class ReplayAlbumLibrary: NSObject, ObservableObject {
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var authorizationDenied = false

    private let imageManager = PHCachingImageManager()
    private var observerRegistered = false

    /// Requests access and refreshes the album contents.
    func refresh() async {
        let status = await PhotoLibrarySaver.requestReadWriteAccess()
        guard status == .authorized || status == .limited else {
            authorizationDenied = true
            assets = []
            return
        }
        authorizationDenied = false
        registerObserverIfNeeded()
        reloadAssets()
    }

    /// Thumbnail for a library asset.
    func thumbnail(for asset: PHAsset, size: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            imageManager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Private

    private func reloadAssets() {
        guard let album = PhotoLibrarySaver.fetchAlbum() else {
            assets = []
            return
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        let result = PHAsset.fetchAssets(in: album, options: options)
        var next: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            next.append(asset)
        }
        assets = next
    }

    private func registerObserverIfNeeded() {
        guard !observerRegistered else { return }
        PHPhotoLibrary.shared().register(self)
        observerRegistered = true
    }
}

extension ReplayAlbumLibrary: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.reloadAssets()
        }
    }
}
