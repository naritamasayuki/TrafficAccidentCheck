import CoreLocation
import Foundation

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

    /// 夜間発生かどうか（21:夜-暮, 22:夜-夜, 23:夜-明）
    var isNighttime: Bool {
        dayNightCode >= 20
    }

    /// 表示用の発生日時文字列
    var formattedDateTime: String {
        let weekday = AccidentCodebook.weekdayName(for: weekdayCode)
        let hourStr = hour <= 23 ? String(format: "%02d", hour) : "--"
        let minStr = minute <= 59 ? String(format: "%02d", minute) : "--"
        return "\(year)年\(month)月\(day)日(\(weekday)) \(hourStr):\(minStr)頃"
    }

    /// 表示用の概要タイトル
    var summaryTitle: String {
        let severity = isFatal ? "死亡事故" : "負傷事故"
        let typeName = AccidentCodebook.accidentTypeName(for: accidentTypeCode)
        return "[\(severity)] \(typeName)"
    }
}

/// 警察庁オープンデータのコード値を日本語表記へ変換するコードブック。
enum AccidentCodebook {
    static func severityName(for code: UInt8) -> String {
        switch code {
        case 1: return "死亡事故"
        case 2: return "負傷事故"
        default: return "人身事故"
        }
    }

    static func weatherName(for code: UInt8) -> String {
        switch code {
        case 1: return "晴"
        case 2: return "曇"
        case 3: return "雨"
        case 4: return "霧"
        case 5: return "雪"
        default: return "不明"
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
        case 11: return "昼（明け方）"
        case 12: return "昼間"
        case 13: return "昼（夕方）"
        case 21: return "夜（日没直後）"
        case 22: return "夜間"
        case 23: return "夜（夜明け前）"
        default: return "不明"
        }
    }

    static func roadSurfaceName(for code: UInt8) -> String {
        switch code {
        case 1: return "乾燥（舗装）"
        case 2: return "湿潤・濡れ路面"
        case 3: return "凍結路面"
        case 4: return "積雪路面"
        case 5: return "非舗装道路"
        default: return "不明"
        }
    }

    static func roadShapeName(for code: UInt8) -> String {
        switch code {
        case 1, 31: return "交差点内"
        case 7, 37: return "交差点付近"
        case 11: return "トンネル内"
        case 12: return "橋・陸橋"
        case 13: return "カーブ・屈折路"
        case 14: return "一般単路（直線等）"
        case 21, 22, 23: return "踏切"
        case 0: return "一般交通の場所（駐車場等）"
        default: return "その他道路"
        }
    }

    static func signalName(for code: UInt8) -> String {
        switch code {
        case 1: return "信号あり（3灯式点灯）"
        case 2: return "信号あり（押ボタン式）"
        case 3, 4: return "信号あり（点滅中）"
        case 5, 6: return "信号消灯・故障中"
        case 7: return "信号機なし"
        case 8: return "信号あり（歩車分離式）"
        default: return "不明"
        }
    }

    static func accidentTypeName(for code: UInt8) -> String {
        switch code {
        case 1: return "人対車両（歩行者事故）"
        case 21: return "車両相互（衝突・追突等）"
        case 41: return "車両単独"
        case 61: return "列車・踏切事故"
        default: return "その他"
        }
    }

    static func partyTypeName(for code: UInt8) -> String {
        switch code {
        case 1: return "大型乗用車（バス等）"
        case 2: return "中型乗用車"
        case 7: return "準中型乗用車"
        case 3: return "普通乗用車"
        case 4: return "軽乗用車"
        case 5: return "ミニカー"
        case 11: return "大型貨物車（トラック）"
        case 12: return "中型貨物車"
        case 17: return "準中型貨物車"
        case 13: return "普通貨物車"
        case 14: return "軽貨物車"
        case 21, 22, 23, 24: return "特殊作業車"
        case 31, 32, 33, 34, 35: return "自動二輪車（バイク）"
        case 36: return "原付自転車"
        case 41, 42: return "路面電車・列車"
        case 43: return "特定小型原付（電動キックボード等）"
        case 51, 52: return "自転車"
        case 59: return "その他軽車両"
        case 61: return "歩行者"
        case 71, 72: return "道路上の人・その他"
        case 75: return "道路工作物・駐車車両等"
        case 76: return "相手なし（単独）"
        case 0: return "対象外・なし"
        default: return "その他車両"
        }
    }

    static func ageGroupName(for code: UInt8) -> String {
        switch code {
        case 1: return "24歳以下"
        case 25: return "25〜34歳"
        case 35: return "35〜44歳"
        case 45: return "45〜54歳"
        case 55: return "55〜64歳"
        case 65: return "65〜74歳"
        case 75: return "75歳以上"
        case 0: return "対象外・不明"
        default: return "不明"
        }
    }

    static func injuryDegreeName(for code: UInt8) -> String {
        switch code {
        case 1: return "死亡"
        case 2: return "負傷"
        case 4: return "損傷なし"
        default: return "対象外・不明"
        }
    }

    static func weekdayName(for code: UInt8) -> String {
        switch code {
        case 1: return "日"
        case 2: return "月"
        case 3: return "火"
        case 4: return "水"
        case 5: return "木"
        case 6: return "金"
        case 7: return "土"
        default: return "-"
        }
    }

    static func prefectureName(for code: UInt8) -> String {
        switch code {
        case 10...14: return "北海道"
        case 20: return "青森県"
        case 21: return "岩手県"
        case 22: return "宮城県"
        case 23: return "秋田県"
        case 24: return "山形県"
        case 25: return "福島県"
        case 30: return "東京都"
        case 40: return "茨城県"
        case 41: return "栃木県"
        case 42: return "群馬県"
        case 43: return "埼玉県"
        case 44: return "千葉県"
        case 45: return "神奈川県"
        case 46: return "新潟県"
        case 47: return "山梨県"
        case 48: return "長野県"
        case 49: return "静岡県"
        case 50: return "富山県"
        case 51: return "石川県"
        case 52: return "福井県"
        case 53: return "岐阜県"
        case 54: return "愛知県"
        case 55: return "三重県"
        case 60: return "滋賀県"
        case 61: return "京都府"
        case 62: return "大阪府"
        case 63: return "兵庫県"
        case 64: return "奈良県"
        case 65: return "和歌山県"
        case 70: return "鳥取県"
        case 71: return "島根県"
        case 72: return "岡山県"
        case 73: return "広島県"
        case 74: return "山口県"
        case 80: return "徳島県"
        case 81: return "香川県"
        case 82: return "愛媛県"
        case 83: return "高知県"
        case 90: return "福岡県"
        case 91: return "佐賀県"
        case 92: return "長崎県"
        case 93: return "熊本県"
        case 94: return "大分県"
        case 95: return "宮崎県"
        case 96: return "鹿児島県"
        case 97: return "沖縄県"
        default: return "全国"
        }
    }
}
