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
        guard let (backFormat, frontFormat) = Self.selectBestFormatPair(back: back, front: front) else {
            throw DualCameraSessionError.noCompatibleFormat
        }

        guard let backRenderer = MetalPreviewRenderer.makeShared(),
              let frontRenderer = MetalPreviewRenderer.makeShared() else {
            throw DualCameraSessionError.cannotAddOutput
        }
        self.backRenderer = backRenderer
        self.frontRenderer = frontRenderer

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        try configureDevice(back, format: backFormat)
        try configureDevice(front, format: frontFormat)

        let backPort = try addInput(for: back, position: .back)
        let frontPort = try addInput(for: front, position: .front)

        try addVideoDataOutput(output: backVideoOutput, port: backPort, queue: backVideoQueue, mirrored: false)
        try addVideoDataOutput(output: frontVideoOutput, port: frontPort, queue: frontVideoQueue, mirrored: true)

        try addPhotoOutputConnection(output: backPhotoOutput, port: backPort, mirrored: false)
        try addPhotoOutputConnection(output: frontPhotoOutput, port: frontPort, mirrored: false)
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

    // MARK: - Private setup

    private func configureDevice(_ device: AVCaptureDevice, format: AVCaptureDevice.Format) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.activeFormat = format
        if device.activeFormat.isVideoHDRSupported {
            device.automaticallyAdjustsVideoHDREnabled = false
            device.isVideoHDREnabled = false
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

    // MARK: - Format selection (DualCameraSession と同じロジック)

    private static func selectBestFormatPair(
        back: AVCaptureDevice,
        front: AVCaptureDevice
    ) -> (back: AVCaptureDevice.Format, front: AVCaptureDevice.Format)? {
        let backCandidates = back.formats.filter { $0.isMultiCamSupported }
        let frontCandidates = front.formats.filter { $0.isMultiCamSupported }
        guard !backCandidates.isEmpty, !frontCandidates.isEmpty else { return nil }

        struct Score {
            let backFormat: AVCaptureDevice.Format
            let frontFormat: AVCaptureDevice.Format
            let pixels: Int
            let fps: Double
        }

        var best: Score?
        for backFmt in backCandidates {
            let backDim = CMVideoFormatDescriptionGetDimensions(backFmt.formatDescription)
            let backPixels = Int(backDim.width) * Int(backDim.height)
            let backFps = backFmt.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0

            for frontFmt in frontCandidates {
                let frontDim = CMVideoFormatDescriptionGetDimensions(frontFmt.formatDescription)
                let frontPixels = Int(frontDim.width) * Int(frontDim.height)
                let frontFps = frontFmt.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0

                let combinedPixels = min(backPixels, frontPixels)
                let combinedFps = min(backFps, frontFps)

                if let current = best {
                    if combinedPixels > current.pixels
                        || (combinedPixels == current.pixels && combinedFps > current.fps) {
                        best = Score(backFormat: backFmt, frontFormat: frontFmt,
                                     pixels: combinedPixels, fps: combinedFps)
                    }
                } else {
                    best = Score(backFormat: backFmt, frontFormat: frontFmt,
                                 pixels: combinedPixels, fps: combinedFps)
                }
            }
        }
        return best.map { ($0.backFormat, $0.frontFormat) }
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

        if output === backVideoOutput {
            backRenderer?.present(ciImage)
        } else if output === frontVideoOutput {
            frontRenderer?.present(ciImage)
        }
    }
}

#endif
