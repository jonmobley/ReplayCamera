//
//  SettingsView.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import SwiftUI

/// Lightweight preferences for Save behavior.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var saveLength = BufferLength.preferredSaveLength

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Save Length", selection: $saveLength) {
                        ForEach(BufferLength.allCases) { length in
                            Text(length.settingsTitle).tag(length)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Default Save Length")
                } footer: {
                    Text(
                        "When you tap Save, Replay keeps this much from the end of the buffer. If less is ready, it saves what’s available."
                    )
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: saveLength) { _, newValue in
                BufferLength.preferredSaveLength = newValue
            }
        }
    }
}
