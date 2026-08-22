//
//  SaveOption.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Choices shown after the user stops a recording.
enum SaveOption: String, Identifiable, Equatable {
    case thirty
    case sixty
    case full

    var id: String { rawValue }

    /// Dialog button title.
    var title: String {
        switch self {
        case .thirty: return "Last 30 Seconds"
        case .sixty: return "Last 60 Seconds"
        case .full: return "Full Recording"
        }
    }

    /// Trailing seconds to keep; `nil` means the entire session.
    var trailingSeconds: TimeInterval? {
        switch self {
        case .thirty: return 30
        case .sixty: return 60
        case .full: return nil
        }
    }

    /// Options available for a given session length.
    static func available(forSessionSeconds seconds: TimeInterval) -> [SaveOption] {
        var options: [SaveOption] = []
        if seconds >= 29.5 { options.append(.thirty) }
        if seconds >= 59.5 { options.append(.sixty) }
        options.append(.full)
        return options
    }
}
