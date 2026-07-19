//
//  DualCameraBeautySession.swift
//  TwinSnap
//
//  AVCaptureVideoDataOutput + MTKView によるプレビューパイプ。
//  Phase B-1 では美顔チェーンを呼ばずに素通し（映像パススルー）。
//  写真キャプチャは AVCapturePhotoOutput + Phase A の後処理を継続利用する。
//

#if os(iOS)
import AVFoundation
import CoreImage
import Foundation
import OSLog

final class DualCameraBeautySession: NSObject, CameraSessionType {

    let session = AVCaptureMultiCamSession()

    private(set) var backRenderer: MetalPreviewRenderer?
    private(set) var frontRenderer: MetalPreviewRenderer?

    var backPreviewSource: PreviewSource? {
        backRenderer.map { .beauty($0) }
    }

    var frontPreviewSource: PreviewSource? {
        frontRenderer.map { .beauty($0) }
    }

    let backPhotoOutput = AVCapturePhotoOutput()
    let frontPhotoOutput = AVCapturePhotoOutput()
    let backVideoOutput = AVCaptureVideoDataOutput()
    let frontVideoOutput = AVCaptureVideoDataOutput()

    private let sessionQueue = DispatchQueue(label: "jp.yanheng.TwinSnap.beauty.session")
    let backVideoQueue = DispatchQueue(label: "jp.yanheng.TwinSnap.beauty.back.video")
    let frontVideoQueue = DispatchQueue(label: "jp.yanheng.TwinSnap.beauty.front.video")

    private var captureDelegates: [Int64: PhotoCaptureDelegate] = [:]
    private let delegateLock = NSLock()

    // MARK: - Beauty state

    /// 顔検出頻度（フレーム）。5フレームに1回 = 30fps時に6fps相当。
    private let faceDetectionInterval = 5

    private var beautyLevel: Double = 0
    private let beautyLevelLock = NSLock()

    private var isBeautySuppressed: Bool = false
    private let suppressionLock = NSLock()

    private var backFrameCounter: Int = 0
    private var frontFrameCounter: Int = 0
    private var lastBackFaces: [CGRect] = []
    private var lastFrontFaces: [CGRect] = []

    // MARK: - Devices (for negotiate)

    private var backDevice: AVCaptureDevice?
    private var frontDevice: AVCaptureDevice?
    var rankedFormatPairs: [MultiCamFormatSelector.FormatPair] = []

    /// hardwareCost しきい値。これを上回ると降格を試行。
    let hardwareCostThreshold: Float = 0.95

