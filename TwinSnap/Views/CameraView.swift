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

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                #if os(iOS)
                layoutContent
                    .ignoresSafeArea()
                #endif

                CameraHUD(viewModel: viewModel)
            }
            .onAppear { viewModel.canvasSize = proxy.size }
            .onChange(of: proxy.size) { _, newValue in
                viewModel.canvasSize = newValue
            }
        }
        .task {
            viewModel.startSession()
        }
        .onDisappear {
            viewModel.stopSession()
        }
        #if os(iOS)
        .fullScreenCover(isPresented: Binding(
            get: { viewModel.isPreviewPresented },
            set: { viewModel.isPreviewPresented = $0 }
        )) {
            if let image = viewModel.composedImage {
                PreviewScreen(
                    image: image,
                    onRetake: { viewModel.dismissPreviewForRetake() },
                    onSave: { await viewModel.saveToLibrary() }
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.isSettingsPresented },
            set: { viewModel.isSettingsPresented = $0 }
        )) {
            SettingsScreen(settings: viewModel.settings) {
                viewModel.isSettingsPresented = false
            }
        }
        #endif
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

    private var mainPreviewSource: PreviewSource? {
        switch viewModel.mainPosition {
        case .back: return viewModel.session?.backPreviewSource
        case .front: return viewModel.session?.frontPreviewSource
        }
    }

    private var subPreviewSource: PreviewSource? {
        switch viewModel.mainPosition {
        case .back: return viewModel.session?.frontPreviewSource
        case .front: return viewModel.session?.backPreviewSource
        }
    }

    private var pipLayout: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let main = mainPreviewSource {
                    CameraPreviewView(source: main)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                if let sub = subPreviewSource {
                    CameraPreviewView(source: sub)
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
            if let main = mainPreviewSource {
                CameraPreviewView(source: main)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 2)
            if let sub = subPreviewSource {
                CameraPreviewView(source: sub)
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
}
