//
//  CaptureSessionController+DeviceControls.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

extension CaptureSessionController {

    // MARK: - Zoom

    /// Pinch-to-zoom like iOS Camera (scale is relative to gesture begin).
    func handlePinchZoom(state: UIGestureRecognizer.State, scale: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            switch state {
            case .began:
                self.pinchZoomBase = self.videoDeviceInput?.device.videoZoomFactor ?? 1
            case .changed:
                self.setZoomFactorLocked(self.pinchZoomBase * scale)
            default:
                break
            }
        }
    }

    func setZoomFactorLocked(_ factor: CGFloat) {
        guard let device = videoDeviceInput?.device else { return }
        let minimum = device.minAvailableVideoZoomFactor
        let maximum = min(device.maxAvailableVideoZoomFactor, max(minimum, 10))
        let clamped = min(max(factor, minimum), maximum)
        do {
            if abs(device.videoZoomFactor - clamped) > 0.001 {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            }
            Task { @MainActor in
                self.zoomFactor = clamped
            }
        } catch {
            // Zoom is best-effort.
        }
    }

    // MARK: - Focus / torch / mic

    /// Tap-to-focus and exposure at a preview-layer point.
    func focusAndExpose(at layerPoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = self.videoDeviceInput?.device
            else { return }

            let devicePoint = self.previewLayer.captureDevicePointConverted(
                fromLayerPoint: layerPoint
            )
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    }
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    if device.isExposureModeSupported(.autoExpose) {
                        device.exposureMode = .autoExpose
                    }
                }
                if device.isSubjectAreaChangeMonitoringEnabled == false {
                    device.isSubjectAreaChangeMonitoringEnabled = true
                }
                device.unlockForConfiguration()
            } catch {
                // Focus is best-effort.
            }
        }
    }

    /// Toggles the torch when the back camera supports it.
    @MainActor
    func toggleTorch() {
        guard canToggleTorch else { return }
        let turnOn = !isTorchOn
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = self.videoDeviceInput?.device,
                  device.hasTorch
            else { return }
            do {
                try device.lockForConfiguration()
                if turnOn {
                    try device.setTorchModeOn(level: 1)
                } else {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
                Task { @MainActor in
                    self.isTorchOn = turnOn
                }
            } catch {
                Task { @MainActor in
                    self.statusMessage = "Torch unavailable."
                    self.scheduleStatusClear()
                }
            }
        }
    }

    /// Mutes microphone samples without tearing down the session.
    @MainActor
    func toggleMicMute() {
        guard !permissionDenied else { return }
        let muted = !isMicMuted
        isMicMuted = muted
        sessionQueue.async { [weak self] in
            self?.isMicMutedLocked = muted
        }
        statusMessage = muted ? "Mic muted" : "Mic on"
        scheduleStatusClear()
    }

    func publishTorchAvailabilityLocked() {
        let device = videoDeviceInput?.device
        let available = device?.hasTorch == true
            && device?.position == .back
        if !available, device?.torchMode == .on {
            try? device?.lockForConfiguration()
            device?.torchMode = .off
            device?.unlockForConfiguration()
        }
        let on = available && device?.torchMode == .on
        Task { @MainActor in
            self.isTorchAvailable = available
            self.isTorchOn = on
        }
    }
}
