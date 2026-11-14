import Foundation

/// Google AdMob の設定値検証および開発用テストIDへの安全なフォールバックを担当する構造体。
/// 開発中の自己クリックによる規約違反や、ID未設定による強制終了を防止する。
struct AdMobConfiguration: Equatable, Sendable {
    /// Google 公式の iOS テスト用 AdMob アプリ ID
    static let officialTestAppID = "ca-app-pub-3940256099942544~1458002511"
    /// Google 公式の iOS テスト用アダプティブバナー広告ユニット ID
    static let officialTestBannerUnitID = "ca-app-pub-3940256099942544/2435281174"

    /// 有効化された AdMob アプリ ID
    let appID: String
    /// 有効化されたバナー広告ユニット ID
    let bannerUnitID: String
    /// 現在テスト広告モードで動作しているかどうか
    let isUsingTestAds: Bool

    /// Info.plist や環境変数から渡された文字列を検証し、安全な設定インスタンスを生成する。
    /// - Parameters:
    ///   - rawAppID: `GADApplicationIdentifier` または環境変数の値
    ///   - rawBannerUnitID: `AdMobBannerUnitID` または環境変数の値
    ///   - forceTestMode: `DEBUG` ビルド時など、強制的にテスト広告を使用する場合は `true`
    init(
        rawAppID: String?,
        rawBannerUnitID: String?,
        forceTestMode: Bool
    ) {
        let cleanedAppID = rawAppID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanedUnitID = rawBannerUnitID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let validAppID = Self.isValidAppID(cleanedAppID) ? cleanedAppID : Self.officialTestAppID
        self.appID = validAppID

        if forceTestMode {
            self.bannerUnitID = Self.officialTestBannerUnitID
            self.isUsingTestAds = true
        } else if Self.isValidBannerUnitID(cleanedUnitID) {
            self.bannerUnitID = cleanedUnitID
            self.isUsingTestAds = (cleanedUnitID == Self.officialTestBannerUnitID)
        } else {
            self.bannerUnitID = Self.officialTestBannerUnitID
            self.isUsingTestAds = true
        }
    }

    /// 現在の実行環境（Bundle / ProcessInfo）から設定を読み込む。
    static func current(bundle: Bundle = .main) -> AdMobConfiguration {
        let envAppID = ProcessInfo.processInfo.environment["ADMOB_APP_ID"]
        let plistAppID = bundle.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
        let envUnitID = ProcessInfo.processInfo.environment["ADMOB_BANNER_UNIT_ID"]
        let plistUnitID = bundle.object(forInfoDictionaryKey: "AdMobBannerUnitID") as? String

        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif

        return AdMobConfiguration(
            rawAppID: (envAppID?.isEmpty == false) ? envAppID : plistAppID,
            rawBannerUnitID: (envUnitID?.isEmpty == false) ? envUnitID : plistUnitID,
            forceTestMode: isDebug
        )
    }

    /// AdMob アプリ ID の形式（`ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY`）を検証する。
    static func isValidAppID(_ value: String) -> Bool {
        guard value.hasPrefix("ca-app-pub-"),
              !value.contains("$("),
              !value.contains("YOUR_"),
              !value.contains("XXXX") else {
            return false
        }
        let parts = value.replacingOccurrences(of: "ca-app-pub-", with: "").split(separator: "~")
        guard parts.count == 2,
              parts[0].count == 16,
              parts[1].count == 10,
              parts[0].allSatisfy(\.isNumber),
              parts[1].allSatisfy(\.isNumber) else {
            return false
        }
        return true
    }

    /// AdMob 広告ユニット ID の形式（`ca-app-pub-XXXXXXXXXXXXXXXX/ZZZZZZZZZZ`）を検証する。
    static func isValidBannerUnitID(_ value: String) -> Bool {
        guard value.hasPrefix("ca-app-pub-"),
              !value.contains("$("),
              !value.contains("YOUR_"),
              !value.contains("XXXX") else {
            return false
        }
        let parts = value.replacingOccurrences(of: "ca-app-pub-", with: "").split(separator: "/")
        guard parts.count == 2,
              parts[0].count == 16,
              parts[1].count == 10,
              parts[0].allSatisfy(\.isNumber),
              parts[1].allSatisfy(\.isNumber) else {
            return false
        }
        return true
    }
}
