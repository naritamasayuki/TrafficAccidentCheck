import CoreLocation
import Foundation

/// 事故の程度区分（色分け・色ごとの表示切替用）。
enum AccidentSeverityLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case fatal = "死亡事故"
    case multipleInjury = "複数負傷（2名以上）"
    case singleInjury = "負傷（1名）"

    var id: String { rawValue }

    /// 地図下部の凡例ボタン向けの短縮ラベル
    var shortLabel: String {
        switch self {
        case .fatal: return L10n.tr("死亡")
        case .multipleInjury: return L10n.tr("複数負傷")
        case .singleInjury: return L10n.tr("負傷")
        }
    }
}

/// 警察庁オープンデータ（本票）の1件分の交通事故レコード。
struct AccidentRecord: Identifiable, Equatable, Sendable {
    /// レコードの一意識別子（バイナリ内のインデックス）
    let id: Int
    /// 発生地点の緯度（世界測地系・10進度）
    let latitude: Double
    /// 発生地点の経度（世界測地系・10進度）
    let longitude: Double
    /// 発生年（西暦）
    let year: UInt16
    /// 発生月（1〜12）
    let month: UInt8
    /// 発生日（1〜31）
    let day: UInt8
    /// 発生時（0〜23）
    let hour: UInt8
    /// 発生分（0〜59）
    let minute: UInt8
    /// 事故内容コード（1: 死亡事故, 2: 負傷事故）
    let severityCode: UInt8
    /// 死者数
    let deaths: UInt8
    /// 負傷者数
    let injuries: UInt8
    /// 天候コード（1:晴, 2:曇, 3:雨, 4:霧, 5:雪）
    let weatherCode: UInt8
    /// 昼夜コード（11〜13:昼, 21〜23:夜）
    let dayNightCode: UInt8
    /// 路面状態コード（1:乾燥, 2:湿潤, 3:凍結, 4:積雪, 5:非舗装）
    let roadSurfaceCode: UInt8
    /// 道路形状コード
    let roadShapeCode: UInt8
    /// 信号機コード
    let signalCode: UInt8
    /// 事故類型コード（1:人対車両, 21:車両相互, 41:車両単独, 61:列車）
    let accidentTypeCode: UInt8
    /// 曜日コード（1:日〜7:土）
    let weekdayCode: UInt8
    /// 祝日コード（1:祝日当日, 2:祝日前日, 3:その他）
    let holidayCode: UInt8
    /// 当事者Aの種別コード
    let partyACode: UInt8
    /// 当事者Bの種別コード
    let partyBCode: UInt8
    /// 当事者Aの年齢層コード
    let ageACode: UInt8
    /// 当事者Bの年齢層コード
    let ageBCode: UInt8
    /// 都道府県コード
    let prefectureCode: UInt8
    /// 当事者Aの人身損傷程度コード
    let injuryACode: UInt8
    /// 当事者Bの人身損傷程度コード
    let injuryBCode: UInt8

    /// CoreLocation 用の座標
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 死亡事故かどうか
    var isFatal: Bool {
        severityCode == 1 || deaths > 0
    }

    /// 事故の程度区分（死亡 / 複数負傷 / 単数負傷）
    var severityLevel: AccidentSeverityLevel {
        if isFatal { return .fatal }
        if injuries >= 2 { return .multipleInjury }
        return .singleInjury
    }

    /// 夜間発生かどうか（21:夜-暮, 22:夜-夜, 23:夜-明）
    var isNighttime: Bool {
        dayNightCode >= 20
    }

    /// 表示用の発生日時文字列
    var formattedDateTime: String {
        let weekday = AccidentCodebook.weekdayName(for: weekdayCode)
        let hourStr = hour <= 23 ? String(format: "%02d", hour) : "--"
        let minStr = minute <= 59 ? String(format: "%02d", minute) : "--"
        return L10n.format("%d年%d月%d日(%@) %@:%@頃", Int(year), Int(month), Int(day), weekday, hourStr, minStr)
    }

    /// 表示用の概要タイトル
    var summaryTitle: String {
        let severity = L10n.tr(isFatal ? "死亡事故" : "負傷事故")
        let typeName = AccidentCodebook.accidentTypeName(for: accidentTypeCode)
        return "[\(severity)] \(typeName)"
    }
}

