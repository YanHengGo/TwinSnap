//
//  PIPGeometry.swift
//  TwinSnap
//
//  プレビュー座標系（points）で置かれた PiP を、実画像内での位置・サイズに変換する共有ロジック。
//  Phase B-2 の CameraViewModel.normalizedPipRect を切り出したもの。
//  Phase C-2-2 で写真と動画の両方から利用する。
//

import CoreGraphics
import Foundation

struct PIPGeometry: Sendable {

    /// プレビューキャンバス（画面上）のサイズ（points）。
    let canvasSize: CGSize
    /// PiP の基準位置（padding.leading, padding.top 相当）。
    let pipBase: CGPoint
    /// PiP の表示サイズ（120x168 等、points）。
    let pipDisplaySize: CGSize
    /// ユーザーがドラッグで加えたオフセット。
    let pipOffset: CGSize

    /// `videoGravity = .resizeAspectFill` で `imageSize` の画像がキャンバスに表示されている前提で、
    /// PiP の中心とサイズを [0, 1] の正規化座標に変換する。
    func normalizedRect(imageSize: CGSize) -> (center: CGPoint, size: CGSize) {
        let canvas = canvasSize == .zero
            ? CGSize(width: pipDisplaySize.width * 3, height: pipDisplaySize.height * 5)
            : canvasSize

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

    /// PiP の矩形を `imageSize` の画像座標（ピクセル）で返す。
    func rect(imageSize: CGSize) -> CGRect {
        let (center, size) = normalizedRect(imageSize: imageSize)
        return CGRect(
            x: (center.x - size.width / 2) * imageSize.width,
            y: (center.y - size.height / 2) * imageSize.height,
            width: size.width * imageSize.width,
            height: size.height * imageSize.height
        )
    }
}
