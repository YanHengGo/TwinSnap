//
//  PermissionDeniedView.swift
//  TwinSnap
//
//  カメラ権限が拒否されている場合のガイド画面。設定アプリへの導線を提供。
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PermissionDeniedView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Color(red: 1.0, green: 0.353, blue: 0.235))

                Text("カメラへのアクセスが必要です")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("TwinSnapで撮影するには、設定アプリからカメラの利用を許可してください。")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    #if canImport(UIKit)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    #endif
                } label: {
                    Text("設定を開く")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Color(red: 1.0, green: 0.353, blue: 0.235))
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
            .padding(32)
        }
    }
}

#Preview {
    PermissionDeniedView()
}
