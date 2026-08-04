//
//  CameraScreen.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import SwiftUI

/// Full-bleed camera: preview, roll, Save, flip, moment re-cut, settings.
struct CameraScreen: View {
    @StateObject private var camera = CaptureSessionController()
    @ObservedObject private var moments = MomentStore.shared

    @State private var showSettings = false
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
                HStack {
                    if moments.latest != nil {
                        momentButton
                    }
                    Spacer()
                    settingsButton
                }
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
                        .transition(.opacity)
                }

                controls
                    .padding(.horizontal, 28)
                    .padding(.bottom, 40)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: camera.statusMessage)
        .animation(.easeInOut(duration: 0.2), value: moments.latest?.id)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDetents([.medium])
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

    // MARK: - Controls

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.45), in: Circle())
        }
        .accessibilityLabel("Settings")
    }

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
        }
        .accessibilityLabel("Last moment")
    }

    private var controls: some View {
        HStack {
            cameraRollButton
            Spacer()
            saveButton
            Spacer()
            flipButton
        }
    }

    private var cameraRollButton: some View {
        Button {
            showRoll = true
        } label: {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    .black.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .disabled(camera.permissionDenied)
        .accessibilityLabel("Camera Roll")
    }

    private var saveButton: some View {
        Button {
            camera.saveReplay()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(camera.canSave ? Color.white : Color.white.opacity(0.35))
                    .frame(width: 62, height: 62)
            }
        }
        .disabled(!camera.canSave)
        .accessibilityLabel("Save replay")
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
        }
        .disabled(camera.permissionDenied)
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
