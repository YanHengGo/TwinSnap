//
//  PhotoLibraryService.swift
//  TwinSnap
//
//  PHPhotoLibrary への保存と、直近1枚のサムネイル取得。
//

#if canImport(UIKit)
import Photos
import UIKit

enum PhotoLibraryError: Error {
    case notAuthorized
}

enum PhotoLibraryService {

    static func save(images: [UIImage]) async throws {
        guard !images.isEmpty else { return }
        try await ensureAuthorization()
        try await PHPhotoLibrary.shared().performChanges {
            for image in images {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        }
    }

    /// 動画ファイルをフォトライブラリへ保存する。Phase C-1-5 で追加。
    static func saveVideo(url: URL) async throws {
        try await ensureAuthorization()
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    /// 直近1件のメディア（画像 or 動画）のサムネイルを返す。
    /// Phase C-1-5 で動画も含めるように変更。
    static func loadLatestThumbnail(targetSize: CGSize = CGSize(width: 200, height: 200)) async -> UIImage? {
        guard (try? await ensureAuthorization()) != nil else { return nil }

        let options = PHFetchOptions()
        options.fetchLimit = 1
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let imageResult = PHAsset.fetchAssets(with: .image, options: options)
        let videoResult = PHAsset.fetchAssets(with: .video, options: options)
        let candidates = [imageResult.firstObject, videoResult.firstObject].compactMap { $0 }
        guard let asset = candidates.max(by: {
            ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
        }) else {
            return nil
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let requestOptions = PHImageRequestOptions()
            requestOptions.deliveryMode = .highQualityFormat
            requestOptions.isNetworkAccessAllowed = true
            requestOptions.resizeMode = .fast
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: requestOptions
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private static func ensureAuthorization() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let newStatus = await withCheckedContinuation { (continuation: CheckedContinuation<PHAuthorizationStatus, Never>) in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { continuation.resume(returning: $0) }
            }
            if newStatus == .authorized || newStatus == .limited { return }
            throw PhotoLibraryError.notAuthorized
        case .denied, .restricted:
            throw PhotoLibraryError.notAuthorized
        @unknown default:
            throw PhotoLibraryError.notAuthorized
        }
    }
}

#endif
