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
    @State private var didSave = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VideoPlayer(player: AVPlayer(url: moment.fileURL))
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Up to \(Int(moment.duration.rounded(.down)))s from this take.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    saveAgain()
                } label: {
                    Text("Save to Photos")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(didSave)

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
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        didSave = true
        Task {
            do {
                let cut = try await MomentExporter.exportTrailing(
                    from: moment.fileURL,
                    seconds: moment.duration
                )
                try await PhotoLibrarySaver.saveVideo(at: cut)
                try? FileManager.default.removeItem(at: cut)
                onFinished?()
                dismiss()
            } catch {
                didSave = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
