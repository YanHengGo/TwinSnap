//
//  RootView.swift
//  TwinSnap
//
//  起動フローの分岐: 権限リクエスト → 対応端末判定 → 撮影画面 or 非対応ガイド。
//

import SwiftUI

struct RootView: View {
    @State private var viewModel = CameraViewModel()

    var body: some View {
        Group {
            switch viewModel.launchState {
            case .checking:
                LaunchCheckingView()
            case .permissionDenied:
                PermissionDeniedView()
            case .unsupported:
                UnsupportedDeviceView()
            case .ready:
                CameraView(viewModel: viewModel)
            case .failed(let message):
                CameraFailureView(message: message)
            }
        }
        .task {
            await viewModel.bootstrap()
        }
        .preferredColorScheme(.dark)
    }
}

private struct LaunchCheckingView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ProgressView()
                .tint(.white)
        }
    }
}

private struct CameraFailureView: View {
    let message: String
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.orange)
                Text("カメラの初期化に失敗しました")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}

#Preview {
    RootView()
}
