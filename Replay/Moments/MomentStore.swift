//
//  MomentStore.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Keeps a short list of frozen takes on disk for quick re-cuts.
@MainActor
final class MomentStore: ObservableObject {
    static let shared = MomentStore()

    @Published private(set) var moments: [ReplayMoment] = []

    private let maxMoments = 3
    private let maxAge: TimeInterval = 30 * 60
    private let directory: URL

    private init() {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReplayMoments", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        pruneExpired()
    }

    /// Newest frozen take, if any.
    var latest: ReplayMoment? { moments.first }

    /// Copies `sourceURL` into the moments folder and retains it.
    @discardableResult
    func add(from sourceURL: URL, duration: TimeInterval) throws -> ReplayMoment {
        pruneExpired()
        let id = UUID()
        let dest = directory
            .appendingPathComponent(id.uuidString)
            .appendingPathExtension("mp4")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)

        let moment = ReplayMoment(
            id: id,
            createdAt: Date(),
            duration: duration,
            fileURL: dest
        )
        moments.insert(moment, at: 0)
        trimToCap()
        return moment
    }

    /// Removes a moment and deletes its file.
    func remove(_ moment: ReplayMoment) {
        moments.removeAll { $0.id == moment.id }
        try? FileManager.default.removeItem(at: moment.fileURL)
    }

    // MARK: - Private

    private func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        let expired = moments.filter { $0.createdAt < cutoff }
        for moment in expired {
            remove(moment)
        }
        // Also drop orphan files with no matching moment.
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        let known = Set(moments.map(\.fileURL.lastPathComponent))
        for file in files where !known.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func trimToCap() {
        while moments.count > maxMoments {
            let removed = moments.removeLast()
            try? FileManager.default.removeItem(at: removed.fileURL)
        }
    }
}
