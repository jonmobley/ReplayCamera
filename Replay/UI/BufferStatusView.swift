//
//  BufferStatusView.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import SwiftUI

/// Shows how full the rolling buffer is.
struct BufferStatusView: View {
    let bufferedSeconds: TimeInterval
    let targetSeconds: TimeInterval

    private var isReady: Bool {
        bufferedSeconds >= targetSeconds - 0.25
    }

    private var label: String {
        if bufferedSeconds < 0.5 {
            return "Buffering…"
        }
        if isReady {
            return "Ready · last \(Int(targetSeconds))s"
        }
        let current = format(bufferedSeconds)
        let target = format(targetSeconds)
        return "\(current) / \(target)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isReady ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.45), in: Capsule())
        .accessibilityLabel(label)
    }

    private func format(_ seconds: TimeInterval) -> String {
        let clamped = max(0, Int(seconds.rounded(.down)))
        let m = clamped / 60
        let s = clamped % 60
        return String(format: "%d:%02d", m, s)
    }
}
