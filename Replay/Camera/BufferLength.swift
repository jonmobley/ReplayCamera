//
//  BufferLength.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Save-duration options for Replay clips.
enum BufferLength: Int, CaseIterable, Identifiable {
    case five = 5
    case ten = 10
    case fifteen = 15
    case thirty = 30

    var id: Int { rawValue }

    /// Seconds represented by this option.
    var seconds: TimeInterval { TimeInterval(rawValue) }

    /// Settings label, e.g. "30 seconds".
    var settingsTitle: String { "\(rawValue) seconds" }

    /// Maximum trailing window kept while the camera is open.
    static let maxBufferSeconds: TimeInterval = 30

    private static let defaultsKey = "replay.defaultSaveLength"

    /// User’s preferred Save length (defaults to 30 seconds).
    static var preferredSaveLength: BufferLength {
        get {
            let raw = UserDefaults.standard.integer(forKey: defaultsKey)
            return BufferLength(rawValue: raw) ?? .thirty
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    /// Effective seconds to export given how much is actually buffered.
    static func exportSeconds(buffered: TimeInterval) -> TimeInterval {
        min(preferredSaveLength.seconds, max(0, buffered))
    }
}
