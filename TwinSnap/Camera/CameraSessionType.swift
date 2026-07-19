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

    /// 熱シャットダウン保護などで美顔チェーンを一時停止させる。
    /// `true` の場合、beautyLevel の値に関わらずプレビューは素通し。
    /// legacy セッションは no-op。
    func setBeautySuppressed(_ suppressed: Bool)
}

#endif
