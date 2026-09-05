//
//  CameraRollView.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVKit
import Photos
import SwiftUI
import UIKit

/// In-app roll: recent Moments plus videos in the Replay Photos album.
struct CameraRollView: View {
    @ObservedObject var moments: MomentStore
    @StateObject private var library = ReplayAlbumLibrary()
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMoment: ReplayMoment?
    @State private var playingAsset: PHAsset?
    @State private var showPlayer = false
    @State private var showRetentionPicker = false

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !moments.moments.isEmpty {
                        momentsSection
                    }
                    albumSection
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
            .navigationTitle("Replay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Keep \(moments.retention.shortLabel)") {
                        showRetentionPicker = true
                    }
                    .accessibilityLabel(
                        "Moments kept for \(moments.retention.title). Tap to change."
                    )
                }
            }
            .confirmationDialog(
                "Keep Moments for",
                isPresented: $showRetentionPicker,
                titleVisibility: .visible
            ) {
                ForEach(MomentRetention.allCases) { option in
                    Button(option.title) {
                        moments.setRetention(option)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Moments are temporary re-save copies. Photos saves stay until you delete them."
                )
            }
            .task { await library.refresh() }
            .sheet(item: $selectedMoment) { moment in
                MomentRecutView(moment: moment)
            }
            .fullScreenCover(isPresented: $showPlayer) {
                if let playingAsset {
                    AssetViewer(asset: playingAsset)
                }
            }
        }
    }

    // MARK: - Sections

    private var momentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Moments")
                .font(.headline)
            Text(
                "Temporary re-save copies. Kept for \(moments.retention.title), then deleted. Photos saves stay."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(moments.moments) { moment in
                        Button {
                            selectedMoment = moment
                        } label: {
                            MomentCard(
                                moment: moment,
                                retention: moments.retention
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved")
                .font(.headline)

            if library.authorizationDenied {
                Text("Allow Photos access to see your Replay album.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.subheadline.weight(.semibold))
            } else if library.isLimitedAccess {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Photos access is limited. Replay can still save clips; grant full access to see everything in the album.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            if !library.authorizationDenied, library.assets.isEmpty {
                Text("Saved clips show up here and sync with iCloud Photos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            } else if !library.assets.isEmpty {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(library.assets, id: \.localIdentifier) { asset in
                        Button {
                            playingAsset = asset
                            showPlayer = true
                        } label: {
                            AlbumThumbnail(asset: asset, library: library)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Cards

private struct MomentCard: View {
    let moment: ReplayMoment
    let retention: MomentRetention

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let expires = moment.createdAt.addingTimeInterval(retention.seconds)
            let remaining = max(0, expires.timeIntervalSince(context.date))
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.25))
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(moment.duration.rounded(.down)))s")
                        .font(.caption.weight(.semibold))
                    Text(remainingLabel(remaining))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(8)
                .foregroundStyle(.white)
            }
            .frame(width: 120, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func remainingLabel(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let m = total / 60
        if m >= 60 {
            return "\(m / 60)h left"
        }
        if m > 0 {
            return "\(m)m left"
        }
        return "\(total)s left"
    }
}

private struct AlbumThumbnail: View {
    let asset: PHAsset
    @ObservedObject var library: ReplayAlbumLibrary
    @State private var image: UIImage?

    var body: some View {
        Color.secondary.opacity(0.2)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task {
                let scale = UIScreen.main.scale
                image = await library.thumbnail(
                    for: asset,
                    size: CGSize(width: 200 * scale, height: 200 * scale)
                )
            }
    }
}

// MARK: - Viewer

private struct AssetViewer: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if asset.mediaType == .image {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                } else {
                    ProgressView().tint(.white)
                }
            } else if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.35))
                    .padding()
            }
        }
        .task {
            if asset.mediaType == .image {
                image = await requestImage(for: asset)
            } else if let url = await requestURL(for: asset) {
                let avPlayer = AVPlayer(url: url)
                player = avPlayer
                avPlayer.play()
            }
        }
    }

    private func requestImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            var hasResumed = false
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                guard !hasResumed else { return }
                hasResumed = true
                if cancelled {
                    continuation.resume(returning: nil)
                } else if let data {
                    continuation.resume(returning: UIImage(data: data))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func requestURL(for asset: PHAsset) async -> URL? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            var hasResumed = false
            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { avAsset, _, _ in
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: (avAsset as? AVURLAsset)?.url)
            }
        }
    }
}