/// 警察庁オープンデータのコード値を日本語表記へ変換するコードブック。
enum AccidentCodebook {
    static func severityName(for code: UInt8) -> String {
        switch code {
        case 1: return L10n.tr("死亡事故")
        case 2: return L10n.tr("負傷事故")
        default: return L10n.tr("人身事故")
        }
    }

    static func weatherName(for code: UInt8) -> String {
        switch code {
        case 1: return L10n.tr("晴")
        case 2: return L10n.tr("曇")
        case 3: return L10n.tr("雨")
        case 4: return L10n.tr("霧")
        case 5: return L10n.tr("雪")
        default: return L10n.tr("不明")
        }
    }

    static func weatherSymbol(for code: UInt8) -> String {
        switch code {
        case 1: return "sun.max.fill"
        case 2: return "cloud.fill"
        case 3: return "cloud.rain.fill"
        case 4: return "cloud.fog.fill"
        case 5: return "snowflake"
        default: return "questionmark.circle"
        }
    }

    static func dayNightName(for code: UInt8) -> String {
        switch code {
        case 11: return L10n.tr("昼（明け方）")
        case 12: return L10n.tr("昼間")
        case 13: return L10n.tr("昼（夕方）")
        case 21: return L10n.tr("夜（日没直後）")
        case 22: return L10n.tr("夜間")
        case 23: return L10n.tr("夜（夜明け前）")
        default: return L10n.tr("不明")
        }
    }

    static func roadSurfaceName(for code: UInt8) -> String {
        switch code {
        case 1: return L10n.tr("乾燥（舗装）")
        case 2: return L10n.tr("湿潤・濡れ路面")
        case 3: return L10n.tr("凍結路面")
        case 4: return L10n.tr("積雪路面")
        case 5: return L10n.tr("非舗装道路")
        default: return L10n.tr("不明")
        }
    }

    static func roadShapeName(for code: UInt8) -> String {
        switch code {
        case 1, 31: return L10n.tr("交差点内")
        case 7, 37: return L10n.tr("交差点付近")
        case 11: return L10n.tr("トンネル内")
        case 12: return L10n.tr("橋・陸橋")
        case 13: return L10n.tr("カーブ・屈折路")
        case 14: return L10n.tr("一般単路（直線等）")
        case 21, 22, 23: return L10n.tr("踏切")
        case 0: return L10n.tr("一般交通の場所（駐車場等）")
        default: return L10n.tr("その他道路")
        }
    }

    static func signalName(for code: UInt8) -> String {
        switch code {
        case 1: return L10n.tr("信号あり（3灯式点灯）")
        case 2: return L10n.tr("信号あり（押ボタン式）")
        case 3, 4: return L10n.tr("信号あり（点滅中）")
        case 5, 6: return L10n.tr("信号消灯・故障中")
        case 7: return L10n.tr("信号機なし")
        case 8: return L10n.tr("信号あり（歩車分離式）")
        default: return L10n.tr("不明")
        }
    }

    static func accidentTypeName(for code: UInt8) -> String {
        switch code {
        case 1: return L10n.tr("人対車両（歩行者事故）")
        case 21: return L10n.tr("車両相互（衝突・追突等）")
        case 41: return L10n.tr("車両単独")
        case 61: return L10n.tr("列車・踏切事故")
        default: return L10n.tr("その他")
        }
    }

    static func partyTypeName(for code: UInt8) -> String {
        switch code {
        case 1: return L10n.tr("大型乗用車（バス等）")
        case 2: return L10n.tr("中型乗用車")
        case 7: return L10n.tr("準中型乗用車")
        case 3: return L10n.tr("普通乗用車")
        case 4: return L10n.tr("軽乗用車")
        case 5: return L10n.tr("ミニカー")
        case 11: return L10n.tr("大型貨物車（トラック）")
        case 12: return L10n.tr("中型貨物車")
        case 17: return L10n.tr("準中型貨物車")
        case 13: return L10n.tr("普通貨物車")
        case 14: return L10n.tr("軽貨物車")
        case 21, 22, 23, 24: return L10n.tr("特殊作業車")
        case 31, 32, 33, 34, 35: return L10n.tr("自動二輪車（バイク）")
        case 36: return L10n.tr("原付自転車")
        case 41, 42: return L10n.tr("路面電車・列車")
        case 43: return L10n.tr("特定小型原付（電動キックボード等）")
        case 51, 52: return L10n.tr("自転車")
        case 59: return L10n.tr("その他軽車両")
        case 61: return L10n.tr("歩行者")
        case 71, 72: return L10n.tr("道路上の人・その他")
        case 75: return L10n.tr("道路工作物・駐車車両等")
        case 76: return L10n.tr("相手なし（単独）")
        case 0: return L10n.tr("対象外・なし")
        default: return L10n.tr("その他車両")
        }
    }

