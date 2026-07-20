//
//  VideoAssetWriter.swift
//  TwinSnap
//
//  AVAssetWriter による動画書き込みラッパー。Phase C-2-1 は映像のみ、
//  Phase C-2-2 で PIP 合成対応、C-2-3 で音声対応を追加予定。
//

#if os(iOS)
import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import OSLog

enum VideoAssetWriterError: Error {
    case cannotAddVideoInput
    case failedToStart
    case notWriting
}

final class VideoAssetWriter {

    private let ciContext: CIContext

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    /// 最初のフレームで startSession(atSourceTime:) を呼ぶまでのフラグ。
    private var isSessionStarted = false

    /// 出力先 URL（stop で回収するため保持）。
    private(set) var outputURL: URL?

    init(ciContext: CIContext) {
        self.ciContext = ciContext
    }

    var isWriting: Bool {
        assetWriter?.status == .writing
    }

    /// AVAssetWriter を初期化して書き込み開始状態にする。
    /// 最初の append 呼出しで startSession(atSourceTime:) が実行される。
    func start(url: URL, size: CGSize) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: 12_000_000  // 12 Mbps (1080p 相当の平均)
        ]
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: compression
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )

        guard writer.canAdd(input) else {
            throw VideoAssetWriterError.cannotAddVideoInput
        }
        writer.add(input)

        guard writer.startWriting() else {
            Logger.session.error("AVAssetWriter startWriting failed: \(String(describing: writer.error), privacy: .public)")
            throw VideoAssetWriterError.failedToStart
        }

        self.assetWriter = writer
        self.videoInput = input
        self.pixelBufferAdaptor = adaptor
        self.isSessionStarted = false
        self.outputURL = url
    }

    /// CMSampleBuffer（VideoDataOutput から流れてくる原生バッファ）を書き込む。
    /// Phase C-2-1 は最小構成: pixelBuffer を素通しで append。
    func append(sampleBuffer: CMSampleBuffer) {
        guard let assetWriter, assetWriter.status == .writing,
              let videoInput, videoInput.isReadyForMoreMediaData,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let pixelBufferAdaptor else {
            return
        }

        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if !isSessionStarted {
            assetWriter.startSession(atSourceTime: time)
            isSessionStarted = true
        }

        pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: time)
    }

    /// 書き込み終了。完了まで await。
    func stop() async {
        guard let assetWriter, assetWriter.status == .writing else {
            resetState()
            return
        }
        videoInput?.markAsFinished()
        await assetWriter.finishWriting()
        if assetWriter.status == .failed {
            Logger.session.error("AVAssetWriter finishWriting failed: \(String(describing: assetWriter.error), privacy: .public)")
        }
        resetState()
    }

    private func resetState() {
        assetWriter = nil
        videoInput = nil
        pixelBufferAdaptor = nil
        isSessionStarted = false
        // outputURL は呼び出し側で参照するため保持しておく（次回 start で上書き）
    }
}

#endif
