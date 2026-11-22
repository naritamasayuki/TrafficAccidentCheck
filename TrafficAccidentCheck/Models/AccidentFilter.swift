import Foundation

/// 地図上の表示モード（ピン＋クラスタリング または ヒートマップ）。
enum MapDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case cluster = "ピン表示"
    case heatmap = "ヒートマップ"

    var id: String { rawValue }
    var localizedName: String { L10n.tr(rawValue) }
}

/// 重大度フィルタ区分。
enum SeverityFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case all = "すべて"
    case fatalOnly = "死亡事故のみ"
    case injuryOnly = "負傷事故のみ"

    var id: String { rawValue }
    var localizedName: String { L10n.tr(rawValue) }
}

/// 昼夜フィルタ区分。
enum TimeOfDayFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case all = "全時間帯"
    case daytime = "昼間"
    case nighttime = "夜間"

    var id: String { rawValue }
    var localizedName: String { L10n.tr(rawValue) }
}

/// 事故類型フィルタ区分。
enum AccidentTypeFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case all = "すべての類型"
    case pedestrian = "人対車両（歩行者）"
    case vehicleToVehicle = "車両相互"
    case singleVehicle = "車両単独"

    var id: String { rawValue }
    var localizedName: String { L10n.tr(rawValue) }

    func matches(code: UInt8) -> Bool {
        switch self {
        case .all: return true
        case .pedestrian: return code == 1
        case .vehicleToVehicle: return code == 21
        case .singleVehicle: return code == 41
        }
    }
}

/// 天候フィルタ区分。
enum WeatherFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case all = "全天候"
    case clear = "晴"
    case cloudy = "曇"
    case rain = "雨"
    case snowOrFog = "雪・霧"

    var id: String { rawValue }
    var localizedName: String { L10n.tr(rawValue) }

    func matches(code: UInt8) -> Bool {
        switch self {
        case .all: return true
        case .clear: return code == 1
        case .cloudy: return code == 2
        case .rain: return code == 3
        case .snowOrFog: return code == 4 || code == 5
        }
    }
}

/// 発生年の絞り込み区分。
enum YearFilter: Equatable, Hashable, Codable, Sendable {
    /// 直近3年（収録データの最新年から3年分）
    case recentThreeYears
    /// 全期間
    case all
    /// 特定の1年
    case specific(UInt16)

    /// 指定された最新年を基準に表示用ラベルを返す。
    func displayText(latestYear: UInt16) -> String {
        switch self {
        case .recentThreeYears:
            let startYear = latestYear >= 2 ? latestYear - 2 : latestYear
            return L10n.format("直近3年（%d〜%d年）", Int(startYear), Int(latestYear))
        case .all:
            return L10n.tr("すべて（全期間）")
        case .specific(let year):
            return L10n.format("%d年のみ", Int(year))
        }
    }

    /// 指定された年がこのフィルタ条件に合致するか判定する。
    func matches(year: UInt16, latestYear: UInt16) -> Bool {
        switch self {
        case .recentThreeYears:
            let minYear = latestYear >= 2 ? latestYear - 2 : 0
            return year >= minYear && year <= latestYear
        case .all:
            return true
        case .specific(let target):
            return year == target
        }
    }
}

/// 周辺危険度診断の対象半径区分（初期値は100m）。
enum DiagnosisRadiusFilter: Int, CaseIterable, Identifiable, Codable, Sendable {
    case r100 = 100
    case r300 = 300
    case r500 = 500
    case r1000 = 1000

    var id: Int { rawValue }

    /// メートル単位の半径値
    var meters: Double { Double(rawValue) }

    /// 表示用ラベル
    var displayText: String {
        rawValue >= 1000
            ? L10n.format("半径%dkm", rawValue / 1000)
            : L10n.format("半径%dm", rawValue)
    }
}

/// 交通事故データの絞り込み条件一式。
struct AccidentFilter: Equatable, Codable, Sendable {
    static let storageKey = "TrafficAccidentCheck.SavedFilter.v3"

    /// ストアが空の場合などに用いる基準年のフォールバック値（現在年）。
    static var defaultReferenceYear: UInt16 {
        UInt16(Calendar.current.component(.year, from: Date()))
    }

