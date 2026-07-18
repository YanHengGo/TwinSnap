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
    var canvasSize: CGSize = .zero
    private(set) var isCapturing: Bool = false
    private(set) var toastMessage: String?
    var isSettingsPresented: Bool = false

    #if os(iOS)
    private(set) var dualSession: DualCameraSession?
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
    private let pipBase = CGPoint(x: 16, y: 100)
    private let pipDisplaySize = CGSize(width: 120, height: 168)

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

    #if os(iOS)
    private func compose(photos: DualCapturedPhotos) -> UIImage? {
        guard let backImage = UIImage(data: photos.back),
              let frontImage = UIImage(data: photos.front) else {
            return nil
        }
        let main: UIImage
        let sub: UIImage
        switch mainPosition {
        case .back:
            main = backImage
            sub = frontImage
        case .front:
            main = frontImage
            sub = backImage
        }

        switch layout {
        case .pip:
            let (center, size) = normalizedPipRect(imageSize: main.size)
            return PhotoComposer.composePiP(
                main: main,
                sub: sub,
                pipCenterNormalized: center,
                pipSizeNormalized: size
            )
        case .stacked:
            return PhotoComposer.composeStacked(main: main, sub: sub)
        }
    }

    /// プレビュー座標系（points）で置かれた PiP を、`imageSize` の画像内での正規化 [0,1] 座標に変換する。
    /// `videoGravity = .resizeAspectFill` で画像がキャンバスに表示されている前提で、
    /// aspectFill による中央クロップを逆算する。
    private func normalizedPipRect(imageSize: CGSize) -> (center: CGPoint, size: CGSize) {
        let canvas = canvasSize == .zero
            ? CGSize(width: pipDisplaySize.width * 3, height: pipDisplaySize.height * 5)
            : canvasSize

        // aspectFill: 1 preview point = pixelsPerPoint image pixels
        // 画像が両dim >= canvas となる最小スケールで拡大 → 逆比で min を取る
        let pixelsPerPoint = min(
            imageSize.width / canvas.width,
            imageSize.height / canvas.height
        )
        let viewportWidth = canvas.width * pixelsPerPoint
        let viewportHeight = canvas.height * pixelsPerPoint
        let cropOffsetX = (imageSize.width - viewportWidth) / 2
        let cropOffsetY = (imageSize.height - viewportHeight) / 2

        let originX = pipBase.x + pipOffset.width
        let originY = pipBase.y + pipOffset.height
        let centerXPreview = originX + pipDisplaySize.width / 2
        let centerYPreview = originY + pipDisplaySize.height / 2

        let centerXImage = cropOffsetX + centerXPreview * pixelsPerPoint
        let centerYImage = cropOffsetY + centerYPreview * pixelsPerPoint
        let widthImage = pipDisplaySize.width * pixelsPerPoint
        let heightImage = pipDisplaySize.height * pixelsPerPoint

        return (
            CGPoint(x: centerXImage / imageSize.width, y: centerYImage / imageSize.height),
            CGSize(width: widthImage / imageSize.width, height: heightImage / imageSize.height)
        )
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
