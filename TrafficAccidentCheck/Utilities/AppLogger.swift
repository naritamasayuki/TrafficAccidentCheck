import Foundation
import os

/// アプリ全体で使用する構造化ログ出力ユーティリティ。
/// エラー発生時に原因究明を迅速に行えるよう、カテゴリ別のロガーと詳細出力を提供する。
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.example.TrafficAccidentCheck"

    /// データ読み込み・バイナリ解析用ロガー
    static let data = Logger(subsystem: subsystem, category: "DataStore")
    /// SNS・ネットワーク通信・ジオコーディング用ロガー
    static let network = Logger(subsystem: subsystem, category: "NetworkSNS")
    /// 地図描画・クラスタリング・ヒートマップ用ロガー
    static let map = Logger(subsystem: subsystem, category: "Map")
    /// 位置情報・接近通知用ロガー
    static let location = Logger(subsystem: subsystem, category: "LocationAlert")
    /// 広告（Google AdMob / ATT）用ロガー
    static let ad = Logger(subsystem: subsystem, category: "AdMob")

    /// 例外エラーを詳細メッセージおよびコールスタック情報とともに記録する。
    static func logError(
        _ logger: Logger,
        context: String,
        error: Error,
        file: String = #fileID,
        line: Int = #line
    ) {
        let stack = Thread.callStackSymbols.prefix(6).joined(separator: " | ")
        logger.error("[\(file, privacy: .public):\(line)] \(context, privacy: .public) - エラー詳細: \(error.localizedDescription, privacy: .public) | Stack: \(stack, privacy: .public)")
    }
}
