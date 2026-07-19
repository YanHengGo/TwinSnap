//
//  CameraPreviewView.swift
//  TwinSnap
//
//  PreviewSource に応じて legacy AVCaptureVideoPreviewLayer と新規 MTKView を透過的に切替えるディスパッチャ。
//

#if canImport(UIKit)
import AVFoundation
import MetalKit
import SwiftUI
import UIKit

struct CameraPreviewView: View {

    let source: PreviewSource

    var body: some View {
        switch source {
        case .legacy(let layer):
            LegacyPreviewLayerView(previewLayer: layer)
        case .beauty(let renderer):
            MetalPreviewView(renderer: renderer)
        }
    }
}

// MARK: - Legacy AVCaptureVideoPreviewLayer 経路

private struct LegacyPreviewLayerView: UIViewRepresentable {

    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewContainerView {
        PreviewContainerView(previewLayer: previewLayer)
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.attach(previewLayer: previewLayer)
    }
}

final class PreviewContainerView: UIView {

    private var currentLayer: AVCaptureVideoPreviewLayer?

    init(previewLayer: AVCaptureVideoPreviewLayer) {
        super.init(frame: .zero)
        backgroundColor = .black
        attach(previewLayer: previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        currentLayer?.frame = bounds
    }

    func attach(previewLayer: AVCaptureVideoPreviewLayer) {
        guard currentLayer !== previewLayer else {
            previewLayer.frame = bounds
            return
        }
        // 直前まで自分の子だった場合のみ剥がす（他View に移った場合は触らない）
        if let current = currentLayer, current.superlayer === layer {
            current.removeFromSuperlayer()
        }
        // 新しいレイヤーが他View にまだ属していれば安全に外してから貼り直す
        previewLayer.removeFromSuperlayer()
        previewLayer.frame = bounds
        layer.addSublayer(previewLayer)
        currentLayer = previewLayer
    }
}

// MARK: - MTKView 経路（Beauty session）

private struct MetalPreviewView: UIViewRepresentable {

    let renderer: MetalPreviewRenderer

    func makeUIView(context: Context) -> MTKView {
        renderer.mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}

#endif
