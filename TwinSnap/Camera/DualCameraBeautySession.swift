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

    private let backPhotoOutput = AVCapturePhotoOutput()
    private let frontPhotoOutput = AVCapturePhotoOutput()
    private let backVideoOutput = AVCaptureVideoDataOutput()
    private let frontVideoOutput = AVCaptureVideoDataOutput()

    private let sessionQueue = DispatchQueue(label: "jp.yanheng.TwinSnap.beauty.session")
    private let backVideoQueue = DispatchQueue(label: "jp.yanheng.TwinSnap.beauty.back.video")
    private let frontVideoQueue = DispatchQueue(label: "jp.yanheng.TwinSnap.beauty.front.video")

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
    private var rankedFormatPairs: [MultiCamFormatSelector.FormatPair] = []

    /// hardwareCost しきい値。これを上回ると降格を試行。
    private let hardwareCostThreshold: Float = 0.95

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

        try initialConfigure(back: back, front: front, formatPair: bestPair)

        // 初期構成後に hardwareCost をチェック。超過なら降格ラダーで再試行。
        try negotiateCostLimit(back: back, front: front)
    }

    private func initialConfigure(
        back: AVCaptureDevice,
        front: AVCaptureDevice,
        formatPair: MultiCamFormatSelector.FormatPair
    ) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        try configureDevice(back, format: formatPair.back)
        try configureDevice(front, format: formatPair.front)

        let backPort = try addInput(for: back, position: .back)
        let frontPort = try addInput(for: front, position: .front)

        try addVideoDataOutput(output: backVideoOutput, port: backPort, queue: backVideoQueue, mirrored: false)
        try addVideoDataOutput(output: frontVideoOutput, port: frontPort, queue: frontVideoQueue, mirrored: true)

        try addPhotoOutputConnection(output: backPhotoOutput, port: backPort, mirrored: false)
        try addPhotoOutputConnection(output: frontPhotoOutput, port: frontPort, mirrored: false)
    }

    /// 4段階の降格ラダー。設計書 Phase B-3 5.3 の pseudo-code に準拠。
    /// (fps, formatIndex) の順で試行し、最初に閾値以下になったら成功。
    private func negotiateCostLimit(back: AVCaptureDevice, front: AVCaptureDevice) throws {
        if session.hardwareCost <= hardwareCostThreshold {
            return
        }

        struct Attempt {
            let fps: Double
            let formatIndex: Int
        }
        let attempts: [Attempt] = [
            Attempt(fps: 24, formatIndex: 0),
            Attempt(fps: 20, formatIndex: 0),
            Attempt(fps: 24, formatIndex: 1),
            Attempt(fps: 20, formatIndex: 2)
        ]

        for attempt in attempts {
            guard attempt.formatIndex < rankedFormatPairs.count else { continue }
            let pair = rankedFormatPairs[attempt.formatIndex]
            try applyDegradedConfiguration(back: back, front: front, pair: pair, fps: attempt.fps)
            if session.hardwareCost <= hardwareCostThreshold {
                return
            }
        }
        throw DualCameraSessionError.hardwareCostExceeded
    }

    private func applyDegradedConfiguration(
        back: AVCaptureDevice,
        front: AVCaptureDevice,
        pair: MultiCamFormatSelector.FormatPair,
        fps: Double
    ) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        try configureDevice(back, format: pair.back, fps: fps)
        try configureDevice(front, format: pair.front, fps: fps)
    }

    func start() {
        sessionQueue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
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

    // MARK: - Private setup

    private func configureDevice(
        _ device: AVCaptureDevice,
        format: AVCaptureDevice.Format,
        fps: Double? = nil
    ) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.activeFormat = format
        if device.activeFormat.isVideoHDRSupported {
            device.automaticallyAdjustsVideoHDREnabled = false
            device.isVideoHDREnabled = false
        }
        if let fps {
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
        }
    }

    private func addInput(for device: AVCaptureDevice, position: AVCaptureDevice.Position) throws -> AVCaptureInput.Port {
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw DualCameraSessionError.cannotAddInput
        }
        session.addInputWithNoConnections(input)
        guard let port = input.ports(
            for: .video,
            sourceDeviceType: .builtInWideAngleCamera,
            sourceDevicePosition: position
        ).first else {
            throw DualCameraSessionError.noPort
        }
        return port
    }

    private func addVideoDataOutput(
        output: AVCaptureVideoDataOutput,
        port: AVCaptureInput.Port,
        queue: DispatchQueue,
        mirrored: Bool
    ) throws {
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        guard session.canAddOutput(output) else {
            throw DualCameraSessionError.cannotAddOutput
        }
        session.addOutputWithNoConnections(output)

        let connection = AVCaptureConnection(inputPorts: [port], output: output)
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if mirrored, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        guard session.canAddConnection(connection) else {
            throw DualCameraSessionError.cannotAddConnection
        }
        session.addConnection(connection)
    }

    private func addPhotoOutputConnection(
        output: AVCapturePhotoOutput,
        port: AVCaptureInput.Port,
        mirrored: Bool
    ) throws {
        guard session.canAddOutput(output) else {
            throw DualCameraSessionError.cannotAddOutput
        }
        session.addOutputWithNoConnections(output)

        let connection = AVCaptureConnection(inputPorts: [port], output: output)
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if mirrored, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        guard session.canAddConnection(connection) else {
            throw DualCameraSessionError.cannotAddConnection
        }
        session.addConnection(connection)
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
