//
//  CameraViewModel+Compose.swift
//  TwinSnap
//
//  撮影後の合成ロジックと PiP 位置の正規化。CameraViewModel 本体から分離。
//

#if canImport(UIKit)
import CoreGraphics
import UIKit

extension CameraViewModel {

    func compose(photos: DualCapturedPhotos) -> UIImage? {
        guard let rawBack = UIImage(data: photos.back),
              let rawFront = UIImage(data: photos.front) else {
            return nil
        }
        let backImage = BeautyProcessor.apply(to: rawBack, level: beautyLevel)
        let frontImage = BeautyProcessor.apply(to: rawFront, level: beautyLevel)
        let main: UIImage
        let sub: UIImage
        switch mainPosition {
        case .back:
            main = backImage
            sub = frontImage
        case .front:
            main = frontImage
            sub = backImage
        }

        switch layout {
        case .pip:
            let (center, size) = normalizedPipRect(imageSize: main.size)
            return PhotoComposer.composePiP(
                main: main,
                sub: sub,
                pipCenterNormalized: center,
                pipSizeNormalized: size
            )
        case .stacked:
            return PhotoComposer.composeStacked(main: main, sub: sub)
        }
    }

    /// プレビュー座標系（points）で置かれた PiP を、`imageSize` の画像内での正規化 [0,1] 座標に変換する。
    /// `videoGravity = .resizeAspectFill` で画像がキャンバスに表示されている前提で、
    /// aspectFill による中央クロップを逆算する。
    func normalizedPipRect(imageSize: CGSize) -> (center: CGPoint, size: CGSize) {
        let canvas = canvasSize == .zero
            ? CGSize(width: pipDisplaySize.width * 3, height: pipDisplaySize.height * 5)
            : canvasSize

        // aspectFill: 1 preview point = pixelsPerPoint image pixels
        // 画像が両dim >= canvas となる最小スケールで拡大 → 逆比で min を取る
        let pixelsPerPoint = min(
            imageSize.width / canvas.width,
            imageSize.height / canvas.height
        )
        let viewportWidth = canvas.width * pixelsPerPoint
        let viewportHeight = canvas.height * pixelsPerPoint
        let cropOffsetX = (imageSize.width - viewportWidth) / 2
        let cropOffsetY = (imageSize.height - viewportHeight) / 2

        let originX = pipBase.x + pipOffset.width
        let originY = pipBase.y + pipOffset.height
        let centerXPreview = originX + pipDisplaySize.width / 2
        let centerYPreview = originY + pipDisplaySize.height / 2

        let centerXImage = cropOffsetX + centerXPreview * pixelsPerPoint
        let centerYImage = cropOffsetY + centerYPreview * pixelsPerPoint
        let widthImage = pipDisplaySize.width * pixelsPerPoint
        let heightImage = pipDisplaySize.height * pixelsPerPoint

        return (
            CGPoint(x: centerXImage / imageSize.width, y: centerYImage / imageSize.height),
            CGSize(width: widthImage / imageSize.width, height: heightImage / imageSize.height)
        )
    }
}

#endif
