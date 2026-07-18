//
//  CameraView.swift
//  TwinSnap
//
//  MultiCam プレビュー（PiP / Stacked 切替、PiP ドラッグ可）を表示する撮影画面。
//  ステップ2ではプレビュー + レイアウト切替まで。HUD の撮影・共有ボタン等はステップ3以降で追加。
//

import SwiftUI

struct CameraView: View {

    let viewModel: CameraViewModel

    private let pipSize = CGSize(width: 120, height: 168)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if os(iOS)
            layoutContent
                .ignoresSafeArea()
            #endif

            hudOverlay
        }
        .task {
            viewModel.startSession()
        }
        .onDisappear {
            viewModel.stopSession()
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var layoutContent: some View {
        switch viewModel.layout {
        case .pip:
            pipLayout
        case .stacked:
            stackedLayout
        }
    }

    private var pipLayout: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let back = viewModel.dualSession?.backPreviewLayer {
                    CameraPreviewView(previewLayer: back)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                if let front = viewModel.dualSession?.frontPreviewLayer {
                    CameraPreviewView(previewLayer: front)
                        .frame(width: pipSize.width, height: pipSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.5), lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 14, x: 0, y: 12)
                        .padding(.leading, 16)
                        .padding(.top, 100)
                        .offset(viewModel.pipOffset)
                        .gesture(pipDragGesture(in: proxy.size))
                }
            }
        }
    }

    private var stackedLayout: some View {
        VStack(spacing: 0) {
            if let back = viewModel.dualSession?.backPreviewLayer {
                CameraPreviewView(previewLayer: back)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 2)
            if let front = viewModel.dualSession?.frontPreviewLayer {
                CameraPreviewView(previewLayer: front)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func pipDragGesture(in canvas: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let baseX: CGFloat = 16
                let baseY: CGFloat = 100
                let minX = 12 - baseX
                let maxX = canvas.width - pipSize.width - 12 - baseX
                let minY = 60 - baseY
                let maxY = canvas.height - pipSize.height - 60 - baseY
                viewModel.pipOffset = CGSize(
                    width: min(max(value.translation.width, minX), maxX),
                    height: min(max(value.translation.height, minY), maxY)
                )
            }
    }
    #endif

    private var hudOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.toggleLayout()
                    }
                } label: {
                    Image(systemName: "rectangle.inset.filled")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()
        }
    }
}
