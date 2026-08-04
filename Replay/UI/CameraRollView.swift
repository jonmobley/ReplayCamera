//
//  CameraRollView.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVKit
import Photos
import SwiftUI

/// In-app roll: recent Moments plus videos in the Replay Photos album.
struct CameraRollView: View {
    @ObservedObject var moments: MomentStore
    @StateObject private var library = ReplayAlbumLibrary()
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMoment: ReplayMoment?
    @State private var playingAsset: PHAsset?
    @State private var showPlayer = false

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
            }
            .task { await library.refresh() }
            .sheet(item: $selectedMoment) { moment in
                MomentRecutView(moment: moment)
            }
            .fullScreenCover(isPresented: $showPlayer) {
                if let playingAsset {
                    AssetPlayerView(asset: playingAsset)
                }
            }
        }
    }

    // MARK: - Sections

    private var momentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Moments")
                .font(.headline)
            Text("Still re-cuttable for a little while.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(moments.moments) { moment in
                        Button {
                            selectedMoment = moment
                        } label: {
                            MomentCard(moment: moment)
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
            } else if library.assets.isEmpty {
                Text("Saved clips show up here and sync with iCloud Photos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            } else {
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

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.25))
            Image(systemName: "film")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("\(Int(moment.duration.rounded(.down)))s")
                .font(.caption.weight(.semibold))
                .padding(8)
                .foregroundStyle(.white)
        }
        .frame(width: 120, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

// MARK: - Player

private struct AssetPlayerView: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player {
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
            if let url = await requestURL(for: asset) {
                let avPlayer = AVPlayer(url: url)
                player = avPlayer
                avPlayer.play()
            }
        }
    }

    private func requestURL(for asset: PHAsset) async -> URL? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { avAsset, _, _ in
                continuation.resume(returning: (avAsset as? AVURLAsset)?.url)
            }
        }
    }
}
