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
                CameraView()
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

#Preview {
    RootView()
}
