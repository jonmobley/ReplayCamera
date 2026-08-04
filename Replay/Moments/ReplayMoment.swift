//
//  ReplayMoment.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// A frozen take kept briefly so the user can export another length.
struct ReplayMoment: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let duration: TimeInterval
    let fileURL: URL

    /// Lengths that can still be cut from this moment.
    var availableLengths: [BufferLength] {
        BufferLength.allCases.filter { $0.seconds <= duration + 0.25 }
    }
}
