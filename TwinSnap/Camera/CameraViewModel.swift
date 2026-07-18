//
//  CameraViewModel.swift
//  TwinSnap
//
//  カメラ権限・MultiCam対応判定・セッションのライフサイクル・レイアウト状態・撮影状態を管理する。
//

import AVFoundation
import CoreGraphics
import SwiftUI

@Observable
final class CameraViewModel {

    enum LaunchState {
        case checking
        case permissionDenied
        case unsupported
        case ready
        case failed(String)
    }

    enum Layout {
        case pip
        case stacked
    }

    enum MainPosition {
        case back
        case front
    }

    enum FlashMode: CaseIterable {
        case off, on, auto

        var next: FlashMode {
            switch self {
            case .off: return .on
            case .on: return .auto
            case .auto: return .off
            }
        }

        var sfSymbol: String {
            switch self {
            case .off: return "bolt.slash.fill"
            case .on: return "bolt.fill"
            case .auto: return "bolt.badge.a.fill"
            }
        }

        #if os(iOS)
        var avFlashMode: AVCaptureDevice.FlashMode {
            switch self {
            case .off: return .off
            case .on: return .on
            case .auto: return .auto
            }
        }
        #endif
    }

    private(set) var launchState: LaunchState = .checking
    var layout: Layout = .pip
    var mainPosition: MainPosition = .back
    var pipOffset: CGSize = .zero
    var flashMode: FlashMode = .off
    private(set) var isCapturing: Bool = false
    private(set) var toastMessage: String?

    #if os(iOS)
    private(set) var dualSession: DualCameraSession?
    private(set) var lastCapturedPhotos: DualCapturedPhotos?
    #endif

    func bootstrap() async {
        let granted = await requestCameraPermission()
        guard granted else {
            launchState = .permissionDenied
            return
        }
        guard isMultiCamSupported else {
            launchState = .unsupported
            return
        }
        #if os(iOS)
        do {
            let session = DualCameraSession()
            try session.configure()
            dualSession = session
            launchState = .ready
        } catch {
            launchState = .failed(String(describing: error))
        }
        #else
        launchState = .unsupported
        #endif
    }

    func startSession() {
        #if os(iOS)
        dualSession?.start()
        #endif
    }

    func stopSession() {
        #if os(iOS)
        dualSession?.stop()
        #endif
    }

    func toggleLayout() {
        layout = (layout == .pip) ? .stacked : .pip
    }

    func swapMainCamera() {
        mainPosition = (mainPosition == .back) ? .front : .back
    }

    func cycleFlash() {
        flashMode = flashMode.next
    }

    func capture() async {
        #if os(iOS)
        guard let session = dualSession, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        do {
            let photos = try await session.capture(flashMode: flashMode.avFlashMode)
            lastCapturedPhotos = photos
            showToast("撮影しました")
        } catch {
            showToast("撮影に失敗しました")
        }
        #endif
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self else { return }
            if self.toastMessage == message {
                self.toastMessage = nil
            }
        }
    }

    private var isMultiCamSupported: Bool {
        #if os(iOS)
        return AVCaptureMultiCamSession.isMultiCamSupported
        #else
        return false
        #endif
    }

    private func requestCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
