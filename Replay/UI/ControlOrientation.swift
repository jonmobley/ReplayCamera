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
    ///
    /// Uses UIDeviceOrientation semantics: in `.landscapeLeft` the device's left edge
    /// is the visual bottom, so the visual top is the trailing edge.
    static func contentAngle(for orientation: UIDeviceOrientation) -> Angle {
        switch orientation {
        case .landscapeLeft:
            return .degrees(-90)
        case .landscapeRight:
            return .degrees(90)
        case .portraitUpsideDown:
            return .degrees(180)
        default:
            return .zero
        }
    }

    /// Frame alignment for chrome that should sit at the visual top of the device.
    static func topAlignment(for orientation: UIDeviceOrientation) -> Alignment {
        switch orientation {
        case .landscapeLeft:
            return .trailing
        case .landscapeRight:
            return .leading
        case .portraitUpsideDown:
            return .bottom
        default:
            return .top
        }
    }

    /// Visual top-leading corner in portrait-locked coordinates.
    static func topLeadingAlignment(for orientation: UIDeviceOrientation) -> Alignment {
        switch orientation {
        case .landscapeLeft:
            return .topTrailing
        case .landscapeRight:
            return .bottomLeading
        case .portraitUpsideDown:
            return .bottomTrailing
        default:
            return .topLeading
        }
    }

    /// Inset from the visual top edge in portrait-locked coordinates.
    static func topEdgePadding(for orientation: UIDeviceOrientation) -> EdgeInsets {
        switch orientation {
        case .landscapeLeft:
            return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16)
        case .landscapeRight:
            return EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0)
        case .portraitUpsideDown:
            return EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0)
        default:
            return EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 0)
        }
    }

    /// Inset for chrome parked at the visual top-leading corner.
    static func topLeadingPadding(for orientation: UIDeviceOrientation) -> EdgeInsets {
        switch orientation {
        case .landscapeLeft:
            return EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 16)
        case .landscapeRight:
            return EdgeInsets(top: 0, leading: 16, bottom: 20, trailing: 0)
        case .portraitUpsideDown:
            return EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 20)
        default:
            return EdgeInsets(top: 16, leading: 20, bottom: 0, trailing: 0)
        }
    }

    @MainActor
    static func currentAngle() -> Angle {
        contentAngle(for: UIDevice.current.orientation)
    }

    /// Landscape chrome keeps HD / mic / torch on one visual-top row.
    static func isLandscapeChrome(_ orientation: UIDeviceOrientation) -> Bool {
        orientation == .landscapeLeft || orientation == .landscapeRight
    }
}

/// Observes device orientation for chrome glyph rotation.
@MainActor
final class DeviceOrientationObserver: ObservableObject {
    @Published private(set) var deviceOrientation: UIDeviceOrientation = .portrait
    @Published private(set) var angle: Angle = .zero

    /// When true, ignores device turns so chrome stays fixed for the take.
    var isLocked = false {
        didSet {
            guard oldValue, !isLocked else { return }
            applyCurrentDeviceOrientation()
        }
    }

    private var orientationObserver: NSObjectProtocol?

    init() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        applyCurrentDeviceOrientation()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleOrientationChange()
            }
        }
    }

    deinit {
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
        }
    }

    private func handleOrientationChange() {
        guard !isLocked else { return }
        applyCurrentDeviceOrientation()
    }

    private func applyCurrentDeviceOrientation() {
        let next = UIDevice.current.orientation
        guard next.isValidInterfaceOrientation || next.isLandscape || next.isPortrait else {
            return
        }
        deviceOrientation = next
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
