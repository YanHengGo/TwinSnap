//
//  VideoRecordingDelegate.swift
//  TwinSnap
//
//  AVCaptureMovieFileOutput の recording delegate。start/finish をクロージャで通知する。
//  MovieFileOutput は delegate を weak 参照するため、呼び出し側で strong 保持すること。
//

#if os(iOS)
import AVFoundation

final class VideoRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {

    private let onStart: (URL) -> Void
    private let onFinish: (URL, Error?) -> Void

    init(
        onStart: @escaping (URL) -> Void,
        onFinish: @escaping (URL, Error?) -> Void
    ) {
        self.onStart = onStart
        self.onFinish = onFinish
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        onStart(fileURL)
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        onFinish(outputFileURL, error)
    }
}

#endif
