//
//  PreviewScreen.swift
//  TwinSnap
//
//  撮影後の全画面プレビュー。戻る / 保存 / 共有 / 再撮影。
//

#if canImport(UIKit)
import SwiftUI
import UIKit

struct PreviewScreen: View {

    let image: UIImage
    let onRetake: () -> Void
    let onSave: () async -> Bool

    @State private var isSaving = false
    @State private var didSave = false

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
            saveButton
            shareButton
            retakeButton
        }
    }

    private var saveButton: some View {
        Button {
            Task {
                isSaving = true
                let success = await onSave()
                isSaving = false
                if success { didSave = true }
            }
        } label: {
            VStack(spacing: 3) {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: didSave ? "checkmark" : "square.and.arrow.down")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }
                Text(didSave ? "保存済み" : "保存")
                    .font(.caption)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: 110)
            .frame(height: 56)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        }
        .disabled(isSaving || didSave)
    }

    private var shareButton: some View {
        ShareLink(item: Image(uiImage: image), preview: SharePreview("TwinSnap", image: Image(uiImage: image))) {
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
    }

    private var retakeButton: some View {
        Button {
            onRetake()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                Text("再撮影")
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
