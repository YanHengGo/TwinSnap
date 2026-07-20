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

    // MARK: - Recording state (Phase C-1)

    private(set) var captureMode: CaptureMode = .photo
    private(set) var isRecording: Bool = false
    private(set) var recordingElapsedSeconds: Int = 0
    #if os(iOS)
    private(set) var lastRecordedVideoURL: URL?
    var recordingDelegate: VideoRecordingDelegate?
    var recordingTimerTask: Task<Void, Never>?
    #endif

    /// 録画中はモード切替を無視する（誤操作防止）。
    func setCaptureMode(_ mode: CaptureMode) {
        guard !isRecording else { return }
        captureMode = mode
    }

    #if os(iOS)
    private(set) var session: (any CameraSessionType)?
    private(set) var composedImage: UIImage?
    private(set) var lastCapturedPhotos: DualCapturedPhotos?
    private(set) var latestThumbnail: UIImage?
    var isPreviewPresented: Bool = false
    private var thermalMonitor: ThermalStateMonitor?
    #endif

    let settings: AppSettings

    #if os(iOS)
    private var backgroundObserver: NSObjectProtocol?
    #endif

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        #if os(iOS)
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppWillResignActive()
        }
        #endif
    }

    deinit {
        #if os(iOS)
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        #endif
    }

    #if os(iOS)
    /// 録画中にアプリがバックグラウンド遷移した場合、自動的に停止する。
    /// 停止後の PhotoLibrary 保存は Task で発火するため、iOS がしばらくアプリを alive に保っている間に完了する可能性が高い。
    /// 完了しなかった場合の tmp 残骸は次回起動時にクリーンアップされる。
    private func handleAppWillResignActive() {
        guard isRecording else { return }
        Logger.session.notice("App will resign active during recording; stopping automatically")
        stopVideoRecording()
    }
    #endif

    // PiP レイアウトの基準座標（CameraView と揃える）
    let pipBase = CGPoint(x: 16, y: 100)
    let pipDisplaySize = CGSize(width: 120, height: 168)

    func bootstrap() async {
        #if os(iOS)
        Self.cleanupStaleTempVideos()
        #endif
        let granted = await requestCameraPermission()
        guard granted else {
            launchState = .permissionDenied
            return
        }
        guard isMultiCamSupported else {
            launchState = .unsupported
            return
        }
        // マイク権限はベストエフォート。拒否されても動画は音声なしで撮影可能とし、
        // 起動フローは止めない。
        let micGranted = await requestMicrophonePermission()
        if !micGranted {
            Logger.session.notice("Microphone permission not granted; video will be recorded without audio")
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

    private func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

#if os(iOS)

// MARK: - Video recording (Phase C-1)

extension CameraViewModel {

    /// 動画録画を開始する。tmp ディレクトリに mp4 を作成し、session の MovieFileOutput へ委譲する。
    /// 完了通知は `VideoRecordingDelegate` 経由で `handleRecordingFinished` に到達する。
    func startVideoRecording() {
        guard let session, !isRecording else { return }
        let url = Self.makeTempVideoURL()
        let delegate = VideoRecordingDelegate(
            onStart: { [weak self] startedURL in
                DispatchQueue.main.async {
                    self?.handleRecordingStarted(url: startedURL)
                }
            },
            onFinish: { [weak self] finishedURL, error in
                DispatchQueue.main.async {
                    self?.handleRecordingFinished(url: finishedURL, error: error)
                }
            }
        )
        // MovieFileOutput は delegate を weak 保持するため、ViewModel 側で strong 保持する
        recordingDelegate = delegate
        session.startRecording(to: url, delegate: delegate)
    }

    /// 動画録画を停止する。実際の完了は delegate の onFinish で通知される。
    func stopVideoRecording() {
        guard let session, isRecording else { return }
        session.stopRecording()
    }

    private func handleRecordingStarted(url: URL) {
        isRecording = true
        recordingElapsedSeconds = 0
        Logger.session.info("Recording started")
        startRecordingTimer()
    }

    private func handleRecordingFinished(url: URL, error: Error?) {
        stopRecordingTimer()
        isRecording = false
        recordingDelegate = nil
        if let error {
            Logger.session.error("Recording failed: \(error.localizedDescription, privacy: .public)")
            showToast("録画に失敗しました")
            try? FileManager.default.removeItem(at: url)
            lastRecordedVideoURL = nil
        } else {
            Logger.session.info("Recording finished successfully")
            lastRecordedVideoURL = url
            Task { await self.persistRecordedVideo(url: url) }
        }
    }

    /// 録画完了した tmp ファイルをフォトライブラリへ保存し、tmp を削除、サムネイルを更新する。
    private func persistRecordedVideo(url: URL) async {
        do {
            try await PhotoLibraryService.saveVideo(url: url)
            Logger.session.info("Video saved to photo library")
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            showToast("保存しました")
            try? FileManager.default.removeItem(at: url)
            await refreshLatestThumbnail()
        } catch {
            Logger.session.error("Video save failed: \(error.localizedDescription, privacy: .public)")
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            showToast("保存に失敗しました")
            // 保存失敗時は tmp を残す（次回のクリーンアップ機会に処理）
        }
    }

    private func startRecordingTimer() {
        recordingTimerTask?.cancel()
        recordingTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                guard let self else { break }
                self.recordingElapsedSeconds += 1
            }
        }
    }

    private func stopRecordingTimer() {
        recordingTimerTask?.cancel()
        recordingTimerTask = nil
    }

    private static func makeTempVideoURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TwinSnap-\(UUID().uuidString)")
            .appendingPathExtension("mov")
    }

    /// 起動時に呼ぶ。前回の保存失敗などで残っている TwinSnap-*.mov を削除する。
    static func cleanupStaleTempVideos() {
        let tmp = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tmp,
            includingPropertiesForKeys: nil
        ) else { return }
        var removed = 0
        for file in files
        where file.lastPathComponent.hasPrefix("TwinSnap-") && file.pathExtension == "mov" {
            try? FileManager.default.removeItem(at: file)
            removed += 1
        }
        if removed > 0 {
            Logger.session.info("Cleaned up \(removed) stale temp video files")
        }
    }
}

#endif
