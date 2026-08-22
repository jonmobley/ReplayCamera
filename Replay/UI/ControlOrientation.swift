//
//  ControlOrientation.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import SwiftUI
import UIKit

/// Keeps chrome fixed in portrait layout while rotating glyphs with the device.
enum ControlOrientation {
    /// Rotation applied to icons/labels so they stay upright when held in landscape.
    static func contentAngle(for orientation: UIDeviceOrientation) -> Angle {
        switch orientation {
        case .landscapeLeft:
            return .degrees(90)
        case .landscapeRight:
            return .degrees(-90)
        case .portraitUpsideDown:
            return .degrees(180)
        default:
            return .zero
        }
    }

    static func currentAngle() -> Angle {
        contentAngle(for: UIDevice.current.orientation)
    }
}

/// Observes device orientation for chrome glyph rotation.
@MainActor
final class DeviceOrientationObserver: ObservableObject {
    @Published private(set) var angle: Angle = .zero

    init() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        angle = ControlOrientation.currentAngle()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    @objc private func orientationDidChange() {
        let next = UIDevice.current.orientation
        guard next.isValidInterfaceOrientation || next.isLandscape || next.isPortrait else {
            return
        }
        angle = ControlOrientation.contentAngle(for: next)
    }
}

private extension UIDeviceOrientation {
    var isValidInterfaceOrientation: Bool {
        switch self {
        case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight:
            return true
        default:
            return false
        }
    }
}
