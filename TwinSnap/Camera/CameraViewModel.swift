//
//  CameraViewModel.swift
//  TwinSnap
//
//  カメラ権限・MultiCam対応判定・セッションのライフサイクル・レイアウト状態を管理する。
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

    private(set) var launchState: LaunchState = .checking
    var layout: Layout = .pip
    var pipOffset: CGSize = .zero

    #if os(iOS)
    private(set) var dualSession: DualCameraSession?
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
