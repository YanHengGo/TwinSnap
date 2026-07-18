//
//  CameraPreviewView.swift
//  TwinSnap
//
//  AVCaptureVideoPreviewLayer を SwiftUI 上に載せる UIViewRepresentable。
//  MultiCam ではプレビューレイヤーをセッション外で生成する必要があるため、
//  外側から生成済みレイヤーを受け取って描画する。
//

#if canImport(UIKit)
import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {

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

#endif
