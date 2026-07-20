//
//  DualCameraBeautySession+Setup.swift
//  TwinSnap
//
//  DualCameraBeautySession のセッション構成・hardwareCost 降格ラダー・入出力接続ヘルパー。
//  class body 肥大化を避けるため extension として分離。
//

#if os(iOS)
import AVFoundation
import Foundation
import OSLog

extension DualCameraBeautySession {

    // MARK: - Initial configuration

    func initialConfigure(
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

        // Phase C-1: audio input + MovieFileOutput（背面のみ）を接続。
        let audioPort = addAudioInputIfAvailable()
        try addMovieFileOutputConnections(
            output: backMovieFileOutput,
            videoPort: backPort,
            audioPort: audioPort
        )
    }

    // MARK: - Audio / Movie output helpers (Phase C-1)

    /// マイクを input として session に追加し、audio port を返す。
    /// マイク未接続・権限拒否時は nil を返す。動画は音声なしで録画される。
    func addAudioInputIfAvailable() -> AVCaptureInput.Port? {
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
    func addMovieFileOutputConnections(
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

    // MARK: - hardwareCost negotiation

    /// 4段階の降格ラダー。設計書 Phase B-3 5.3 の pseudo-code に準拠。
    /// (fps, formatIndex) の順で試行し、最初に閾値以下になったら成功。
    func negotiateCostLimit(back: AVCaptureDevice, front: AVCaptureDevice) throws {
        let initialCost = session.hardwareCost
        Logger.negotiate.info("Initial hardwareCost: \(initialCost) (threshold: \(self.hardwareCostThreshold))")
        if initialCost <= hardwareCostThreshold {
            Logger.negotiate.info("Initial configuration accepted; no degradation needed")
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

        for (index, attempt) in attempts.enumerated() {
            guard attempt.formatIndex < rankedFormatPairs.count else {
                Logger.negotiate.info("Skipping attempt \(index + 1): formatIndex \(attempt.formatIndex) unavailable")
                continue
            }
            let pair = rankedFormatPairs[attempt.formatIndex]
            try applyDegradedConfiguration(back: back, front: front, pair: pair, fps: attempt.fps)
            let cost = session.hardwareCost
            Logger.negotiate.info("Attempt \(index + 1): fps=\(attempt.fps) formatIndex=\(attempt.formatIndex) → hardwareCost=\(cost)")
            if cost <= hardwareCostThreshold {
                Logger.negotiate.notice("Degradation succeeded at attempt \(index + 1) (fps=\(attempt.fps))")
                return
            }
        }
        Logger.negotiate.error("All degradation attempts exhausted; throwing hardwareCostExceeded")
        throw DualCameraSessionError.hardwareCostExceeded
    }

    func applyDegradedConfiguration(
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

    // MARK: - Device / input / output helpers

    func configureDevice(
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

    func addInput(for device: AVCaptureDevice, position: AVCaptureDevice.Position) throws -> AVCaptureInput.Port {
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

    func addVideoDataOutput(
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

    func addPhotoOutputConnection(
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
}

#endif
