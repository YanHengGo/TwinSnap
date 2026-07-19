//
//  CameraSessionType.swift
//  TwinSnap
//
//  カメラセッションの抽象。legacy (AVCaptureVideoPreviewLayer) と Beauty (MTKView) を透過的に扱う。
//

#if os(iOS)
import AVFoundation

enum PreviewSource {
    case legacy(AVCaptureVideoPreviewLayer)
    case beauty(MetalPreviewRenderer)
}

protocol CameraSessionType: AnyObject {
    var backPreviewSource: PreviewSource? { get }
    var frontPreviewSource: PreviewSource? { get }
    func start()
    func stop()
    func capture(flashMode: AVCaptureDevice.FlashMode) async throws -> DualCapturedPhotos
    /// プレビューへの美顔フィルター強度を反映する。
    /// legacy セッションは no-op（プレビュー美顔は Phase B のみ）。
    func setBeautyLevel(_ level: Double)
}

#endif
