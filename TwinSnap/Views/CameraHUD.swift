//
//  CameraHUD.swift
//  TwinSnap
//
//  撮影画面のHUD: ヘッダー（フラッシュ・レイアウト切替・設定）、
//  フッター（サムネイル・シャッター・カメラ切替）、トースト表示。
//

import SwiftUI

struct CameraHUD: View {

    let viewModel: CameraViewModel

    private let accent = Color(red: 1.0, green: 0.353, blue: 0.235)

    var body: some View {
        ZStack {
            VStack {
                header
                Spacer()
                if viewModel.isBeautyControlPresented {
                    beautySlider
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                footer
            }
            toastOverlay
            recordingIndicatorOverlay
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isBeautyControlPresented)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isRecording)
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

            HStack(spacing: 10) {
                glassButton {
                    viewModel.isBeautyControlPresented.toggle()
                } content: {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(viewModel.beautyLevel > 0.01 ? accent : .white.opacity(0.9))
                }

                glassButton {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.toggleLayout()
                    }
                } content: {
                    Image(systemName: "rectangle.inset.filled")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }

                glassButton {
                    viewModel.isSettingsPresented = true
                } content: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .disabled(viewModel.isRecording)
        .opacity(viewModel.isRecording ? 0.4 : 1.0)
    }

    private var beautySlider: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent)

            Slider(value: Binding(
                get: { viewModel.beautyLevel },
                set: { viewModel.beautyLevel = $0 }
            ), in: 0...1)
                .tint(accent)

            Text("\(Int(viewModel.beautyLevel * 100))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            modeSegment
            HStack {
                thumbnail
                Spacer()
                shutter
                Spacer()
                swapButton
            }
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 32)
    }

    private var modeSegment: some View {
        Picker("", selection: Binding(
            get: { viewModel.captureMode },
            set: { viewModel.setCaptureMode($0) }
        )) {
            Text("写真").tag(CameraViewModel.CaptureMode.photo)
            Text("動画").tag(CameraViewModel.CaptureMode.video)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 180)
        .disabled(viewModel.isRecording)
        .opacity(viewModel.isRecording ? 0.4 : 1.0)
    }

    private var thumbnail: some View {
        Group {
            #if os(iOS)
            if let image = viewModel.latestThumbnail {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.08)
            }
            #else
            Color.white.opacity(0.08)
            #endif
        }
        .frame(width: 50, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .disabled(viewModel.isRecording)
        .opacity(viewModel.isRecording ? 0.4 : 1.0)
    }

    private var shutter: some View {
        Button {
            handleShutterTap()
        } label: {
            ZStack {
                Circle()
                    .stroke(viewModel.captureMode == .video ? Color.red : accent, lineWidth: 4)
                    .frame(width: 78, height: 78)
                shutterInner
            }
        }
        .disabled(viewModel.isCapturing)
    }

    @ViewBuilder
    private var shutterInner: some View {
        switch viewModel.captureMode {
        case .photo:
            Circle()
                .fill(Color.white)
                .frame(width: 64, height: 64)
                .scaleEffect(viewModel.isCapturing ? 0.85 : 1.0)
                .animation(.easeOut(duration: 0.15), value: viewModel.isCapturing)
        case .video:
            if viewModel.isRecording {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red)
                    .frame(width: 32, height: 32)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.isRecording)
            } else {
                Circle()
                    .fill(Color.red)
                    .frame(width: 64, height: 64)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.isRecording)
            }
        }
    }

    private func handleShutterTap() {
        switch viewModel.captureMode {
        case .photo:
            Task { await viewModel.capture() }
        case .video:
            #if os(iOS)
            if viewModel.isRecording {
                viewModel.stopVideoRecording()
            } else {
                viewModel.startVideoRecording()
            }
            #endif
        }
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
        .disabled(viewModel.isRecording)
        .opacity(viewModel.isRecording ? 0.4 : 1.0)
    }

    private var recordingIndicatorOverlay: some View {
        VStack {
            if viewModel.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                    Text(formattedElapsed)
                        .font(.footnote.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                .padding(.top, 60)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Spacer()
        }
    }

    private var formattedElapsed: String {
        let total = viewModel.recordingElapsedSeconds
        return String(format: "%02d:%02d", total / 60, total % 60)
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
