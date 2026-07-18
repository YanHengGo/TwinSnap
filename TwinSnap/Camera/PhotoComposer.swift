//
//  PhotoComposer.swift
//  TwinSnap
//
//  Core Graphics で PiP / Stacked の合成、EXIF orientation 正規化、3:4 キャンバス生成。
//

#if canImport(UIKit)
import UIKit

enum PhotoComposer {

    /// 合成キャンバスの目標アスペクト比（幅 / 高さ）。3:4 縦長ポートレート。
    static let canvasAspectRatio: CGFloat = 3.0 / 4.0

    /// PiP レイアウトの合成。`pipCenterNormalized` / `pipSizeNormalized` は
    /// 「main画像の全体（ピクセル）」を基準にした [0,1] 正規化座標。
    /// 呼び出し側は preview canvas → main 画像への aspectFill 座標変換済みで渡すこと。
    static func composePiP(
        main: UIImage,
        sub: UIImage,
        pipCenterNormalized: CGPoint,
        pipSizeNormalized: CGSize
    ) -> UIImage {
        let mainNormalized = normalizedImage(main)
        let size = mainNormalized.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            mainNormalized.draw(in: CGRect(origin: .zero, size: size))

            let pipRect = CGRect(
                x: (pipCenterNormalized.x - pipSizeNormalized.width / 2) * size.width,
                y: (pipCenterNormalized.y - pipSizeNormalized.height / 2) * size.height,
                width: pipSizeNormalized.width * size.width,
                height: pipSizeNormalized.height * size.height
            )

            let cornerRadius = pipRect.width * 0.17
            let path = UIBezierPath(roundedRect: pipRect, cornerRadius: cornerRadius)

            ctx.cgContext.saveGState()
            path.addClip()
            let subNormalized = normalizedImage(sub)
            let subRect = aspectFillRect(imageSize: subNormalized.size, in: pipRect)
            subNormalized.draw(in: subRect)
            ctx.cgContext.restoreGState()

            UIColor.white.withAlphaComponent(0.55).setStroke()
            path.lineWidth = max(pipRect.width * 0.012, 2)
            path.stroke()
        }
    }

    static func composeStacked(main: UIImage, sub: UIImage) -> UIImage {
        let mainNormalized = normalizedImage(main)
        let subNormalized = normalizedImage(sub)

        let width = mainNormalized.size.width
        let height = width / canvasAspectRatio
        let size = CGSize(width: width, height: height)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let topRect = CGRect(x: 0, y: 0, width: size.width, height: size.height / 2)
            let bottomRect = CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2)

            drawAspectFill(mainNormalized, in: topRect, context: ctx.cgContext)
            drawAspectFill(subNormalized, in: bottomRect, context: ctx.cgContext)

            UIColor.white.withAlphaComponent(0.08).setFill()
            ctx.fill(CGRect(x: 0, y: size.height / 2 - 1, width: size.width, height: 2))
        }
    }

    // MARK: - Private

    /// UIImage の EXIF orientation を実際のピクセルデータに焼き込む（`.up` に統一）。
    private static func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func aspectFillRect(imageSize: CGSize, in target: CGRect) -> CGRect {
        let scale = max(target.width / imageSize.width, target.height / imageSize.height)
        let scaled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: target.midX - scaled.width / 2,
            y: target.midY - scaled.height / 2,
            width: scaled.width,
            height: scaled.height
        )
    }

    private static func drawAspectFill(_ image: UIImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.clip(to: rect)
        image.draw(in: aspectFillRect(imageSize: image.size, in: rect))
        context.restoreGState()
    }
}

#endif
