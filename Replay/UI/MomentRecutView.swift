//
//  MomentRecutView.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVKit
import SwiftUI

/// Lets the user save the frozen moment to the Replay album again.
struct MomentRecutView: View {
    let moment: ReplayMoment
    var onFinished: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var didSave = false

    private var fileURL: URL {
        MomentStore.shared.fileURL(for: moment)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VideoPlayer(player: AVPlayer(url: fileURL))
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Up to \(Int(moment.duration.rounded(.down)))s from this take.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(
                    "Temporary copy — expires after \(MomentStore.shared.retention.title). Saves to Photos stay."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                Button {
                    saveAgain()
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(didSave ? "Saved" : "Save to Photos")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || didSave)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Last Moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func saveAgain() {
        errorMessage = nil
        isSaving = true
        Task {
            do {
                let cut = try await MomentExporter.exportTrailing(
                    from: fileURL,
                    seconds: moment.duration
                )
                try await PhotoLibrarySaver.saveVideo(at: cut)
                try? FileManager.default.removeItem(at: cut)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                didSave = true
                isSaving = false
                onFinished?()
                dismiss()
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