    /// 対象年フィルタ（初期表示は直近3年）
    var yearFilter: YearFilter = .recentThreeYears
    /// 周辺危険度診断の検索半径（初期値は半径100m）
    var diagnosisRadius: DiagnosisRadiusFilter = .r100
    /// 色分けごとの表示フラグ（赤: 死亡事故）
    var showFatalAccidents: Bool = true
    /// 色分けごとの表示フラグ（橙: 複数負傷事故）
    var showMultipleInjuryAccidents: Bool = true
    /// 色分けごとの表示フラグ（黄: 負傷事故1名）
    var showSingleInjuryAccidents: Bool = true
    /// 重大度（すべて / 死亡のみ / 負傷のみ）
    var severity: SeverityFilter = .all
    /// 昼夜区分
    var timeOfDay: TimeOfDayFilter = .all
    /// 事故類型区分
    var accidentType: AccidentTypeFilter = .all
    /// 天候区分
    var weather: WeatherFilter = .all
    /// SNS・速報データ（未確認情報）をマップ上に表示するかどうか
    var showSNSReports: Bool = true
    /// ユーザーが非表示（誤報・除外）に指定したSNS速報ID一覧
    var hiddenSNSReportIDs: Set<String> = []
    /// 地図の表示モード
    var displayMode: MapDisplayMode = .cluster
    /// 画面内に一度に描画する最大件数（パフォーマンス維持用）
    var maxVisibleRecords: Int = 1500

    /// 保存済みのフィルタ設定を復元する（存在しない場合やデコードエラー時はデフォルト値を返す）。
    static func loadSaved(defaults: UserDefaults = .standard) -> AccidentFilter {
        guard let data = defaults.data(forKey: storageKey) else {
            return AccidentFilter()
        }
        do {
            return try JSONDecoder().decode(AccidentFilter.self, from: data)
        } catch {
            AppLogger.logError(AppLogger.data, context: "保存済みフィルタ設定の復元失敗", error: error)
            return AccidentFilter()
        }
    }

    /// 現在のフィルタ設定を永続化する。
    func save(to defaults: UserDefaults = .standard) {
        do {
            let encoded = try JSONEncoder().encode(self)
            defaults.set(encoded, forKey: Self.storageKey)
        } catch {
            AppLogger.logError(AppLogger.data, context: "フィルタ設定の保存失敗", error: error)
        }
    }

    /// 指定された事故の程度区分が現在表示対象かどうか
    func isVisible(_ level: AccidentSeverityLevel) -> Bool {
        switch level {
        case .fatal: return showFatalAccidents
        case .multipleInjury: return showMultipleInjuryAccidents
        case .singleInjury: return showSingleInjuryAccidents
        }
    }

    /// 指定された事故の程度区分の表示/非表示を切り替える
    mutating func toggleVisibility(for level: AccidentSeverityLevel) {
        switch level {
        case .fatal: showFatalAccidents.toggle()
        case .multipleInjury: showMultipleInjuryAccidents.toggle()
        case .singleInjury: showSingleInjuryAccidents.toggle()
        }
    }

    /// フィルタが初期状態から変更されているかどうか
    var hasActiveCriteria: Bool {
        yearFilter != .recentThreeYears ||
            diagnosisRadius != .r100 ||
            !showFatalAccidents ||
            !showMultipleInjuryAccidents ||
            !showSingleInjuryAccidents ||
            severity != .all ||
            timeOfDay != .all ||
            accidentType != .all ||
            weather != .all
    }

    /// 指定された公式事故レコードがこのフィルタ条件に合致するか判定する。
    func matches(_ record: AccidentRecord, latestYear: UInt16 = AccidentFilter.defaultReferenceYear) -> Bool {
        guard yearFilter.matches(year: record.year, latestYear: latestYear) else {
            return false
        }
        guard isVisible(record.severityLevel) else {
            return false
        }
        switch severity {
        case .all: break
        case .fatalOnly:
            if !record.isFatal { return false }
        case .injuryOnly:
            if record.isFatal { return false }
        }
        switch timeOfDay {
        case .all: break
        case .daytime:
            if record.isNighttime { return false }
        case .nighttime:
            if !record.isNighttime { return false }
        }
        if !accidentType.matches(code: record.accidentTypeCode) {
            return false
        }
        if !weather.matches(code: record.weatherCode) {
            return false
        }
        return true
    }
}

/// バグ・不具合・改善要望の報告カテゴリ区分。
enum BugReportCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case mapDisplay = "地図・ピンの表示不具合"
    case locationAndVoice = "現在地追従・音声アナウンス"
    case snsData = "SNS・未確認速報の誤報・不具合"
    case crashOrPerformance = "アプリの動作・強制終了"
    case featureRequest = "機能改善のご要望"
    case other = "その他"

    var id: String { rawValue }
    var localizedName: String { L10n.tr(rawValue) }
}

