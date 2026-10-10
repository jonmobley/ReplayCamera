//
//  MomentExportOption.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Trailing cuts offered when re-saving a Moment to Photos.
enum MomentExportOption: String, Identifiable, Equatable {
    case thirty
    case sixty
    case full

    var id: String { rawValue }

    /// Button title.
    var title: String {
        switch self {
        case .thirty: return "Last 30 Seconds"
        case .sixty: return "Last 60 Seconds"
        case .full: return "Full Moment"
        }
    }

    /// Trailing seconds to keep; `nil` means the entire moment.
    var trailingSeconds: TimeInterval? {
        switch self {
        case .thirty: return 30
        case .sixty: return 60
        case .full: return nil
        }
    }

    /// Seconds to export from a moment of `duration`.
    func secondsToExport(from duration: TimeInterval) -> TimeInterval {
        if let trailing = trailingSeconds {
            return min(trailing, duration)
        }
        return duration
    }

    /// Options available for a moment of the given length.
    static func available(forDuration duration: TimeInterval) -> [MomentExportOption] {
        var options: [MomentExportOption] = []
        if duration >= 29.5 { options.append(.thirty) }
        if duration >= 59.5 { options.append(.sixty) }
        options.append(.full)
        return options
    }
}
