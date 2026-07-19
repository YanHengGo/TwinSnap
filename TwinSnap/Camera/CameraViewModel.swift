//
//  CameraViewModel.swift
//  TwinSnap
//
//  カメラ権限・MultiCam対応判定・セッションのライフサイクル・レイアウト状態・撮影/プレビュー状態を管理する。
//

import AVFoundation
import CoreGraphics
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@Observable
final class CameraViewModel {

    private(set) var launchState: LaunchState = .checking
    var layout: Layout = .pip
    var mainPosition: MainPosition = .back
    var pipOffset: CGSize = .zero
    var flashMode: FlashMode = .off
    var canvasSize: CGSize = .zero
    var beautyLevel: Double = 0 {
        didSet {
            #if os(iOS)
            session?.setBeautyLevel(beautyLevel)
            #endif
        }
    }
    var isBeautyControlPresented: Bool = false
    private(set) var isCapturing: Bool = false
    private(set) var toastMessage: String?
    var isSettingsPresented: Bool = false

    #if os(iOS)
    private(set) var session: (any CameraSessionType)?
    private(set) var composedImage: UIImage?
    private(set) var lastCapturedPhotos: DualCapturedPhotos?
    private(set) var latestThumbnail: UIImage?
    var isPreviewPresented: Bool = false
    #endif

    let settings: AppSettings

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    // PiP レイアウトの基準座標（CameraView と揃える）
    let pipBase = CGPoint(x: 16, y: 100)
    let pipDisplaySize = CGSize(width: 120, height: 168)

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
            let newSession: any CameraSessionType
            if settings.wysiwygBeautyPreviewEnabled {
                let beauty = DualCameraBeautySession()
                try beauty.configure()
                newSession = beauty
            } else {
                let legacy = DualCameraSession()
                try legacy.configure()
                newSession = legacy
            }
            session = newSession
            newSession.setBeautyLevel(beautyLevel)
            applyDefaultLayoutFromSettings()
            launchState = .ready
            await refreshLatestThumbnail()
        } catch {
            launchState = .failed(String(describing: error))
        }
        #else
        launchState = .unsupported
        #endif
    }

    private func applyDefaultLayoutFromSettings() {
        layout = (settings.defaultLayout == .pip) ? .pip : .stacked
    }

    func startSession() {
        #if os(iOS)
        session?.start()
        #endif
    }

    func stopSession() {
        #if os(iOS)
        session?.stop()
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
        guard let session, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        do {
            let photos = try await session.capture(flashMode: flashMode.avFlashMode)
            let composed = compose(photos: photos)
            lastCapturedPhotos = photos
            composedImage = composed
            isPreviewPresented = true
        } catch {
            showToast("撮影に失敗しました")
        }
        #endif
    }

    func dismissPreviewForRetake() {
        #if os(iOS)
        isPreviewPresented = false
        composedImage = nil
        lastCapturedPhotos = nil
        #endif
    }

    #if os(iOS)
    /// 現在のプレビュー画像・撮影データを、設定「保存形式」に従ってフォトライブラリへ保存する。
    func saveToLibrary() async -> Bool {
        guard let composed = composedImage else { return false }
        var images: [UIImage] = [composed]
        if settings.saveMode == .composedAndOriginals,
           let photos = lastCapturedPhotos,
           let backImage = UIImage(data: photos.back),
           let frontImage = UIImage(data: photos.front) {
            images.append(backImage)
            images.append(frontImage)
        }
        do {
            try await PhotoLibraryService.save(images: images)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            showToast("保存しました")
            await refreshLatestThumbnail()
            return true
        } catch {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            showToast("保存に失敗しました")
            return false
        }
    }

    func refreshLatestThumbnail() async {
        latestThumbnail = await PhotoLibraryService.loadLatestThumbnail()
    }
    #endif

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
