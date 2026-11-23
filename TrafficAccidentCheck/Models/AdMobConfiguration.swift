import Foundation

/// Google AdMob の設定値検証および開発用テストIDへの安全なフォールバックを担当する構造体。
/// 開発中の自己クリックによる規約違反や、ID未設定による強制終了を防止する。
struct AdMobConfiguration: Equatable, Sendable {
    /// Google 公式の iOS テスト用 AdMob アプリ ID
    static let officialTestAppID = "ca-app-pub-3940256099942544~1458002511"
    /// Google 公式の iOS テスト用アダプティブバナー広告ユニット ID
    static let officialTestBannerUnitID = "ca-app-pub-3940256099942544/2435281174"
    /// Google 公式の iOS テスト用インタースティシャル広告ユニット ID
    static let officialTestInterstitialUnitID = "ca-app-pub-3940256099942544/4411468910"

    /// 有効化された AdMob アプリ ID
    let appID: String
    /// 有効化されたバナー広告ユニット ID
    let bannerUnitID: String
    /// 有効化されたインタースティシャル広告ユニット ID
    let interstitialUnitID: String
    /// 現在テスト広告モードで動作しているかどうか
    let isUsingTestAds: Bool

    /// Info.plist や環境変数から渡された文字列を検証し、安全な設定インスタンスを生成する。
    /// - Parameters:
    ///   - rawAppID: `GADApplicationIdentifier` または環境変数の値
    ///   - rawBannerUnitID: `AdMobBannerUnitID` または環境変数の値
    ///   - rawInterstitialUnitID: `AdMobInterstitialUnitID` または環境変数の値
    ///   - forceTestMode: `DEBUG` ビルド時など、強制的にテスト広告を使用する場合は `true`
    init(
        rawAppID: String?,
        rawBannerUnitID: String?,
        rawInterstitialUnitID: String? = nil,
        forceTestMode: Bool
    ) {
        let cleanedAppID = rawAppID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanedUnitID = rawBannerUnitID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanedInterstitialID = rawInterstitialUnitID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let validAppID = Self.isValidAppID(cleanedAppID) ? cleanedAppID : Self.officialTestAppID
        self.appID = validAppID

        if forceTestMode {
            self.bannerUnitID = Self.officialTestBannerUnitID
            self.interstitialUnitID = Self.officialTestInterstitialUnitID
            self.isUsingTestAds = true
        } else {
            if Self.isValidBannerUnitID(cleanedUnitID) {
                self.bannerUnitID = cleanedUnitID
                self.isUsingTestAds = (cleanedUnitID == Self.officialTestBannerUnitID)
            } else {
                self.bannerUnitID = Self.officialTestBannerUnitID
                self.isUsingTestAds = true
            }
            if Self.isValidBannerUnitID(cleanedInterstitialID) {
                self.interstitialUnitID = cleanedInterstitialID
            } else {
                self.interstitialUnitID = Self.officialTestInterstitialUnitID
            }
        }
    }

