//
//  MomentRecutView.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVKit
import SwiftUI

/// Lets the user re-save a frozen moment (full or trailing cut) to Photos.
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

    private var exportOptions: [MomentExportOption] {
        MomentExportOption.available(forDuration: moment.duration)
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

                VStack(spacing: 10) {
                    ForEach(exportOptions) { option in
                        Button {
                            save(option)
                        } label: {
                            Text(didSave ? "Saved" : option.title)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving || didSave)
                    }
                    if isSaving {
                        ProgressView()
                            .padding(.top, 4)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func save(_ option: MomentExportOption) {
        errorMessage = nil
        isSaving = true
        let seconds = option.secondsToExport(from: moment.duration)
        Task {
            do {
                let cut = try await MomentExporter.exportTrailing(
                    from: fileURL,
                    seconds: seconds
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
