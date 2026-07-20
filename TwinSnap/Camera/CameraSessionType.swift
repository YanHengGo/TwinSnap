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

    // MARK: - Video recording (Phase C-1)

    /// 現在動画を録画中か。
    var isRecording: Bool { get }

    /// 動画録画を開始する。
    /// - Parameters:
    ///   - url: 出力先 URL（呼び出し側で tmp path 等を用意）
    ///   - delegate: 開始・完了通知の delegate。MovieFileOutput は weak 参照するため、呼び出し側で strong 保持すること
    func startRecording(to url: URL, delegate: AVCaptureFileOutputRecordingDelegate)

    /// 動画録画を停止する。完了は `delegate.fileOutput(_:didFinishRecordingTo:...)` で通知される。
    func stopRecording()
}

#endif
