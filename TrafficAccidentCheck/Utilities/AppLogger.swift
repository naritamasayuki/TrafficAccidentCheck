import Foundation
import os

/// アプリ全体で使用する構造化ログ出力ユーティリティ。
/// エラー発生時に原因究明を迅速に行えるよう、カテゴリ別のロガーと詳細出力を提供する。
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.naritamasayuki.TrafficAccidentCheck"

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
        let msg = "[\(file):\(line)] \(context) - 詳細: \(error.localizedDescription) | \(stack)"
        logger.error("\(msg, privacy: .public)")
    }
}

/// 多言語化（日本語・英語・中国語）用のローカライズヘルパー。
enum L10n {
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, comment: "")
        return String(format: format, locale: Locale.current, arguments: args)
    }

    /// 現在のアプリ言語設定に応じた音声合成用BCP-47言語コード
    static var speechLanguageCode: String {
        let preferred = Bundle.main.preferredLocalizations.first ?? "ja"
        if preferred.hasPrefix("en") { return "en-US" }
        if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW") || preferred.hasPrefix("zh-HK") {
            return "zh-TW"
        }
        if preferred.hasPrefix("zh") { return "zh-CN" }
        return "ja-JP"
    }
}
