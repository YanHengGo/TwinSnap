//
//  BeautyProcessor.swift
//  TwinSnap
//
//  美顔フィルター: Vision で顔を検出し、顔領域には周波数分離ベースの肌なめらか化を、
//  顔が検出できなかった場合は画像全体に軽い Gaussian blur + ColorControls を適用する。
//
//  Phase A: 撮影後の UIImage 向け `apply(to:level:)`
//  Phase B: プレビュー向け `beautifyCIImage(_:level:faceRects:)` + `detectFaces(in:)`
//

#if canImport(UIKit)
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

enum BeautyProcessor {

    // MARK: - UIImage API (Phase A: 撮影後の後処理)

    /// beautyLevel: 0.0（無効） 〜 1.0（最大効果）
    static func apply(to image: UIImage, level: Double) -> UIImage {
        guard level > 0.001, let cgSource = image.cgImage else { return image }

        let ciImage = CIImage(cgImage: cgSource)
        let context = CIContext(options: [.useSoftwareRenderer: false])

        let faceRects = detectFaces(in: ciImage)
        let composed = beautifyCIImage(ciImage, level: level, faceRects: faceRects)

        guard let cgOut = context.createCGImage(composed, from: ciImage.extent) else {
            return image
        }
        return UIImage(cgImage: cgOut, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - CIImage API (Phase B: プレビュー用)

    /// 事前に検出済みの `faceRects` を受け取り、美顔をかけた CIImage を返す。
    /// - `level == 0` の場合は元 CIImage をそのまま返す（GPU 節約）。
    /// - `faceRects` が空の場合は画像全体にフォールバック処理を適用する。
    static func beautifyCIImage(
        _ source: CIImage,
        level: Double,
        faceRects: [CGRect]
    ) -> CIImage {
        guard level > 0.001 else { return source }

        let beautified = beautify(source: source, strength: CGFloat(level))

        if faceRects.isEmpty {
            return beautified
        }
        let mask = faceMask(extent: source.extent, faceRects: faceRects)
        return beautified.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: source,
            kCIInputMaskImageKey: mask
        ])
    }

    /// Vision で顔矩形を検出。CIImage 座標系（原点左下）の CGRect を返す。
    static func detectFaces(in image: CIImage) -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        guard let observations = request.results else { return [] }

        return observations.map { obs in
            // Vision の boundingBox は正規化 [0,1]、原点は左下（CoreImage と同じ）
            let box = obs.boundingBox
            let rect = CGRect(
                x: box.origin.x * image.extent.width,
                y: box.origin.y * image.extent.height,
                width: box.width * image.extent.width,
                height: box.height * image.extent.height
            )
            // 額・アゴ・耳周りも含めるため 20% 拡張
            return rect.insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.2)
        }
    }

    // MARK: - Beautify chain (private)

    /// 周波数分離ベースの美顔:
    /// 1. Gaussian blur で低周波（肌の色調・面）を作る
    /// 2. 低周波を α ブレンドで元画像に重ねる（strength が高いほど blur 寄り）
    /// 3. わずかに明度アップ・彩度ダウンして "美肌トーン" に寄せる
    private static func beautify(source: CIImage, strength: CGFloat) -> CIImage {
        let extent = source.extent

        let blurRadius = 6.0 + Double(strength) * 8.0  // 6〜14
        let lowFreq = source
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
            .cropped(to: extent)

        // alpha=strength*0.65 で低周波を上に重ねる（1.0でも 65% blur、残り 35% は元ディテール）
        let alpha = min(strength * 0.65, 0.65)
        let alphaBlur = lowFreq.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)
        ])
        let mixed = alphaBlur.applyingFilter("CISourceOverCompositing", parameters: [
            kCIInputBackgroundImageKey: source
        ])

        let toned = mixed.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 1.0 - Double(strength) * 0.08,
            kCIInputBrightnessKey: Double(strength) * 0.03,
            kCIInputContrastKey: 1.0
        ])

        return toned.cropped(to: extent)
    }

    // MARK: - Face mask (radial gradient)

    private static func faceMask(extent: CGRect, faceRects: [CGRect]) -> CIImage {
        var mask: CIImage = CIImage(color: .black).cropped(to: extent)

        for rect in faceRects {
            let radius = min(rect.width, rect.height) / 2
            let center = CIVector(x: rect.midX, y: rect.midY)
            let gradient = CIFilter.radialGradient()
            gradient.center = CGPoint(x: center.x, y: center.y)
            gradient.radius0 = Float(radius * 0.65)
            gradient.radius1 = Float(radius)
            gradient.color0 = CIColor.white
            gradient.color1 = CIColor.black

            guard let radial = gradient.outputImage?.cropped(to: extent) else { continue }
            mask = radial.applyingFilter("CIAdditionCompositing", parameters: [
                kCIInputBackgroundImageKey: mask
            ])
        }
        return mask
    }
}

#endif
