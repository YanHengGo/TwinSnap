//
//  CameraViewModel.swift
//  TwinSnap
//
//  カメラ権限・MultiCam対応判定・セッションのライフサイクルを管理する。
//  ステップ1では権限と対応判定のみ実装。セッション本体はステップ2以降で追加。
//

import AVFoundation
import SwiftUI

@Observable
final class CameraViewModel {

    enum LaunchState {
        case checking
        case permissionDenied
        case unsupported
        case ready
    }

    private(set) var launchState: LaunchState = .checking

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
        launchState = .ready
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
