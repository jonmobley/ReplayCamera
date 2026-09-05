//
//  MomentRetention.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// How long a frozen Moment stays available for re-save.
enum MomentRetention: Int, CaseIterable, Codable, Identifiable {
    case minutes15 = 15
    case minutes30 = 30
    case hour1 = 60
    case hours2 = 120

    var id: Int { rawValue }

    var seconds: TimeInterval { TimeInterval(rawValue * 60) }

    /// Short label for chrome (e.g. "30m").
    var shortLabel: String {
        switch self {
        case .minutes15, .minutes30:
            return "\(rawValue)m"
        case .hour1:
            return "1h"
        case .hours2:
            return "2h"
        }
    }

    /// Dialog / accessibility title.
    var title: String {
        switch self {
        case .minutes15: return "15 minutes"
        case .minutes30: return "30 minutes"
        case .hour1: return "1 hour"
        case .hours2: return "2 hours"
        }
    }

    private static let defaultsKey = "Replay.momentRetention"

    static let `default`: MomentRetention = .minutes30

    static func load() -> MomentRetention {
        let raw = UserDefaults.standard.integer(forKey: defaultsKey)
        return MomentRetention(rawValue: raw) ?? .default
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}