    /// 現在の実行環境（Bundle / ProcessInfo）から設定を読み込む。
    static func current(bundle: Bundle = .main) -> AdMobConfiguration {
        let envAppID = ProcessInfo.processInfo.environment["ADMOB_APP_ID"]
        let plistAppID = bundle.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
        let envUnitID = ProcessInfo.processInfo.environment["ADMOB_BANNER_UNIT_ID"]
        let plistUnitID = bundle.object(forInfoDictionaryKey: "AdMobBannerUnitID") as? String
        let envInterstitialID = ProcessInfo.processInfo.environment["ADMOB_INTERSTITIAL_UNIT_ID"]
        let plistInterstitialID = bundle.object(forInfoDictionaryKey: "AdMobInterstitialUnitID") as? String

        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif

        return AdMobConfiguration(
            rawAppID: (envAppID?.isEmpty == false) ? envAppID : plistAppID,
            rawBannerUnitID: (envUnitID?.isEmpty == false) ? envUnitID : plistUnitID,
            rawInterstitialUnitID: (envInterstitialID?.isEmpty == false) ? envInterstitialID : plistInterstitialID,
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

/// Amazon アソシエイト（物販アフィリエイト）による交通安全グッズ購入導線を管理するモデル。
/// 景品表示法（ステマ規制）に配慮し、UI 側では必ず `PR` 表記と併せて表示する。
struct SafetyGoodsRecommendation: Identifiable, Equatable, Sendable {
    /// 共通 Amazon アソシエイト ID（日本・Amazon.co.jp）
    static let japanAssociateTag = "shirokumacamp-22"

    let id: String
    let titleKey: String
    let subtitleKey: String
    let systemImage: String
    let japaneseKeyword: String
    let globalKeyword: String

    /// 定番の交通安全グッズ一覧。
    static let allItems: [SafetyGoodsRecommendation] = [
        SafetyGoodsRecommendation(
            id: "dashcam",
            titleKey: "前後2カメラ ドライブレコーダー",
            subtitleKey: "万が一の衝突・あおり運転の証拠記録に",
            systemImage: "video.badge.checkmark",
            japaneseKeyword: "ドライブレコーダー 前後 2カメラ",
            globalKeyword: "dash cam front and rear"
        ),
        SafetyGoodsRecommendation(
            id: "reflective_vest",
            titleKey: "夜間用 反射ベスト・LED リフレクター",
            subtitleKey: "夜間や雨天の歩行・自転車・停車時の視認性向上に",
            systemImage: "flashlight.on.fill",
            japaneseKeyword: "交通安全 反射ベスト LED リフレクター",
            globalKeyword: "reflective safety vest LED"
        ),
        SafetyGoodsRecommendation(
            id: "escape_hammer",
            titleKey: "車載用 緊急脱出ハンマー",
            subtitleKey: "シートベルトカッター付き・水没や閉じ込め対策に",
            systemImage: "hammer.fill",
            japaneseKeyword: "車 緊急脱出ハンマー シートベルトカッター",
            globalKeyword: "car emergency escape hammer seatbelt cutter"
        ),
        SafetyGoodsRecommendation(
            id: "warning_triangle",
            titleKey: "三角表示板・LED 非常信号灯",
            subtitleKey: "高速道路や夜間の緊急停車時の二次事故防止に",
            systemImage: "exclamationmark.triangle.fill",
            japaneseKeyword: "車 三角表示板 LED 非常信号灯",
            globalKeyword: "car warning triangle LED road flare"
        ),
        SafetyGoodsRecommendation(
            id: "bike_safety",
            titleKey: "自転車用 高輝度ライト・ヘルメット",
            subtitleKey: "通勤・通学時の見落とし防止と頭部保護に",
            systemImage: "bicycle",
            japaneseKeyword: "自転車 ライト 高輝度 ヘルメット SG",
            globalKeyword: "bike LED light safety helmet"
        )
    ]

    /// 事故詳細（夜間・自転車/歩行者など）に合わせて最も関連性の高いグッズを 2 件選出する。
    static func recommended(for record: AccidentRecord) -> [SafetyGoodsRecommendation] {
        var selected: [SafetyGoodsRecommendation] = []
        if record.isNighttime, let vest = allItems.first(where: { $0.id == "reflective_vest" }) {
            selected.append(vest)
        }
        // 歩行者・自転車関連の事故類型・当事者の場合は自転車/視認グッズを優先
        if (record.accidentTypeCode == 1 || record.partyACode == 5 || record.partyBCode == 5 || record.partyACode == 6 || record.partyBCode == 6),
           let bike = allItems.first(where: { $0.id == "bike_safety" }),
           !selected.contains(bike) {
            selected.append(bike)
        }
        if let dashcam = allItems.first(where: { $0.id == "dashcam" }), !selected.contains(dashcam) {
            selected.append(dashcam)
        }
        if selected.count < 2,
           let hammer = allItems.first(where: { $0.id == "escape_hammer" }),
           !selected.contains(hammer) {
            selected.append(hammer)
        }
        return Array(selected.prefix(2))
    }

    /// ロケールに応じて安全な Amazon 検索 URL を `URLComponents` で生成する。
    /// 日本ロケール時は `amazon.co.jp` + `tag=shirokumacamp-22`、海外ロケール時は `amazon.com` を使用する。
    func amazonSearchURL(locale: Locale = .current) -> URL? {
        let isJapanLocale = Self.isJapan(locale: locale)
        var components = URLComponents()
        components.scheme = "https"
        components.host = isJapanLocale ? "www.amazon.co.jp" : "www.amazon.com"
        components.path = "/s"

        var queryItems = [
            URLQueryItem(name: "k", value: isJapanLocale ? japaneseKeyword : globalKeyword)
        ]
        if isJapanLocale {
            queryItems.append(URLQueryItem(name: "tag", value: Self.japanAssociateTag))
        }
        components.queryItems = queryItems
        return components.url
    }

    private static func isJapan(locale: Locale) -> Bool {
        if locale.region?.identifier.uppercased() == "JP" {
            return true
        }
        if locale.language.languageCode?.identifier.lowercased() == "ja" {
            return true
        }
        return false
    }
}

/// App Store の評価依頼（`requestReview`）のタイミングを制御するマネージャ。
/// ユーザーのストレスにならないよう、一定回数以上の利用と十分なクールダウン期間を設ける。
struct ReviewPromptManager: Sendable {
    static let actionCountKey = "TrafficAccidentCheck.ReviewActionCount.v1"
    static let lastRequestedAtKey = "TrafficAccidentCheck.ReviewLastRequestedAt.v1"

    /// 初回レビュー依頼を行うまでの最低アクション回数（診断詳細確認・お気に入り保存等）
    static let minimumActionCount = 3
    /// 再依頼までのクールダウン期間（90日）
    static let cooldownInterval: TimeInterval = 90 * 24 * 60 * 60

    /// 意味のある操作回数を1つ加算し、今レビュー依頼を表示すべきかどうかを返す。
    @discardableResult
    static func recordActionAndShouldRequestReview(
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> Bool {
        let nextCount = defaults.integer(forKey: actionCountKey) + 1
        defaults.set(nextCount, forKey: actionCountKey)

        guard nextCount >= minimumActionCount else { return false }

        let lastTimestamp = defaults.double(forKey: lastRequestedAtKey)
        if lastTimestamp > 0 {
            let elapsed = now.timeIntervalSince1970 - lastTimestamp
            if elapsed < cooldownInterval {
                return false
            }
        }

        defaults.set(now.timeIntervalSince1970, forKey: lastRequestedAtKey)
        return true
    }
}
