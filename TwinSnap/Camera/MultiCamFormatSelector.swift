//
//  MultiCamFormatSelector.swift
//  TwinSnap
//
//  前後カメラ双方が MultiCam 対応するフォーマットの中から、
//  「解像度最優先 → fps最大」で最良ペアを選ぶ。
//

#if os(iOS)
import AVFoundation

enum MultiCamFormatSelector {

    static func selectBestFormatPair(
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
