//
//  AppSettings.swift
//  TwinSnap
//
//  永続化するユーザー設定。UserDefaults バックの @Observable。
//

import Foundation
import SwiftUI

enum SaveMode: String, CaseIterable, Identifiable {
    case composedOnly
    case composedAndOriginals

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .composedOnly: return "合成写真のみ"
        case .composedAndOriginals: return "合成 + 個別2枚"
        }
    }
}

enum DefaultLayout: String, CaseIterable, Identifiable {
    case pip
    case stacked

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pip: return "ピクチャ・イン・ピクチャ"
        case .stacked: return "上下2分割"
        }
    }
}

@Observable
final class AppSettings {

    var defaultLayout: DefaultLayout {
        didSet { store.set(defaultLayout.rawValue, forKey: Keys.defaultLayout) }
    }

    var saveMode: SaveMode {
        didSet { store.set(saveMode.rawValue, forKey: Keys.saveMode) }
    }

    /// Phase B: WYSIWYG 美顔プレビュー（VideoDataOutput + MTKView パス）を使うか。
    /// B-1 時点ではデバッグ用トグル。B-4 で「実験機能」として正式 UI 化する。
    var wysiwygBeautyPreviewEnabled: Bool {
        didSet { store.set(wysiwygBeautyPreviewEnabled, forKey: Keys.wysiwygBeautyPreviewEnabled) }
    }

    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        if let raw = store.string(forKey: Keys.defaultLayout),
           let value = DefaultLayout(rawValue: raw) {
            self.defaultLayout = value
        } else {
            self.defaultLayout = .pip
        }
        if let raw = store.string(forKey: Keys.saveMode),
           let value = SaveMode(rawValue: raw) {
            self.saveMode = value
        } else {
            self.saveMode = .composedAndOriginals
        }
        self.wysiwygBeautyPreviewEnabled = store.bool(forKey: Keys.wysiwygBeautyPreviewEnabled)
    }

    private enum Keys {
        static let defaultLayout = "settings.defaultLayout"
        static let saveMode = "settings.saveMode"
        static let wysiwygBeautyPreviewEnabled = "settings.wysiwygBeautyPreviewEnabled"
    }
}