/// バグ報告フォームの入力下書きおよびURL生成モデル（自動保存対応）。
struct BugReportDraft: Equatable, Codable, Sendable {
    static let storageKey = "TrafficAccidentCheck.BugReportDraft.v1"
    static let webFeedbackBaseURL = "https://naritamasayuki.github.io/TrafficAccidentCheck/feedback.html"
    static let supportEmailAddress = "doronko.narunaru@gmail.com"
    static let githubIssuesBaseURL = "https://github.com/naritamasayuki/TrafficAccidentCheck/issues/new"

    var category: BugReportCategory = .mapDisplay
    var detailText: String = ""
    var includeDiagnostics: Bool = true

    static func loadSaved(defaults: UserDefaults = .standard) -> BugReportDraft {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(BugReportDraft.self, from: data) else {
            return BugReportDraft()
        }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        if let encoded = try? JSONEncoder().encode(self) {
            defaults.set(encoded, forKey: Self.storageKey)
        }
    }

    /// 診断情報付きの報告本文テキストを生成する。
    func buildFormattedBody(
        appVersion: String,
        osVersion: String,
        filter: AccidentFilter,
        isGoogleMapsConfigured: Bool
    ) -> String {
        let userText = detailText.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptionSection = userText.isEmpty ? "（詳細未入力）" : userText

        var lines: [String] = [
            "【報告カテゴリ】\(category.rawValue)",
            "",
            "【発生状況・詳細】",
            descriptionSection
        ]

        if includeDiagnostics {
            let yearStr = filter.yearFilter.displayText(latestYear: AccidentFilter.defaultReferenceYear)
            let mapEngine = isGoogleMapsConfigured ? "Google Maps SDK" : "MapKit互換モード"
            lines.append(contentsOf: [
                "",
                "--- 自動診断情報 ---",
                "・アプリバージョン: \(appVersion)",
                "・OS環境: \(osVersion)",
                "・マップ描画モード: \(mapEngine) / \(filter.displayMode.rawValue)",
                "・フィルタ設定: 年度=\(yearStr), 診断半径=\(filter.diagnosisRadius.displayText), 重大度=\(filter.severity.rawValue), 時間帯=\(filter.timeOfDay.rawValue)",
                "・SNS速報表示: \(filter.showSNSReports ? "ON" : "OFF")"
            ])
        }
        return lines.joined(separator: "\n")
    }

    /// ログイン不要の Web フィードバックフォーム URL を生成する（カテゴリ・本文・環境情報を事前入力）。
    func buildWebFeedbackURL(
        appVersion: String,
        osVersion: String,
        filter: AccidentFilter,
        isGoogleMapsConfigured: Bool
    ) -> URL? {
        let body = buildFormattedBody(
            appVersion: appVersion,
            osVersion: osVersion,
            filter: filter,
            isGoogleMapsConfigured: isGoogleMapsConfigured
        )

        var components = URLComponents(string: Self.webFeedbackBaseURL)
        components?.queryItems = [
            URLQueryItem(name: "app", value: "事故マップ - 交通事故チェック"),
            URLQueryItem(name: "category", value: category.rawValue),
            URLQueryItem(name: "version", value: appVersion),
            URLQueryItem(name: "os", value: osVersion),
            URLQueryItem(name: "body", value: body)
        ]
        return components?.url
    }

    /// 標準メールアプリで直接送信するための `mailto:` URL を生成する。
    func buildMailtoURL(
        appVersion: String,
        osVersion: String,
        filter: AccidentFilter,
        isGoogleMapsConfigured: Bool
    ) -> URL? {
        let shortSummary = String(detailText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        let titleSuffix = shortSummary.isEmpty ? "アプリ内からの報告" : shortSummary
        let subject = "[事故マップ][\(category.rawValue)] \(titleSuffix)"
        let body = buildFormattedBody(
            appVersion: appVersion,
            osVersion: osVersion,
            filter: filter,
            isGoogleMapsConfigured: isGoogleMapsConfigured
        )

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.supportEmailAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    /// GitHub Issue 作成画面の URL を生成する（タイトルと本文をクエリパラメータで自動入力）。
    func buildGitHubIssueURL(
        appVersion: String,
        osVersion: String,
        filter: AccidentFilter,
        isGoogleMapsConfigured: Bool
    ) -> URL? {
        let shortSummary = String(detailText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        let titleSuffix = shortSummary.isEmpty ? "アプリ内からの報告" : shortSummary
        let title = "[\(category.rawValue)] \(titleSuffix)"
        let body = buildFormattedBody(
            appVersion: appVersion,
            osVersion: osVersion,
            filter: filter,
            isGoogleMapsConfigured: isGoogleMapsConfigured
        )

        var components = URLComponents(string: Self.githubIssuesBaseURL)
        components?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body)
        ]
        return components?.url
    }
}
