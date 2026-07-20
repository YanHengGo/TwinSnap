# Changelog

TwinSnap のリリース履歴。フォーマットは [Keep a Changelog](https://keepachangelog.com/) 準拠、バージョニングは [Semantic Versioning](https://semver.org/) に従う。

## [Unreleased]

## [0.2.0] - Phase B: WYSIWYG 美顔プレビュー

### Added
- **`AVCaptureVideoDataOutput` + `MTKView` によるプレビューパイプ**（`DualCameraBeautySession`）
  - `MetalPreviewRenderer` で `CIRenderDestination` 直接描画、前後で `CIContext` 共有
  - aspectFill・回転・ミラーリングを `AVCaptureConnection` 側で処理
- **プレビューへのリアルタイム美顔適用**
  - `BeautyProcessor.beautifyCIImage(_:level:faceRects:)` の CIImage 版 API
  - Vision 顔検出を 5フレーム周期に throttle し、キャッシュされた `faceRects` を再利用
- **`hardwareCost` 段階的降格**（Phase B-3）
  - 初期構成後に `hardwareCost` を検査、閾値 `0.95`
  - 4段階の降格ラダー: (24fps × best), (20fps × best), (24fps × 2nd), (20fps × 3rd)
  - 全滅時は `hardwareCostExceeded` を throw し、`CameraViewModel` が `DualCameraSession` にフォールバック
  - `MultiCamFormatSelector.selectRankedFormatPairs` で降格候補のソート済みリストを返す
- **熱シャットダウン保護**（Phase B-4）
  - `ThermalStateMonitor`: `ProcessInfo.thermalStateDidChangeNotification` を購読
  - `.serious` 以上が 5秒継続で `onSeriousSustained` を発火
  - 発火時に美顔チェーンを内部 suppression + トグル OFF 永続化 + ユーザートースト
- **`os.Logger` によるロギング基盤**（Phase B-5）
  - Subsystem `jp.yanheng.TwinSnap`
  - Category: `Session` / `Beauty` / `Thermal` / `Negotiate`
- **設定画面: 「実験機能」セクション**
  - WYSIWYG 美顔プレビューの ON/OFF トグル（永続化）
  - トグル変更時に「再起動してください」トースト

### Changed
- **`CameraSessionType` プロトコル**で `DualCameraSession` (legacy) と `DualCameraBeautySession` を透過的に扱えるように
- `CameraPreviewView` を `PreviewSource` enum でディスパッチ（`.legacy` / `.beauty`）
- `CameraViewModel.beautyLevel` の `didSet` で `session.setBeautyLevel(_:)` へ即時伝達
- `DualCameraBeautySession` を `+Setup` 拡張ファイルに分割し、class body を SwiftLint 制限内に

### Refactored
- `PhotoCaptureDelegate` を `Camera/PhotoCaptureDelegate.swift` に抽出し、両セッションで共有
- `MultiCamFormatSelector` を独立ファイル化、`selectBestFormatPair` は `selectRankedFormatPairs` の薄いラッパー
- `CameraViewModel` の型定義（`LaunchState` / `Layout` / `MainPosition` / `FlashMode`）を `CameraViewModelTypes.swift` に extension として分離
- `CameraViewModel` の合成ロジックを `CameraViewModel+Compose.swift` に extension として分離

## [0.1.0] - Phase A: 撮影後美顔・保存・共有・設定

### Added
- **`BeautyProcessor.apply(to:level:)`**: 撮影後の UIImage に美顔を適用
  - Vision 顔検出（`VNDetectFaceRectanglesRequest`）
  - 周波数分離ベースの肌なめらか化（`CIGaussianBlur` + α ブレンド + `CIColorControls`）
  - 顔検出失敗時のフォールバック（全体軽ブラー）
- **`CameraHUD` に美顔ボタン + スライダー**
- **`PhotoLibraryService`**: `PHPhotoLibrary` 保存・直近サムネイル取得（`readWrite` 権限）
- **`SettingsScreen`**: カメラ / 画質（表示専用）/ その他 の 3セクション
  - `AppSettings.defaultLayout`, `saveMode` を UserDefaults 永続化
- **`AboutScreen`**: バージョン表示
- **`PreviewScreen`**: 撮影後の全画面プレビュー、保存 / 共有 / 再撮影
- **`ShareLink` による共有**
- **アプリアイコン**（cute バージョン）

### Changed
- `PhotoComposer.composePiP`: PiP 位置マッピングを `videoGravity = .resizeAspectFill` 逆算に改善（横方向 aspectFill クロップを考慮）
- カメラ設定を Portrait 固定に変更（`INFOPLIST_KEY_UISupportedInterfaceOrientations_*`）

## [0.0.1] - MVP: MultiCam 同時撮影

### Added
- **`AVCaptureMultiCamSession`** による前後カメラ同時プレビュー + 撮影
- **`DualCameraSession`**: セッション構築、`MultiCamFormatSelector` で最適フォーマット選択
- **PiP / Stacked レイアウト切替**、PiP ドラッグ、main/PiP 入れ替え
- **フラッシュ（Torch）** 3状態切替
- **フォトライブラリ保存**
- **CI**: GitHub Actions で iOS ビルド + SwiftLint + Claude Code Review

[Unreleased]: https://github.com/USER/TwinSnap/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/USER/TwinSnap/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/USER/TwinSnap/compare/v0.0.1...v0.1.0
[0.0.1]: https://github.com/USER/TwinSnap/releases/tag/v0.0.1
