//
//  CameraScreen.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import SwiftUI

/// Full-bleed camera: preview, roll, start/stop shutter, flip, moment.
struct CameraScreen: View {
    @StateObject private var camera = CaptureSessionController()
    @StateObject private var orientation = DeviceOrientationObserver()
    @ObservedObject private var moments = MomentStore.shared

    @State private var showRoll = false
    @State private var showMomentRecut = false

    var body: some View {
        ZStack {
            CameraPreviewView(previewLayer: camera.previewLayer)
                .ignoresSafeArea()

            if camera.permissionDenied {
                permissionOverlay
            }

            VStack {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Spacer()

                if let message = camera.statusMessage {
                    Text(message)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 16)
                        .rotationEffect(orientation.angle)
                        .transition(.opacity)
                }

                controls
                    .padding(.horizontal, 28)
                    .padding(.bottom, 40)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: camera.statusMessage)
        .animation(.easeInOut(duration: 0.2), value: camera.isRecording)
        .animation(.easeInOut(duration: 0.2), value: moments.latest?.id)
        .animation(.easeInOut(duration: 0.2), value: orientation.angle)
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
            Button("Cancel", role: .cancel) {
                camera.discardRecording()
            }
        } message: {
            Text("How much do you want to keep?")
        }
        .sheet(isPresented: $showRoll) {
            CameraRollView(moments: moments)
        }
        .sheet(isPresented: $showMomentRecut) {
            if let moment = moments.latest {
                MomentRecutView(moment: moment)
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    // MARK: - Bindings

    private var saveDialogBinding: Binding<Bool> {
        Binding(
            get: { camera.isChoosingSave },
            set: { presented in
                if !presented, camera.isChoosingSave {
                    camera.discardRecording()
                }
            }
        )
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            HStack {
                if moments.latest != nil {
                    momentButton
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }

            if camera.isRecording {
                recordingTimer
                    .rotationEffect(orientation.angle)
            }
        }
        .frame(height: 40)
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

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Controls

    private var momentButton: some View {
        Button {
            showMomentRecut = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                Text("Moment")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(.black.opacity(0.45), in: Capsule())
            .rotationEffect(orientation.angle)
        }
        .accessibilityLabel("Last moment")
    }

    private var controls: some View {
        HStack {
            if camera.isRecording {
                clipButton
            } else {
                cameraRollButton
            }
            Spacer()
            shutterButton
            Spacer()
            flipButton
        }
    }

    private var clipButton: some View {
        Button {
            camera.saveClipWhileRecording()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "scissors")
                    .font(.system(size: 18, weight: .semibold))
                Text("30s")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
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
        .disabled(camera.permissionDenied || camera.isChoosingSave)
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
