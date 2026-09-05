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
    @Published private(set) var retention: MomentRetention = .load()

    private let maxMoments = 3
    private let directory: URL
    private let indexURL: URL

    private init() {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        directory = root.appendingPathComponent("ReplayMoments", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        migrateFromCachesIfNeeded()
        loadIndex()
        pruneExpired()
        persistIndex()
        removeOrphanFiles()
    }

    /// Newest frozen take, if any.
    var latest: ReplayMoment? { moments.first }

    /// Absolute URL for a stored moment.
    func fileURL(for moment: ReplayMoment) -> URL {
        moment.fileURL(in: directory)
    }

    /// Updates how long Moments are kept and prunes immediately.
    func setRetention(_ value: MomentRetention) {
        guard value != retention else { return }
        retention = value
        value.save()
        pruneExpired()
        persistIndex()
    }

    /// When this moment will be deleted.
    func expiresAt(for moment: ReplayMoment) -> Date {
        moment.createdAt.addingTimeInterval(retention.seconds)
    }

    /// Seconds left before expiry (0 if already expired).
    func remainingSeconds(for moment: ReplayMoment, now: Date = Date()) -> TimeInterval {
        max(0, expiresAt(for: moment).timeIntervalSince(now))
    }

    /// Removes expired moments. Safe to call often.
    func pruneExpiredIfNeeded() {
        pruneExpired()
        persistIndex()
        removeOrphanFiles()
    }

    /// Copies `sourceURL` into the moments folder and retains it.
    @discardableResult
    func add(from sourceURL: URL, duration: TimeInterval) throws -> ReplayMoment {
        pruneExpired()
        let moment = ReplayMoment(duration: duration)
        let dest = fileURL(for: moment)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)

        moments.insert(moment, at: 0)
        trimToCap()
        persistIndex()
        return moment
    }

    /// Removes a moment and deletes its file.
    func remove(_ moment: ReplayMoment) {
        moments.removeAll { $0.id == moment.id }
        try? FileManager.default.removeItem(at: fileURL(for: moment))
        persistIndex()
    }

    // MARK: - Private

    private func loadIndex() {
        guard
            let data = try? Data(contentsOf: indexURL),
            let decoded = try? JSONDecoder().decode([ReplayMoment].self, from: data)
        else {
            moments = []
            return
        }
        moments = decoded.filter { moment in
            FileManager.default.fileExists(atPath: fileURL(for: moment).path)
        }
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(moments) else { return }
        try? data.write(to: indexURL, options: [.atomic])
    }

    private func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-retention.seconds)
        let expired = moments.filter { $0.createdAt < cutoff }
        for moment in expired {
            moments.removeAll { $0.id == moment.id }
            try? FileManager.default.removeItem(at: fileURL(for: moment))
        }
    }

    private func removeOrphanFiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        let known = Set(moments.map(\.fileName))
        for file in files {
            let name = file.lastPathComponent
            if name == indexURL.lastPathComponent { continue }
            if !known.contains(name) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func trimToCap() {
        while moments.count > maxMoments {
            let removed = moments.removeLast()
            try? FileManager.default.removeItem(at: fileURL(for: removed))
        }
    }

    /// One-time move from the old Caches location into Application Support.
    private func migrateFromCachesIfNeeded() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReplayMoments", isDirectory: true)
        guard FileManager.default.fileExists(atPath: caches.path) else { return }
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: caches,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )
        else {
            try? FileManager.default.removeItem(at: caches)
            return
        }

        let existing = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        let hasIndex = FileManager.default.fileExists(atPath: indexURL.path)

        if existing.isEmpty || !hasIndex {
            var rebuilt: [ReplayMoment] = []
            for file in files where file.pathExtension.lowercased() == "mp4" {
                let name = file.deletingPathExtension().lastPathComponent
                guard let id = UUID(uuidString: name) else { continue }
                let dest = directory.appendingPathComponent(file.lastPathComponent)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.copyItem(at: file, to: dest)
                }
                let created = (try? file.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate) ?? Date()
                rebuilt.append(
                    ReplayMoment(id: id, createdAt: created, duration: 0)
                )
            }
            if !rebuilt.isEmpty, !hasIndex {
                rebuilt.sort { $0.createdAt > $1.createdAt }
                if let data = try? JSONEncoder().encode(Array(rebuilt.prefix(maxMoments))) {
                    try? data.write(to: indexURL, options: [.atomic])
                }
            }
        }

        try? FileManager.default.removeItem(at: caches)
    }
}
