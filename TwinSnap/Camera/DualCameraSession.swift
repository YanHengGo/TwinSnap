//
//  DualCameraSession.swift
//  TwinSnap
//
//  AVCaptureMultiCamSession のセットアップ・最適フォーマット選択・プレビューレイヤー提供。
//  ステップ2ではプレビューまで。撮影出力はステップ3で追加。
//

import AVFoundation
import Foundation

#if os(iOS)

enum DualCameraSessionError: Error {
    case multiCamNotSupported
    case noBackCamera
    case noFrontCamera
    case noCompatibleFormat
    case cannotAddInput
    case cannotAddConnection
    case noPort
}

final class DualCameraSession {

    let session = AVCaptureMultiCamSession()

    private(set) var backPreviewLayer: AVCaptureVideoPreviewLayer?
    private(set) var frontPreviewLayer: AVCaptureVideoPreviewLayer?

    private let sessionQueue = DispatchQueue(label: "jp.yanheng.TwinSnap.session")

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

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        try configure(device: back, format: backFormat)
        try configure(device: front, format: frontFormat)

        let backLayer = try addInputAndPreview(for: back, position: .back, mirrored: false)
        let frontLayer = try addInputAndPreview(for: front, position: .front, mirrored: true)

        backPreviewLayer = backLayer
        frontPreviewLayer = frontLayer
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

    private func addInputAndPreview(
        for device: AVCaptureDevice,
        position: AVCaptureDevice.Position,
        mirrored: Bool
    ) throws -> AVCaptureVideoPreviewLayer {
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

        let previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.setSessionWithNoConnection(session)
        previewLayer.videoGravity = .resizeAspectFill

        let connection = AVCaptureConnection(inputPort: port, videoPreviewLayer: previewLayer)
        if mirrored, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        guard session.canAddConnection(connection) else {
            throw DualCameraSessionError.cannotAddConnection
        }
        session.addConnection(connection)

        return previewLayer
    }

    /// 前後カメラ双方が MultiCam 対応するフォーマットの中から、
    /// 「解像度最優先 → fps最大」で最良ペアを選ぶ。
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

#endif
