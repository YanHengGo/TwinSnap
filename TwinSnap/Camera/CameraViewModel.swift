//
//  CameraViewModel.swift
//  TwinSnap
//
//  カメラ権限・MultiCam対応判定・セッションのライフサイクル・レイアウト状態・撮影/プレビュー状態を管理する。
//

import AVFoundation
import CoreGraphics
import OSLog
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
    private var thermalMonitor: ThermalStateMonitor?
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
            let newSession = try makeSession()
            session = newSession
            newSession.setBeautyLevel(beautyLevel)
            if newSession is DualCameraBeautySession {
                startThermalMonitoring()
            }
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

    #if os(iOS)
    private func startThermalMonitoring() {
        let monitor = ThermalStateMonitor()
        monitor.onSeriousSustained = { [weak self] in
            self?.handleThermalSuppression()
        }
        thermalMonitor = monitor
    }

    private func handleThermalSuppression() {
        // 既に停止済み（トグル OFF）なら再発火しない
        guard settings.wysiwygBeautyPreviewEnabled else { return }
        Logger.thermal.notice("Thermal suppression triggered; disabling beauty preview and persisting toggle OFF")
        session?.setBeautySuppressed(true)
        settings.wysiwygBeautyPreviewEnabled = false
        showToast("端末が高温になったため WYSIWYG 美顔を停止しました")
    }
    #endif

    #if os(iOS)
    /// 設定に応じて Beauty / Legacy セッションを生成する。
    /// Beauty 側で hardwareCost 超過（`hardwareCostExceeded`）が発生した場合は
    /// 自動的に Legacy にフォールバックし、ユーザーへトーストで通知する。
    private func makeSession() throws -> any CameraSessionType {
        guard settings.wysiwygBeautyPreviewEnabled else {
            Logger.session.info("Bootstrapping legacy DualCameraSession (toggle OFF)")
            let legacy = DualCameraSession()
            try legacy.configure()
            return legacy
        }
        do {
            Logger.session.info("Bootstrapping DualCameraBeautySession (toggle ON)")
            let beauty = DualCameraBeautySession()
            try beauty.configure()
            return beauty
        } catch DualCameraSessionError.hardwareCostExceeded {
            Logger.session.notice("hardwareCost exceeded; falling back to legacy DualCameraSession")
            showToast("WYSIWYG プレビューはこの端末では利用できません（撮影後の美顔は動作します）")
            let legacy = DualCameraSession()
            try legacy.configure()
            return legacy
        }
    }
    #endif

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
