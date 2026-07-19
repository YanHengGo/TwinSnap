//
//  SettingsScreen.swift
//  TwinSnap
//
//  設定 Sheet。カメラ / 画質（表示専用） / その他 の3セクション。
//

#if canImport(UIKit)
import SwiftUI

struct SettingsScreen: View {

    @Bindable var settings: AppSettings
    let onDismiss: () -> Void

    @State private var showAbout: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                cameraSection
                qualitySection
                otherSection
                debugSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { onDismiss() }
                        .foregroundStyle(.white)
                }
            }
            .navigationDestination(isPresented: $showAbout) {
                AboutScreen()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var cameraSection: some View {
        Section("カメラ") {
            Picker("デフォルトレイアウト", selection: $settings.defaultLayout) {
                ForEach(DefaultLayout.allCases) { layout in
                    Text(layout.displayName).tag(layout)
                }
            }
            Picker("保存形式", selection: $settings.saveMode) {
                ForEach(SaveMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        }
    }

    private var qualitySection: some View {
        Section {
            HStack {
                Text("解像度")
                Spacer()
                Text("端末で自動選択")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("HDR")
                Spacer()
                Text("オフ")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("画質")
        } footer: {
            Text("MultiCam の安定動作を優先し、アプリが最適な設定を選択します。")
                .font(.caption)
        }
    }

    private var otherSection: some View {
        Section("その他") {
            HStack {
                Text("シャッター音")
                Spacer()
                Text("オン")
                    .foregroundStyle(.secondary)
            }
            Button {
                showAbout = true
            } label: {
                HStack {
                    Text("このアプリについて")
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var debugSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings.wysiwygBeautyPreviewEnabled },
                set: { settings.wysiwygBeautyPreviewEnabled = $0 }
            )) {
                Text("WYSIWYG 美顔プレビュー")
            }
        } header: {
            Text("デバッグ")
        } footer: {
            Text("プレビューに美顔フィルターをリアルタイム反映します。変更後はアプリを再起動してください。実験機能のため予期しない挙動が起こる可能性があります。")
                .font(.caption)
        }
    }
}

#endif
