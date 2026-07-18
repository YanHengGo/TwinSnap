//
//  PreviewScreen.swift
//  TwinSnap
//
//  撮影後の全画面プレビュー。戻る / 保存 / 共有 / 再撮影 のHUD付き。
//  保存・共有はステップ5で機能実装、ステップ4ではUIのみ。
//

#if canImport(UIKit)
import SwiftUI
import UIKit

struct PreviewScreen: View {

    let image: UIImage
    let onRetake: () -> Void

    private let accent = Color(red: 1.0, green: 0.353, blue: 0.235)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .ignoresSafeArea()

            hudOverlay
        }
    }

    private var hudOverlay: some View {
        VStack {
            HStack {
                Button {
                    onRetake()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            pillButton(icon: "square.and.arrow.down", label: "保存") {
                // Step 5 で実装
            }
            .disabled(true)
            .opacity(0.6)

            Button {
                // Step 5 で実装
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                    Text("共有")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                .frame(width: 66, height: 66)
                .background(accent, in: Circle())
            }
            .disabled(true)
            .opacity(0.6)

            pillButton(icon: "arrow.counterclockwise", label: "再撮影") {
                onRetake()
            }
        }
    }

    private func pillButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: 110)
            .frame(height: 56)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        }
    }
}

#endif
