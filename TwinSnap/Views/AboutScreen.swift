//
//  AboutScreen.swift
//  TwinSnap
//
//  アプリ情報画面（バージョン等）。
//

#if canImport(UIKit)
import SwiftUI

struct AboutScreen: View {

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "TwinSnap"
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(short) (\(build))"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.on.rectangle.fill")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(Color(red: 1.0, green: 0.353, blue: 0.235))
                        Text(appName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Version \(version)")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.top, 40)

                    VStack(spacing: 14) {
                        Text("前面と背面のカメラを同時に撮影する MultiCam アプリです。")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.85))

                        Text("© 2026 TwinSnap")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 32)
                }
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("このアプリについて")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#endif
