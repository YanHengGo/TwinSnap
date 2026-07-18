//
//  CameraView.swift
//  TwinSnap
//
//  MultiCam プレビュー（PiP / Stacked、切替・ドラッグ・入れ替え）＋ シャッター・フラッシュ HUD。
//

import SwiftUI

#if os(iOS)
import AVFoundation
#endif

struct CameraView: View {

    let viewModel: CameraViewModel

    private let pipSize = CGSize(width: 120, height: 168)
    private let accent = Color(red: 1.0, green: 0.353, blue: 0.235)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if os(iOS)
            layoutContent
                .ignoresSafeArea()
            #endif

            hudOverlay
            toastOverlay
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

    private var mainPreviewLayer: AVCaptureVideoPreviewLayer? {
        switch viewModel.mainPosition {
        case .back: return viewModel.dualSession?.backPreviewLayer
        case .front: return viewModel.dualSession?.frontPreviewLayer
        }
    }

    private var subPreviewLayer: AVCaptureVideoPreviewLayer? {
        switch viewModel.mainPosition {
        case .back: return viewModel.dualSession?.frontPreviewLayer
        case .front: return viewModel.dualSession?.backPreviewLayer
        }
    }

    private var pipLayout: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let main = mainPreviewLayer {
                    CameraPreviewView(previewLayer: main)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                if let sub = subPreviewLayer {
                    CameraPreviewView(previewLayer: sub)
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
            if let main = mainPreviewLayer {
                CameraPreviewView(previewLayer: main)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 2)
            if let sub = subPreviewLayer {
                CameraPreviewView(previewLayer: sub)
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
            header
            Spacer()
            footer
        }
    }

    private var header: some View {
        HStack {
            glassButton {
                viewModel.cycleFlash()
            } content: {
                Image(systemName: viewModel.flashMode.sfSymbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(viewModel.flashMode == .off ? .white.opacity(0.85) : accent)
            }

            Spacer()

            glassButton {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    viewModel.toggleLayout()
                }
            } content: {
                Image(systemName: "rectangle.inset.filled")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var footer: some View {
        HStack {
            thumbnail
            Spacer()
            shutter
            Spacer()
            swapButton
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 32)
    }

    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.white.opacity(0.08))
            .frame(width: 50, height: 50)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }

    private var shutter: some View {
        Button {
            Task { await viewModel.capture() }
        } label: {
            ZStack {
                Circle()
                    .stroke(accent, lineWidth: 4)
                    .frame(width: 78, height: 78)
                Circle()
                    .fill(Color.white)
                    .frame(width: 64, height: 64)
                    .scaleEffect(viewModel.isCapturing ? 0.85 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: viewModel.isCapturing)
            }
        }
        .disabled(viewModel.isCapturing)
    }

    private var swapButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                viewModel.swapMainCamera()
            }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 50, height: 50)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        }
    }

    private func glassButton<Content: View>(
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        }
    }

    private var toastOverlay: some View {
        VStack {
            Spacer()
            if let message = viewModel.toastMessage {
                Text(message)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                    .padding(.bottom, 140)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.toastMessage)
    }
}
