//
//  Loggers.swift
//  TwinSnap
//
//  os.Logger の共有インスタンス。Console.app / Xcode Console で
//  subsystem = jp.yanheng.TwinSnap で絞り込み、Category で機能別に確認できる。
//

import OSLog

extension Logger {

    private static let subsystem = "jp.yanheng.TwinSnap"

    /// セッション生成・start/stop・legacy fallback などのライフサイクル。
    static let session = Logger(subsystem: subsystem, category: "Session")

    /// 美顔チェーンの beauty level / suppression 変更、fps メトリクスなど。
    static let beauty = Logger(subsystem: subsystem, category: "Beauty")

    /// ProcessInfo.thermalState 変化・自動 OFF 発火。
    static let thermal = Logger(subsystem: subsystem, category: "Thermal")

    /// hardwareCost チェック・降格試行の各ステップ。
    static let negotiate = Logger(subsystem: subsystem, category: "Negotiate")
}
