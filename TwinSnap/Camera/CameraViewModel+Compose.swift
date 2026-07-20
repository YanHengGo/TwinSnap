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
    /// Phase C-2-2 で共有 `PIPGeometry` に委譲するよう変更。
    func normalizedPipRect(imageSize: CGSize) -> (center: CGPoint, size: CGSize) {
        currentPIPGeometry().normalizedRect(imageSize: imageSize)
    }

    /// 現在の canvas/offset/base/display を snapshot した `PIPGeometry` を返す。
    /// 動画録画開始時にも渡す用途で共有。
    func currentPIPGeometry() -> PIPGeometry {
        PIPGeometry(
            canvasSize: canvasSize,
            pipBase: pipBase,
            pipDisplaySize: pipDisplaySize,
            pipOffset: pipOffset
        )
    }
}

#endif
