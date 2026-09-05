//
//  CaptureSessionController+Interruptions.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

@preconcurrency import AVFoundation
import UIKit

extension CaptureSessionController {

    func installInterruptionObservers() {
        removeInterruptionObservers()
        let center = NotificationCenter.default

        interruptionObservers = [
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleExternalInterruption()
                }
            },
            center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: captureSession,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleExternalInterruption()
                }
            },
            center.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification,
                object: captureSession,
                queue: .main
            ) { [weak self] _ in
                self?.resumeCaptureIfNeeded()
            },
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.resumeCaptureIfNeeded()
            }
        ]
    }

    func removeInterruptionObservers() {
        let center = NotificationCenter.default
        interruptionObservers.forEach { center.removeObserver($0) }
        interruptionObservers.removeAll()
    }
}
