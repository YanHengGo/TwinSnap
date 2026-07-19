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

    typealias FormatPair = (back: AVCaptureDevice.Format, front: AVCaptureDevice.Format)

    static func selectBestFormatPair(
        back: AVCaptureDevice,
        front: AVCaptureDevice
    ) -> FormatPair? {
        selectRankedFormatPairs(back: back, front: front).first
    }

    /// 「解像度最優先 → fps最大」の順で全ペアをランク付けして返す。
    /// Phase B-3 の hardwareCost 降格ラダーで、best が超過した場合の次候補として利用する。
    static func selectRankedFormatPairs(
        back: AVCaptureDevice,
        front: AVCaptureDevice
    ) -> [FormatPair] {
        let backCandidates = back.formats.filter { $0.isMultiCamSupported }
        let frontCandidates = front.formats.filter { $0.isMultiCamSupported }
        guard !backCandidates.isEmpty, !frontCandidates.isEmpty else { return [] }

        struct RankedPair {
            let backFormat: AVCaptureDevice.Format
            let frontFormat: AVCaptureDevice.Format
            let pixels: Int
            let fps: Double
        }

        var pairs: [RankedPair] = []
        for backFmt in backCandidates {
            let backDim = CMVideoFormatDescriptionGetDimensions(backFmt.formatDescription)
            let backPixels = Int(backDim.width) * Int(backDim.height)
            let backFps = backFmt.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0

            for frontFmt in frontCandidates {
                let frontDim = CMVideoFormatDescriptionGetDimensions(frontFmt.formatDescription)
                let frontPixels = Int(frontDim.width) * Int(frontDim.height)
                let frontFps = frontFmt.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0

                pairs.append(RankedPair(
                    backFormat: backFmt,
                    frontFormat: frontFmt,
                    pixels: min(backPixels, frontPixels),
                    fps: min(backFps, frontFps)
                ))
            }
        }

        // 解像度降順、同解像度なら fps 降順、同スコアは重複除去（先勝ち）
        pairs.sort { lhs, rhs in
            if lhs.pixels != rhs.pixels { return lhs.pixels > rhs.pixels }
            return lhs.fps > rhs.fps
        }

        // 同スコアの重複除去（連続する同じ pixels/fps は1つに）
        var seen = Set<String>()
        var deduped: [FormatPair] = []
        for pair in pairs {
            let key = "\(pair.pixels)-\(pair.fps)"
            if seen.insert(key).inserted {
                deduped.append((pair.backFormat, pair.frontFormat))
            }
        }
        return deduped
    }
}

#endif
