//
//  CameraScreen.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import SwiftUI

/// Full-bleed camera UI: live preview, buffer status, Save, and flip.
struct CameraScreen: View {
    @StateObject private var camera = CaptureSessionController()

    var body: some View {
        ZStack {
            CameraPreviewView(previewLayer: camera.previewLayer)
                .ignoresSafeArea()

            if camera.permissionDenied {
                permissionOverlay
            }

            VStack(spacing: 12) {
                BufferStatusView(
                    bufferedSeconds: camera.bufferedSeconds,
                    targetSeconds: camera.bufferTarget
                )
                .padding(.top, 20)

                BufferLengthPicker(
                    selection: bufferLengthBinding,
                    isDisabled: camera.isSaving || camera.permissionDenied
                )

                Spacer()

                if let message = camera.statusMessage {
                    Text(message)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }

                controls
                    .padding(.bottom, 36)
            }
            .padding(.horizontal, 24)
        }
        .animation(.easeInOut(duration: 0.2), value: camera.statusMessage)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    // MARK: - Bindings

    private var bufferLengthBinding: Binding<BufferLength> {
        Binding(
            get: { camera.bufferLength },
            set: { camera.setBufferLength($0) }
        )
    }

    // MARK: - Controls

    private var controls: some View {
        HStack {
            Color.clear.frame(width: 52, height: 52)

            Spacer()

            Button {
                camera.saveReplay()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .frame(width: 78, height: 78)
                    Circle()
                        .fill(camera.canSave ? Color.accentColor : Color.white.opacity(0.35))
                        .frame(width: 64, height: 64)
                    if camera.isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Save")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(!camera.canSave)
            .accessibilityLabel(
                "Save last \(camera.bufferLength.rawValue) seconds"
            )

            Spacer()

            Button {
                camera.flipCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .disabled(camera.isSaving || camera.permissionDenied)
            .accessibilityLabel("Flip camera")
        }
    }

    private var permissionOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 40))
            Text("Camera access needed")
                .font(.headline)
            Text("Enable Camera in Settings to use Replay.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.85))
    }
}
