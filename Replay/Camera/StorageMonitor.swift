//
//  StorageMonitor.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Free-space checks for soft low-storage warnings (never auto-stops).
enum StorageMonitor {
    /// Warn when important free capacity drops below this (800 MB).
    static let warningThresholdBytes: Int64 = 800 * 1024 * 1024

    /// Free bytes available for important usage, if the system reports it.
    static func freeDiskBytes(
        homeURL: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) -> Int64? {
        let values = try? homeURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let capacity = values?.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return Int64(capacity)
    }

    /// Whether free space is below the soft warning threshold.
    static func isLowOnSpace(
        freeBytes: Int64? = freeDiskBytes(),
        threshold: Int64 = warningThresholdBytes
    ) -> Bool {
        guard let freeBytes else { return false }
        return freeBytes < threshold
    }
}
