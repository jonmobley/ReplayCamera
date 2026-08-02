//
//  BufferLength.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Selectable trailing-window lengths for the rolling buffer.
enum BufferLength: Int, CaseIterable, Identifiable {
    case five = 5
    case ten = 10
    case fifteen = 15
    case thirty = 30

    var id: Int { rawValue }

    /// Seconds to retain before Save.
    var seconds: TimeInterval { TimeInterval(rawValue) }

    /// Short label for the control (e.g. "15s").
    var label: String { "\(rawValue)s" }

    private static let defaultsKey = "replay.bufferLength"

    /// Persisted preference, defaulting to 15 seconds.
    static var stored: BufferLength {
        get {
            let raw = UserDefaults.standard.integer(forKey: defaultsKey)
            return BufferLength(rawValue: raw) ?? .fifteen
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }
}
