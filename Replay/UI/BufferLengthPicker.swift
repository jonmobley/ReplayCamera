//
//  BufferLengthPicker.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import SwiftUI

/// Compact control to choose how many seconds Replay keeps.
struct BufferLengthPicker: View {
    @Binding var selection: BufferLength
    var isDisabled: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(BufferLength.allCases) { length in
                Button {
                    selection = length
                } label: {
                    Text(length.label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(selection == length ? .black : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selection == length
                                ? Color.white
                                : Color.white.opacity(0.18),
                            in: Capsule()
                        )
                }
                .disabled(isDisabled)
                .accessibilityLabel("Buffer \(length.label)")
            }
        }
        .padding(4)
        .background(.black.opacity(0.45), in: Capsule())
    }
}
