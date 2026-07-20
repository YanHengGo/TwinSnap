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

    /// Phase C-1: 背面カメラ用の動画出力。C-1-2 で録画の start/stop 実装。
    let backMovieFileOutput = AVCaptureMovieFileOutput()
    var audioDeviceInput: AVCaptureDeviceInput?

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

    // MARK: - AVAssetWriter (Phase C-2-1 / C-2-2)

    private var videoAssetWriter: VideoAssetWriter?
    /// 録画開始要求のURL。最初のフレーム到着時に AssetWriter を initialize する。
    private var pendingAssetWriterURL: URL?

    /// PIP 合成用のジオメトリ（PIP compose 経路のみ設定）。nil の場合は背面のみ書き出し。
    private var pipGeometry: PIPGeometry?
    /// 前面カメラの最新フレーム（PIP 合成の sub に使う）。frontVideoQueue で書き、backVideoQueue で読む。
    private var latestFrontCIImage: CIImage?
    private let frontFrameLock = NSLock()

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
        let backSize = "\(backDim.width)x\(backDim.height)"
        let frontSize = "\(frontDim.width)x\(frontDim.height)"
        Logger.session.info(
            "Configuring beauty session: back=\(backSize) front=\(frontSize) rankedPairs=\(ranked.count)"
        )

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

    // MARK: - Video recording (Phase C-1)

    var isRecording: Bool {
        backMovieFileOutput.isRecording || videoAssetWriter?.isWriting == true || pendingAssetWriterURL != nil
    }

    func startRecording(to url: URL, delegate: AVCaptureFileOutputRecordingDelegate) {
        guard !backMovieFileOutput.isRecording else {
            Logger.session.notice("startRecording ignored: already recording")
            return
        }
        Logger.session.info("startRecording to \(url.lastPathComponent, privacy: .public)")
        backMovieFileOutput.startRecording(to: url, recordingDelegate: delegate)
    }

    func stopRecording() {
        guard backMovieFileOutput.isRecording else {
            Logger.session.notice("stopRecording ignored: not recording")
            return
        }
        Logger.session.info("stopRecording")
        backMovieFileOutput.stopRecording()
    }

    // MARK: - AVAssetWriter recording (Phase C-2-1)

    /// AVAssetWriter 経由の録画を開始する。実際の writer 初期化は最初のフレーム到着時。
    /// - Parameter pipGeometry: 指定時は PIP 合成モード（背面 + 前面をリアルタイム合成）。nil なら背面のみ。
    func startAssetWriterRecording(to url: URL, pipGeometry: PIPGeometry? = nil) {
        guard videoAssetWriter == nil, pendingAssetWriterURL == nil else {
            Logger.session.notice("startAssetWriterRecording ignored: already recording")
            return
        }
        Logger.session.info("startAssetWriterRecording pending: \(url.lastPathComponent, privacy: .public) pip=\(pipGeometry != nil)")
        pendingAssetWriterURL = url
        self.pipGeometry = pipGeometry
    }

    /// AVAssetWriter 経由の録画を停止し、完了を await して URL を返す。
    func stopAssetWriterRecording() async -> URL? {
        pendingAssetWriterURL = nil
        pipGeometry = nil
        frontFrameLock.lock()
        latestFrontCIImage = nil
        frontFrameLock.unlock()
        guard let writer = videoAssetWriter else {
            Logger.session.notice("stopAssetWriterRecording: no active writer")
            return nil
        }
        let url = writer.outputURL
        await writer.stop()
        videoAssetWriter = nil
        Logger.session.info("AssetWriter recording finished")
        return url
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
            processBack(sampleBuffer: sampleBuffer, ciImage: ciImage, level: level)
        } else if output === frontVideoOutput {
            processFront(ciImage: ciImage, level: level)
        }
    }

    /// backVideoQueue（シリアル）でのみ呼ばれるため排他不要。
    private func processBack(sampleBuffer: CMSampleBuffer, ciImage: CIImage, level: Double) {
        backFrameCounter &+= 1
        if backFrameCounter % faceDetectionInterval == 0 {
            lastBackFaces = BeautyProcessor.detectFaces(in: ciImage)
        }
        let output = level < 0.001
            ? ciImage
            : BeautyProcessor.beautifyCIImage(ciImage, level: level, faceRects: lastBackFaces)
        backRenderer?.present(output)

        // Phase C-2: AssetWriter 録画中ならフレームを書き込む
        appendToAssetWriterIfNeeded(sampleBuffer: sampleBuffer, backCIImage: ciImage)
    }

    /// AssetWriter が pending or writing の場合、フレームを書き込む。
    /// 最初のフレームで writer を初期化する（実サイズ判明のため）。
    /// pipGeometry があれば背面 + 前面を PIP 合成、なければ背面のみ素通し。
    private func appendToAssetWriterIfNeeded(sampleBuffer: CMSampleBuffer, backCIImage: CIImage) {
        if let pendingURL = pendingAssetWriterURL, videoAssetWriter == nil {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                  let ciContext = MetalPreviewRenderer.sharedCIContext else {
                Logger.session.error("AssetWriter start aborted: no CIContext or pixelBuffer")
                pendingAssetWriterURL = nil
                return
            }
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let size = CGSize(width: width, height: height)
            let writer = VideoAssetWriter(ciContext: ciContext)
            do {
                try writer.start(url: pendingURL, size: size)
                videoAssetWriter = writer
                pendingAssetWriterURL = nil
                Logger.session.info("AssetWriter started (\(width)x\(height))")
            } catch {
                Logger.session.error("AssetWriter start failed: \(error.localizedDescription, privacy: .public)")
                pendingAssetWriterURL = nil
                return
            }
        }

        guard let writer = videoAssetWriter else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // PIP 合成モード: 前面フレームが揃っていれば合成、それ以外は背面素通し
        if let geometry = pipGeometry {
            frontFrameLock.lock()
            let front = latestFrontCIImage
            frontFrameLock.unlock()
            if let front {
                let pipRect = geometry.rect(imageSize: backCIImage.extent.size)
                let composed = PIPCompositor.composePIP(main: backCIImage, sub: front, pipRect: pipRect)
                writer.append(ciImage: composed, at: time)
            } else {
                writer.append(sampleBuffer: sampleBuffer)
            }
        } else {
            // 背面のみ（C-2-1 モード）
            writer.append(sampleBuffer: sampleBuffer)
        }
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

        // Phase C-2-2: PIP 合成用に最新の前面フレームを保持（合成前の原生 CIImage）
        if pipGeometry != nil {
            frontFrameLock.lock()
            latestFrontCIImage = ciImage
            frontFrameLock.unlock()
        }
    }
}

#endif
