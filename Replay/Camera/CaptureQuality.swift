//
//  CaptureQuality.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Recording resolution toggled from the camera chrome.
enum CaptureResolution: String, CaseIterable, Codable {
    case hd
    case fourK

    var label: String {
        switch self {
        case .hd: return "HD"
        case .fourK: return "4K"
        }
    }

    var width: Int32 {
        switch self {
        case .hd: return 1920
        case .fourK: return 3840
        }
    }

    var height: Int32 {
        switch self {
        case .hd: return 1080
        case .fourK: return 2160
        }
    }
}

/// Recording frame rate toggled from the camera chrome.
enum CaptureFrameRate: Int, CaseIterable, Codable {
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60

    var label: String { "\(rawValue)" }

    /// Next rate in the 24 → 30 → 60 cycle.
    var next: CaptureFrameRate {
        switch self {
        case .fps24: return .fps30
        case .fps30: return .fps60
        case .fps60: return .fps24
        }
    }
}

/// Persisted capture quality preference.
struct CaptureQualityPreference: Codable, Equatable {
    var resolution: CaptureResolution
    var frameRate: CaptureFrameRate

    static let `default` = CaptureQualityPreference(
        resolution: .hd,
        frameRate: .fps30
    )

    private static let defaultsKey = "Replay.captureQuality"

    static func load() -> CaptureQualityPreference {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let value = try? JSONDecoder().decode(Self.self, from: data)
        else {
            return .default
        }
        return value
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
