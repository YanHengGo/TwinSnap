//
//  DualCameraSession.swift
//  TwinSnap
//
//  AVCaptureMultiCamSession のセットアップ・最適フォーマット選択・プレビュー/撮影出力。
//

import AVFoundation
import Foundation
import OSLog

#if os(iOS)

enum DualCameraSessionError: Error {
    case multiCamNotSupported
    case noBackCamera
    case noFrontCamera
    case noCompatibleFormat
    case cannotAddInput
    case cannotAddOutput
    case cannotAddConnection
    case noPort
    case captureFailed
    case hardwareCostExceeded
}

struct DualCapturedPhotos {
    let back: Data
    let front: Data
}

final class DualCameraSession: NSObject, CameraSessionType {

    let session = AVCaptureMultiCamSession()

    private(set) var backPreviewLayer: AVCaptureVideoPreviewLayer?
    private(set) var frontPreviewLayer: AVCaptureVideoPreviewLayer?

    var backPreviewSource: PreviewSource? {
        backPreviewLayer.map { .legacy($0) }
    }

    var frontPreviewSource: PreviewSource? {
        frontPreviewLayer.map { .legacy($0) }
    }

    private let backPhotoOutput = AVCapturePhotoOutput()
    private let frontPhotoOutput = AVCapturePhotoOutput()

    /// Phase C-1: 背面カメラ用の動画出力。C-1-2 で録画の start/stop 実装。
    let backMovieFileOutput = AVCaptureMovieFileOutput()
    private var audioDeviceInput: AVCaptureDeviceInput?

    private var backDevice: AVCaptureDevice?
    private let sessionQueue = DispatchQueue(label: "jp.yanheng.TwinSnap.session")

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
        guard let (backFormat, frontFormat) = MultiCamFormatSelector.selectBestFormatPair(back: back, front: front) else {
            throw DualCameraSessionError.noCompatibleFormat
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        try configure(device: back, format: backFormat)
        try configure(device: front, format: frontFormat)

        let backPort = try addInput(for: back, position: .back)
        let frontPort = try addInput(for: front, position: .front)

        backPreviewLayer = try addPreviewConnection(port: backPort, mirrored: false)
        frontPreviewLayer = try addPreviewConnection(port: frontPort, mirrored: true)

        try addPhotoOutputConnection(output: backPhotoOutput, port: backPort, mirrored: false)
        try addPhotoOutputConnection(output: frontPhotoOutput, port: frontPort, mirrored: true)

        // Phase C-1: audio input + MovieFileOutput（背面のみ）を接続。
        // マイク権限拒否時は音声なし動画として続行。
        let audioPort = addAudioInputIfAvailable()
        try addMovieFileOutputConnections(
            output: backMovieFileOutput,
            videoPort: backPort,
            audioPort: audioPort
        )

        backDevice = back
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

    /// legacy 経路はプレビュー美顔なし。撮影後の Phase A で対応するため no-op。
    func setBeautyLevel(_ level: Double) {}

    /// legacy 経路にはプレビュー美顔チェーンが存在しないため no-op。
    func setBeautySuppressed(_ suppressed: Bool) {}

    // MARK: - Video recording (Phase C-1)

    var isRecording: Bool { backMovieFileOutput.isRecording }

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

    /// 前後カメラの写真を同時にキャプチャする。両方揃った時点で返す。
    func capture(flashMode: AVCaptureDevice.FlashMode) async throws -> DualCapturedPhotos {
        async let backData = capturePhoto(from: backPhotoOutput, flashMode: flashMode)
        async let frontData = capturePhoto(from: frontPhotoOutput, flashMode: .off)
        let (back, front) = try await (backData, frontData)
        return DualCapturedPhotos(back: back, front: front)
    }

    // MARK: - Private

    private func configure(device: AVCaptureDevice, format: AVCaptureDevice.Format) throws {
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

    private func addPreviewConnection(port: AVCaptureInput.Port, mirrored: Bool) throws -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer()
        layer.setSessionWithNoConnection(session)
        layer.videoGravity = .resizeAspectFill

        let connection = AVCaptureConnection(inputPort: port, videoPreviewLayer: layer)
        if mirrored, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        guard session.canAddConnection(connection) else {
            throw DualCameraSessionError.cannotAddConnection
        }
        session.addConnection(connection)
        return layer
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
        if mirrored, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            // プレビューはミラーリングするが、保存する写真は反転しない
            connection.isVideoMirrored = false
        }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        guard session.canAddConnection(connection) else {
            throw DualCameraSessionError.cannotAddConnection
        }
        session.addConnection(connection)
    }

    /// マイクを input として session に追加し、audio port を返す。
    /// マイク未接続・権限拒否時は nil を返し、動画は音声なしで録画される。
    private func addAudioInputIfAvailable() -> AVCaptureInput.Port? {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            Logger.session.notice("Microphone permission not granted; skipping audio input")
            return nil
        }
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            Logger.session.notice("Audio device not available; skipping audio input")
            return nil
        }
        do {
            let input = try AVCaptureDeviceInput(device: audioDevice)
            guard session.canAddInput(input) else {
                Logger.session.error("Cannot add audio input to session")
                return nil
            }
            session.addInputWithNoConnections(input)
            audioDeviceInput = input
            return input.ports.first { $0.mediaType == .audio }
        } catch {
            Logger.session.error("Failed to create audio input: \(error.localizedDescription)")
            return nil
        }
    }

    /// MovieFileOutput に video / audio connection を接続する。
    private func addMovieFileOutputConnections(
        output: AVCaptureMovieFileOutput,
        videoPort: AVCaptureInput.Port,
        audioPort: AVCaptureInput.Port?
    ) throws {
        guard session.canAddOutput(output) else {
            throw DualCameraSessionError.cannotAddOutput
        }
        session.addOutputWithNoConnections(output)

        let videoConnection = AVCaptureConnection(inputPorts: [videoPort], output: output)
        if videoConnection.isVideoRotationAngleSupported(90) {
            videoConnection.videoRotationAngle = 90
        }
        guard session.canAddConnection(videoConnection) else {
            throw DualCameraSessionError.cannotAddConnection
        }
        session.addConnection(videoConnection)

        if let audioPort {
            let audioConnection = AVCaptureConnection(inputPorts: [audioPort], output: output)
            guard session.canAddConnection(audioConnection) else {
                throw DualCameraSessionError.cannotAddConnection
            }
            session.addConnection(audioConnection)
        }
    }

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

#endif
