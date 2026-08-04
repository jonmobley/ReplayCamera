//
//  MomentRecutView.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVKit
import SwiftUI

/// Lets the user export another length from a frozen moment.
struct MomentRecutView: View {
    let moment: ReplayMoment
    var onFinished: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var isExporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VideoPlayer(player: AVPlayer(url: moment.fileURL))
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Save another length from this take.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                ForEach(moment.availableLengths) { length in
                    Button {
                        export(length)
                    } label: {
                        Text(length.saveActionTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting)
                }

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
            .overlay {
                if isExporting {
                    ProgressView("Saving…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func export(_ length: BufferLength) {
        isExporting = true
        errorMessage = nil
        Task {
            do {
                let cut = try await MomentExporter.exportTrailing(
                    from: moment.fileURL,
                    seconds: length.seconds
                )
                try await PhotoLibrarySaver.saveVideo(at: cut)
                try? FileManager.default.removeItem(at: cut)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                isExporting = false
                onFinished?()
                dismiss()
            } catch {
                isExporting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
