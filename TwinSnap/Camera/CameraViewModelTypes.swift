//
//  CameraViewModelTypes.swift
//  TwinSnap
//
//  CameraViewModel が持つ状態 enum の定義。class body 肥大化を避けるため分離。
//

import AVFoundation
import Foundation

extension CameraViewModel {

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
}