    static func ageGroupName(for code: UInt8) -> String {
        switch code {
        case 1: return L10n.tr("24歳以下")
        case 25: return L10n.tr("25〜34歳")
        case 35: return L10n.tr("35〜44歳")
        case 45: return L10n.tr("45〜54歳")
        case 55: return L10n.tr("55〜64歳")
        case 65: return L10n.tr("65〜74歳")
        case 75: return L10n.tr("75歳以上")
        case 0: return L10n.tr("対象外・不明")
        default: return L10n.tr("不明")
        }
    }

    static func injuryDegreeName(for code: UInt8) -> String {
        switch code {
        case 1: return L10n.tr("死亡")
        case 2: return L10n.tr("負傷")
        case 4: return L10n.tr("損傷なし")
        default: return L10n.tr("対象外・不明")
        }
    }

    static func weekdayName(for code: UInt8) -> String {
        switch code {
        case 1: return L10n.tr("日")
        case 2: return L10n.tr("月")
        case 3: return L10n.tr("火")
        case 4: return L10n.tr("水")
        case 5: return L10n.tr("木")
        case 6: return L10n.tr("金")
        case 7: return L10n.tr("土")
        default: return "-"
        }
    }

    static func prefectureName(for code: UInt8) -> String {
        switch code {
        case 10...14: return L10n.tr("北海道")
        case 20: return L10n.tr("青森県")
        case 21: return L10n.tr("岩手県")
        case 22: return L10n.tr("宮城県")
        case 23: return L10n.tr("秋田県")
        case 24: return L10n.tr("山形県")
        case 25: return L10n.tr("福島県")
        case 30: return L10n.tr("東京都")
        case 40: return L10n.tr("茨城県")
        case 41: return L10n.tr("栃木県")
        case 42: return L10n.tr("群馬県")
        case 43: return L10n.tr("埼玉県")
        case 44: return L10n.tr("千葉県")
        case 45: return L10n.tr("神奈川県")
        case 46: return L10n.tr("新潟県")
        case 47: return L10n.tr("山梨県")
        case 48: return L10n.tr("長野県")
        case 49: return L10n.tr("静岡県")
        case 50: return L10n.tr("富山県")
        case 51: return L10n.tr("石川県")
        case 52: return L10n.tr("福井県")
        case 53: return L10n.tr("岐阜県")
        case 54: return L10n.tr("愛知県")
        case 55: return L10n.tr("三重県")
        case 60: return L10n.tr("滋賀県")
        case 61: return L10n.tr("京都府")
        case 62: return L10n.tr("大阪府")
        case 63: return L10n.tr("兵庫県")
        case 64: return L10n.tr("奈良県")
        case 65: return L10n.tr("和歌山県")
        case 70: return L10n.tr("鳥取県")
        case 71: return L10n.tr("島根県")
        case 72: return L10n.tr("岡山県")
        case 73: return L10n.tr("広島県")
        case 74: return L10n.tr("山口県")
        case 80: return L10n.tr("徳島県")
        case 81: return L10n.tr("香川県")
        case 82: return L10n.tr("愛媛県")
        case 83: return L10n.tr("高知県")
        case 90: return L10n.tr("福岡県")
        case 91: return L10n.tr("佐賀県")
        case 92: return L10n.tr("長崎県")
        case 93: return L10n.tr("熊本県")
        case 94: return L10n.tr("大分県")
        case 95: return L10n.tr("宮崎県")
        case 96: return L10n.tr("鹿児島県")
        case 97: return L10n.tr("沖縄県")
        default: return L10n.tr("全国")
        }
    }
}
