//
//  ReplayMoment.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// A frozen take kept briefly so the user can save it again.
struct ReplayMoment: Identifiable, Equatable, Codable {
    let id: UUID
    let createdAt: Date
    let duration: TimeInterval
    /// File name only (`{id}.mp4`); resolved against the Moments directory.
    let fileName: String

    /// Builds a moment that will live at `id.mp4` in the store directory.
    init(id: UUID = UUID(), createdAt: Date = Date(), duration: TimeInterval) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.fileName = id.uuidString + ".mp4"
    }

    /// Absolute file URL inside `directory`.
    func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }
}
