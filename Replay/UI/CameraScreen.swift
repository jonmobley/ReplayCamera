//
//  CameraScreen.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import SwiftUI
import UIKit

/// Full-bleed camera: preview, roll, start/stop shutter, flip, moment.
struct CameraScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = CaptureSessionController()
    @StateObject private var orientation = DeviceOrientationObserver()
    @ObservedObject private var moments = MomentStore.shared

    @State private var showRoll = false
    @State private var showMomentRecut = false
    @State private var showFirstRunTip = FirstRunTipStore.shouldShow
    @State private var focusPoint: CGPoint?
    @State private var showZoomBadge = false

    var body: some View {
        ZStack {
            CameraPreviewView(
                previewLayer: camera.previewLayer,
                onPinchZoom: { state, scale in
                    camera.handlePinchZoom(state: state, scale: scale)
                    if state == .began || state == .changed {
                        showZoomBadge = true
                    }
                },
                onTapFocus: { point in
                    camera.focusAndExpose(at: point)
                    withAnimation(.easeOut(duration: 0.15)) {
                        focusPoint = point
                    }
                }
            )
            .ignoresSafeArea()

            if camera.permissionDenied {
                permissionOverlay
            }

            if let focusPoint {
                FocusReticle()
                    .position(focusPoint)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if isLandscapeChrome {
                landscapeTopChrome
            }

            VStack {
                headerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Spacer()

                if showZoomBadge || camera.zoomFactor > 1.05 {
                    zoomBadge
                        .rotationEffect(orientation.angle)
                        .padding(.bottom, 12)
                }

                controls
                    .padding(.horizontal, 28)
                    .padding(.bottom, 0)
            }

            if camera.isRecording {
                recordingTimer
                    .rotationEffect(orientation.angle)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: ControlOrientation.topAlignment(
                            for: orientation.deviceOrientation
                        )
                    )
                    .padding(
                        ControlOrientation.topEdgePadding(
                            for: orientation.deviceOrientation
                        )
                    )
                    .transition(.opacity)
            }

            if let message = camera.statusMessage {
                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .rotationEffect(orientation.angle)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: camera.statusMessage)
        .animation(.easeInOut(duration: 0.2), value: camera.isRecording)
        .animation(.easeInOut(duration: 0.2), value: moments.latest?.id)
        .animation(.easeInOut(duration: 0.2), value: orientation.angle)
        .animation(.easeInOut(duration: 0.2), value: orientation.deviceOrientation)
        .animation(.easeInOut(duration: 0.15), value: camera.zoomFactor)
        .confirmationDialog(
            "Save Recording?",
            isPresented: saveDialogBinding,
            titleVisibility: .visible
        ) {
            ForEach(camera.availableSaveOptions) { option in
                Button(option.title) {
                    camera.confirmSave(option)
                }
            }
            Button("Don't Save", role: .destructive) {
                camera.discardRecording()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("How much do you want to keep? Cancel keeps a temporary Moment.")
        }
        .sheet(isPresented: $showRoll) {
            CameraRollView(moments: moments)
        }
        .sheet(isPresented: $showMomentRecut) {
            if let moment = moments.latest {
                MomentRecutView(moment: moment)
            }
        }
        .sheet(isPresented: $showFirstRunTip) {
            FirstRunTipView {
                FirstRunTipStore.markShown()
                showFirstRunTip = false
            }
            .presentationDetents([.medium])
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: camera.isRecording) { _, recording in
            orientation.isLocked = recording
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                camera.handleExternalInterruption()
            } else if phase == .active {
                camera.resumeCaptureIfNeeded()
                moments.pruneExpiredIfNeeded()
            }
        }
        .onChange(of: focusPoint) { _, point in
            guard point != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                withAnimation(.easeOut(duration: 0.25)) {
                    focusPoint = nil
                }
            }
        }
        .onChange(of: camera.zoomFactor) { _, _ in
            showZoomBadge = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if camera.zoomFactor <= 1.05 {
                    showZoomBadge = false
                }
            }
        }
    }

    // MARK: - Bindings

    private var saveDialogBinding: Binding<Bool> {
        Binding(
            get: { camera.isChoosingSave },
            set: { presented in
                if !presented, camera.isChoosingSave {
                    camera.keepRecordingAsMoment()
                }
            }
        )
    }

    // MARK: - Chrome

    private var isLandscapeChrome: Bool {
        ControlOrientation.isLandscapeChrome(orientation.deviceOrientation)
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            if !isLandscapeChrome {
                qualityBadge
            }
            Spacer()
            if moments.latest != nil {
                momentButton
            }
            if !isLandscapeChrome {
                muteButton
                torchButton
            }
        }
    }

    /// Landscape: HD → mic → flash along the visual top, left to right.
    /// Laid out as a VStack on the visual-top edge (not a rotated HStack).
    private var landscapeTopChrome: some View {
        let stack = VStack(spacing: 10) {
            if orientation.deviceOrientation == .landscapeRight {
                // Visual left is portrait-bottom, so HD sits at the bottom of the stack.
                torchButton.rotationEffect(orientation.angle)
                muteButton.rotationEffect(orientation.angle)
                qualityBadge.rotationEffect(orientation.angle)
            } else {
                // landscapeLeft: visual left is portrait-top.
                qualityBadge.rotationEffect(orientation.angle)
                muteButton.rotationEffect(orientation.angle)
                torchButton.rotationEffect(orientation.angle)
            }
        }
        .fixedSize()

        return stack
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: ControlOrientation.topLeadingAlignment(
                    for: orientation.deviceOrientation
                )
            )
            .padding(
                ControlOrientation.topLeadingPadding(
                    for: orientation.deviceOrientation
                )
            )
    }

    private var qualityBadge: some View {
        HStack(spacing: 0) {
            Button {
                camera.toggleResolution()
            } label: {
                Text(camera.resolution.label)
                    .frame(minWidth: 28)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }

            Text("·")
                .foregroundStyle(.white.opacity(0.55))

            Button {
                camera.cycleFrameRate()
            } label: {
                Text(camera.frameRate.label)
                    .frame(minWidth: 28)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .background(.black.opacity(0.45), in: Capsule())
        .disabled(!camera.canChangeQuality)
        .opacity(camera.canChangeQuality ? 1 : 0.45)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(camera.resolution.label) \(camera.frameRate.label) frames per second"
        )
    }

    private var recordingTimer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Text(formatDuration(camera.bufferedSeconds))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(.black.opacity(0.45), in: Capsule())
        .accessibilityLabel("Recording \(formatDuration(camera.bufferedSeconds))")
    }

    private var zoomBadge: some View {
        Text(String(format: "%.1f×", camera.zoomFactor))
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.45), in: Capsule())
            .accessibilityLabel("Zoom \(String(format: "%.1f", camera.zoomFactor)) times")
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatRemaining(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        if m > 0 {
            return "\(m)m"
        }
        return "\(total)s"
    }

    // MARK: - Controls

    private var momentButton: some View {
        Button {
            showMomentRecut = true
        } label: {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let remaining: TimeInterval = {
                    guard let latest = moments.latest else { return 0 }
                    return moments.remainingSeconds(for: latest, now: context.date)
                }()
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(formatRemaining(remaining))
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(.black.opacity(0.45), in: Capsule())
            }
            .rotationEffect(orientation.angle)
        }
        .accessibilityLabel("Last moment, time remaining")
    }

    private var torchButton: some View {
        Button {
            camera.toggleTorch()
        } label: {
            Image(systemName: camera.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(camera.isTorchOn ? .yellow : .white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.45), in: Circle())
        }
        .disabled(!camera.canToggleTorch)
        .opacity(camera.canToggleTorch ? 1 : 0.35)
        .accessibilityLabel(camera.isTorchOn ? "Torch on" : "Torch off")
    }

    private var muteButton: some View {
        Button {
            camera.toggleMicMute()
        } label: {
            Image(systemName: camera.isMicMuted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(camera.isMicMuted ? .red.opacity(0.9) : .white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.45), in: Circle())
        }
        .disabled(camera.permissionDenied)
        .accessibilityLabel(camera.isMicMuted ? "Microphone muted" : "Microphone on")
    }

    private var controls: some View {
        ZStack {
            if camera.isRecording {
                HStack {
                    clipButton
                    Spacer()
                    stillPhotoButton
                }
            } else {
                HStack {
                    cameraRollButton
                    Spacer()
                    flipButton
                }
            }

            shutterButton
        }
        .animation(.easeInOut(duration: 0.2), value: camera.isRecording)
    }

    private var stillPhotoButton: some View {
        Button {
            camera.captureStillPhoto()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 3.5)
                    .frame(width: 64, height: 64)
                Circle()
                    .fill(Color.white)
                    .frame(width: 50, height: 50)
            }
            .rotationEffect(orientation.angle)
        }
        .disabled(!camera.canCapturePhoto)
        .opacity(camera.canCapturePhoto ? 1 : 0.45)
        .accessibilityLabel("Take photo")
    }

    private var clipButton: some View {
        Button {
            camera.saveClipWhileRecording()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "scissors")
                    .font(.system(size: 22, weight: .semibold))
                Text("30s")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(.black.opacity(0.45), in: Circle())
            .rotationEffect(orientation.angle)
        }
        .disabled(!camera.canClip)
        .accessibilityLabel("Save last 30 seconds clip")
    }

    private var cameraRollButton: some View {
        Button {
            showRoll = true
        } label: {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.black.opacity(0.45), in: Circle())
                .rotationEffect(orientation.angle)
        }
        .disabled(camera.permissionDenied || camera.isChoosingSave)
        .accessibilityLabel("Camera Roll")
    }

    private var shutterButton: some View {
        Button {
            camera.toggleShutter()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 76, height: 76)
                if camera.isRecording {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.red)
                        .frame(width: 28, height: 28)
                        .rotationEffect(orientation.angle)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 62, height: 62)
                }
            }
        }
        .disabled(!camera.canToggleShutter)
        .accessibilityLabel(camera.isRecording ? "Stop recording" : "Start recording")
    }

    private var flipButton: some View {
        Button {
            camera.flipCamera()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.black.opacity(0.45), in: Circle())
                .rotationEffect(orientation.angle)
        }
        .disabled(!camera.canFlipCamera)
        .opacity(camera.canFlipCamera ? 1 : 0.35)
        .accessibilityLabel("Flip camera")
    }

    private var permissionOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash")
                .font(.system(size: 36, weight: .regular))
            Text("Camera Access Needed")
                .font(.headline)
            Text("Enable Camera in Settings to use Replay.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Focus reticle

private struct FocusReticle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(Color.yellow, lineWidth: 1.5)
            .frame(width: 72, height: 72)
    }
}

// MARK: - First-run tip

private struct FirstRunTipView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How Replay works")
                .font(.title2.weight(.bold))

            tipRow(
                icon: "record.circle",
                title: "Start when you’re ready",
                detail: "Live preview only until you tap the shutter."
            )
            tipRow(
                icon: "scissors",
                title: "Clip while filming",
                detail: "Save the last 30 seconds to Photos without stopping."
            )
            tipRow(
                icon: "square.and.arrow.down",
                title: "Choose how much to keep",
                detail: "On stop, save 30s, 60s, or the full take to Photos."
            )
            tipRow(
                icon: "clock.arrow.circlepath",
                title: "Moments are temporary",
                detail: "Cancel keeps a short-lived redo copy. Don’t Save deletes the take."
            )

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Text("Got it")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }

    private func tipRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
