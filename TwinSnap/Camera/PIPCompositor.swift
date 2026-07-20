//
//  PIPCompositor.swift
//  TwinSnap
//
//  背面 CIImage と前面 CIImage を PIP レイアウトで合成する。
//  Phase C-2-2 で動画録画パイプ用に導入。写真の PhotoComposer とは別パス（CIImage ネイティブ）。
//

#if canImport(UIKit)
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum PIPCompositor {

    /// 背面（main）の上に前面（sub）を PIP として合成した CIImage を返す。
    /// - Parameters:
    ///   - main: 背景に敷く画像（背面カメラ）
    ///   - sub: PIP として重ねる画像（前面カメラ）
    ///   - pipRect: `main` の座標系での PIP 表示矩形
    static func composePIP(main: CIImage, sub: CIImage, pipRect: CGRect) -> CIImage {
        let cornerRadius = max(pipRect.width * 0.17, 8)
        let borderWidth = max(pipRect.width * 0.012, 2)
        let mainExtent = main.extent

        // sub を pipRect に aspectFill で収める
        let subScaled = aspectFilledCIImage(sub, in: pipRect)

        // 丸角マスクを生成し、sub にアルファマスクとして適用
        let mask = CIFilter.roundedRectangleGenerator()
        mask.extent = pipRect
        mask.radius = Float(cornerRadius)
        mask.color = CIColor.white
        let maskImage = mask.outputImage?.cropped(to: mainExtent) ?? CIImage.empty()

        let subMasked = subScaled.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: mainExtent),
            kCIInputMaskImageKey: maskImage
        ])

        // 白枠（ストローク）を生成
        let borderColor = CIColor(red: 1, green: 1, blue: 1, alpha: 0.55)
        let border = CIFilter.roundedRectangleStrokeGenerator()
        border.extent = pipRect
        border.radius = Float(cornerRadius)
        border.color = borderColor
        border.width = Float(borderWidth)
        let borderImage = border.outputImage?.cropped(to: mainExtent) ?? CIImage.empty()

        // 合成順: main → sub(masked) → border
        let composed = subMasked.composited(over: main)
        return borderImage.composited(over: composed).cropped(to: mainExtent)
    }

    /// `sub` を `rect` に aspectFill でスケール・センタリングした CIImage を返す。
    /// PIP の丸角マスク適用前段階として使う。
    private static func aspectFilledCIImage(_ sub: CIImage, in rect: CGRect) -> CIImage {
        let srcSize = sub.extent.size
        guard srcSize.width > 0, srcSize.height > 0 else { return sub }

        let scale = max(rect.width / srcSize.width, rect.height / srcSize.height)
        let scaledWidth = srcSize.width * scale
        let scaledHeight = srcSize.height * scale

        let scaled = sub.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // scaled の extent 原点は (0,0) 相当。rect にセンタリングするための平行移動
        let offsetX = rect.midX - scaledWidth / 2
        let offsetY = rect.midY - scaledHeight / 2
        return scaled.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
    }
}

#endif
