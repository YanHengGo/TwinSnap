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

    static func loadLatestThumbnail(targetSize: CGSize = CGSize(width: 200, height: 200)) async -> UIImage? {
        guard (try? await ensureAuthorization()) != nil else { return nil }

        let options = PHFetchOptions()
        options.fetchLimit = 1
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        guard let asset = result.firstObject else { return nil }

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
