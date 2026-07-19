//
//  ThermalStateMonitor.swift
//  TwinSnap
//
//  ProcessInfo.thermalState を監視し、`.serious` 以上が 5秒継続した時にコールバックを発火する。
//  一瞬のスパイクで発火するのを避けるためのデバウンスを内蔵。
//

import Foundation

@Observable
final class ThermalStateMonitor {

    /// 現在の熱状態（通知経由でリアルタイム更新）。
    private(set) var currentState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    /// `.serious` 以上が `sustainedSeconds` 継続した際に呼ばれる。
    var onSeriousSustained: (() -> Void)?

    /// 発火判定に使う継続時間（秒）。
    private let sustainedSeconds: TimeInterval = 5.0

    private var pendingWorkItem: DispatchWorkItem?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleThermalChange()
        }
        // 起動時の状態も評価（既に高温で起動した場合の対応）
        handleThermalChange()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        pendingWorkItem?.cancel()
    }

    private func handleThermalChange() {
        let state = ProcessInfo.processInfo.thermalState
        currentState = state

        pendingWorkItem?.cancel()
        pendingWorkItem = nil

        guard state == .serious || state == .critical else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.checkSustainedFire()
        }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + sustainedSeconds, execute: workItem)
    }

    /// 5秒後、まだ `.serious` 以上であればコールバックを発火。
    /// 既にコールバック済みの場合も再発火する（トグル OFF 済みならクライアント側で判定）。
    private func checkSustainedFire() {
        let current = ProcessInfo.processInfo.thermalState
        guard current == .serious || current == .critical else { return }
        onSeriousSustained?()
    }
}
