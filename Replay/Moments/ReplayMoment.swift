//
//  ReplayMoment.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// A frozen take kept briefly so the user can save it again.
struct ReplayMoment: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let duration: TimeInterval
    let fileURL: URL
}
