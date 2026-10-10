//
//  FirstRunTipStore.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// One-time tip for the start → stop → auto-save flow.
enum FirstRunTipStore {
    private static let key = "Replay.didShowFirstRunTip"

    static var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: key)
    }

    static func markShown() {
        UserDefaults.standard.set(true, forKey: key)
    }
}
