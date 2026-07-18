//
//  CameraView.swift
//  TwinSnap
//
//  撮影画面のプレースホルダー。ステップ2以降で MultiCam プレビューを実装する。
//

import SwiftUI

struct CameraView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.white.opacity(0.6))
                Text("撮影画面（ステップ2で実装）")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

#Preview {
    CameraView()
}
