//
//  CameraPreviewView.swift
//  Replay
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import SwiftUI

/// Hosts an `AVCaptureVideoPreviewLayer` for live camera preview.
struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer = previewLayer
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        uiView.previewLayer = previewLayer
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = uiView.bounds
        CATransaction.commit()
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
