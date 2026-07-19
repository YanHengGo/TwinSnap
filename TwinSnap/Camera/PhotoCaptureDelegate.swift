//
//  PhotoCaptureDelegate.swift
//  TwinSnap
//
//  AVCapturePhotoCaptureDelegate の共有実装。両セッション種別で利用する。
//

#if os(iOS)
import AVFoundation

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {

    let uniqueID: Int64
    let completion: (Int64, Result<Data, Error>) -> Void

    init(uniqueID: Int64, completion: @escaping (Int64, Result<Data, Error>) -> Void) {
        self.uniqueID = uniqueID
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            completion(uniqueID, .failure(error))
        } else if let data = photo.fileDataRepresentation() {
            completion(uniqueID, .success(data))
        } else {
            completion(uniqueID, .failure(DualCameraSessionError.captureFailed))
        }
    }
}

#endif