    func configure() throws {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            throw DualCameraSessionError.multiCamNotSupported
        }
        guard let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw DualCameraSessionError.noBackCamera
        }
        guard let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw DualCameraSessionError.noFrontCamera
        }

        let ranked = MultiCamFormatSelector.selectRankedFormatPairs(back: back, front: front)
        guard let bestPair = ranked.first else {
            throw DualCameraSessionError.noCompatibleFormat
        }

        guard let backRenderer = MetalPreviewRenderer.makeShared(),
              let frontRenderer = MetalPreviewRenderer.makeShared() else {
            throw DualCameraSessionError.cannotAddOutput
        }
        self.backRenderer = backRenderer
        self.frontRenderer = frontRenderer
        self.backDevice = back
        self.frontDevice = front
        self.rankedFormatPairs = ranked

        let backDim = CMVideoFormatDescriptionGetDimensions(bestPair.back.formatDescription)
        let frontDim = CMVideoFormatDescriptionGetDimensions(bestPair.front.formatDescription)
        Logger.session.info("Configuring beauty session: back=\(backDim.width)x\(backDim.height) front=\(frontDim.width)x\(frontDim.height) rankedPairs=\(ranked.count)")

        try initialConfigure(back: back, front: front, formatPair: bestPair)

        // 初期構成後に hardwareCost をチェック。超過なら降格ラダーで再試行。
        try negotiateCostLimit(back: back, front: front)
        Logger.session.info("Beauty session configured; final hardwareCost=\(self.session.hardwareCost)")
    }

    func start() {
        sessionQueue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
            Logger.session.info("DualCameraBeautySession started")
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
            Logger.session.info("DualCameraBeautySession stopped")
        }
    }

    func capture(flashMode: AVCaptureDevice.FlashMode) async throws -> DualCapturedPhotos {
        async let backData = capturePhoto(from: backPhotoOutput, flashMode: flashMode)
        async let frontData = capturePhoto(from: frontPhotoOutput, flashMode: .off)
        let (back, front) = try await (backData, frontData)
        return DualCapturedPhotos(back: back, front: front)
    }

    func setBeautyLevel(_ level: Double) {
        beautyLevelLock.lock()
        beautyLevel = level
        beautyLevelLock.unlock()
    }

    func setBeautySuppressed(_ suppressed: Bool) {
        suppressionLock.lock()
        isBeautySuppressed = suppressed
        suppressionLock.unlock()
        Logger.beauty.notice("Beauty chain suppression=\(suppressed)")
    }

    private func currentBeautyLevel() -> Double {
        beautyLevelLock.lock()
        let level = beautyLevel
        beautyLevelLock.unlock()
        return level
    }

    private func currentSuppressed() -> Bool {
        suppressionLock.lock()
        let suppressed = isBeautySuppressed
        suppressionLock.unlock()
        return suppressed
    }

    // MARK: - Photo capture (共有ロジック)

    private func capturePhoto(
        from output: AVCapturePhotoOutput,
        flashMode: AVCaptureDevice.FlashMode
    ) async throws -> Data {
        let settings = AVCapturePhotoSettings()
        if output.supportedFlashModes.contains(flashMode) {
            settings.flashMode = flashMode
        }

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoCaptureDelegate(uniqueID: settings.uniqueID) { [weak self] uid, result in
                self?.removeDelegate(uniqueID: uid)
                continuation.resume(with: result)
            }
            addDelegate(delegate, for: settings.uniqueID)
            output.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func addDelegate(_ delegate: PhotoCaptureDelegate, for uniqueID: Int64) {
        delegateLock.lock()
        captureDelegates[uniqueID] = delegate
        delegateLock.unlock()
    }

    private func removeDelegate(uniqueID: Int64) {
        delegateLock.lock()
        captureDelegates.removeValue(forKey: uniqueID)
        delegateLock.unlock()
    }
}

extension DualCameraBeautySession: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        // 熱シャットダウン保護等で suppressed の場合は美顔チェーンを完全にスキップする
        let level = currentSuppressed() ? 0 : currentBeautyLevel()

        if output === backVideoOutput {
            processBack(ciImage: ciImage, level: level)
        } else if output === frontVideoOutput {
            processFront(ciImage: ciImage, level: level)
        }
    }

    /// backVideoQueue（シリアル）でのみ呼ばれるため排他不要。
    private func processBack(ciImage: CIImage, level: Double) {
        backFrameCounter &+= 1
        if backFrameCounter % faceDetectionInterval == 0 {
            lastBackFaces = BeautyProcessor.detectFaces(in: ciImage)
        }
        let output = level < 0.001
            ? ciImage
            : BeautyProcessor.beautifyCIImage(ciImage, level: level, faceRects: lastBackFaces)
        backRenderer?.present(output)
    }

    /// frontVideoQueue（シリアル）でのみ呼ばれるため排他不要。
    private func processFront(ciImage: CIImage, level: Double) {
        frontFrameCounter &+= 1
        if frontFrameCounter % faceDetectionInterval == 0 {
            lastFrontFaces = BeautyProcessor.detectFaces(in: ciImage)
        }
        let output = level < 0.001
            ? ciImage
            : BeautyProcessor.beautifyCIImage(ciImage, level: level, faceRects: lastFrontFaces)
        frontRenderer?.present(output)
    }
}

#endif
