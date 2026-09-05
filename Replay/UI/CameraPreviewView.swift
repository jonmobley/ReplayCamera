//
//  CameraPreviewView.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import SwiftUI
import UIKit

/// Hosts an `AVCaptureVideoPreviewLayer` for live camera preview.
struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer
    var onPinchZoom: ((UIGestureRecognizer.State, CGFloat) -> Void)?
    var onTapFocus: ((CGPoint) -> Void)?

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer = previewLayer
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        uiView.previewLayer = previewLayer
        context.coordinator.onPinchZoom = onPinchZoom
        context.coordinator.onTapFocus = onTapFocus
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = uiView.bounds
        CATransaction.commit()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPinchZoom: onPinchZoom, onTapFocus: onTapFocus)
    }

    final class Coordinator: NSObject {
        var onPinchZoom: ((UIGestureRecognizer.State, CGFloat) -> Void)?
        var onTapFocus: ((CGPoint) -> Void)?

        init(
            onPinchZoom: ((UIGestureRecognizer.State, CGFloat) -> Void)?,
            onTapFocus: ((CGPoint) -> Void)?
        ) {
            self.onPinchZoom = onPinchZoom
            self.onTapFocus = onTapFocus
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            onPinchZoom?(gesture.state, gesture.scale)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended,
                  let view = gesture.view
            else { return }
            onTapFocus?(gesture.location(in: view))
        }
    }
}

/// UIView that keeps the preview layer sized to its bounds.
final class PreviewHostView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }
}
