import Foundation

/// 地図上の表示モード（ピン＋クラスタリング または ヒートマップ）。
enum MapDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case cluster = "ピン表示"
    case heatmap = "ヒートマップ"

    var id: String { rawValue }
}

/// 重大度フィルタ区分。
enum SeverityFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case all = "すべて"
    case fatalOnly = "死亡事故のみ"
    case injuryOnly = "負傷事故のみ"

    var id: String { rawValue }
}

/// 昼夜フィルタ区分。
enum TimeOfDayFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case all = "全時間帯"
    case daytime = "昼間"
    case nighttime = "夜間"

    var id: String { rawValue }
}

/// 事故類型フィルタ区分。
enum AccidentTypeFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case all = "すべての類型"
    case pedestrian = "人対車両（歩行者）"
    case vehicleToVehicle = "車両相互"
    case singleVehicle = "車両単独"

    var id: String { rawValue }

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

/// 交通事故データの絞り込み条件一式。
struct AccidentFilter: Equatable, Codable, Sendable {
    static let storageKey = "TrafficAccidentCheck.SavedFilter.v1"

    /// 対象年（nil の場合は全年度）
    var targetYear: UInt16? = nil
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

    /// フィルタが初期状態から変更されているかどうか
    var hasActiveCriteria: Bool {
        targetYear != nil || severity != .all || timeOfDay != .all || accidentType != .all || weather != .all
    }

    /// 指定された公式事故レコードがこのフィルタ条件に合致するか判定する。
    func matches(_ record: AccidentRecord) -> Bool {
        if let year = targetYear, record.year != year {
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
