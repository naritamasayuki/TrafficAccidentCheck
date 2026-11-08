import CoreLocation
import Foundation

/// 周辺エリアの危険度ランク定義。
enum DangerLevel: String, Sendable {
    case safe = "低（安全）"
    case caution = "中（注意）"
    case warning = "高（警戒）"
    case critical = "極めて高い（厳重警戒）"

    var symbolName: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "flame.fill"
        }
    }
}

/// 指定座標（現在地またはマップ中心）周辺の危険度診断結果。
struct AreaDangerAssessment: Equatable, Sendable {
    /// 評価対象の半径（メートル）
    let radiusMeters: Double
    /// 危険度スコア（0〜100）
    let score: Int
    /// 危険度ランク
    let level: DangerLevel
    /// 半径内の公式事故件数
    let totalAccidents: Int
    /// 半径内の死亡事故件数
    let fatalAccidents: Int
    /// 夜間事故の割合（0.0〜1.0）
    let nightAccidentRatio: Double
    /// 半径内のSNS未確認速報件数
    let nearbySNSCount: Int
    /// 最も多い事故類型名
    let dominantAccidentType: String
    /// ドライバー・歩行者向けの注意アドバイス
    let safetyAdvice: String
}

/// 事故多発地点（ブラックスポット / 接近通知対象地点）。
struct AccidentHotspot: Identifiable, Equatable, Sendable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let accidentCount: Int
    let fatalCount: Int
    let dominantType: String

    static func == (lhs: AccidentHotspot, rhs: AccidentHotspot) -> Bool {
        lhs.id == rhs.id &&
            lhs.accidentCount == rhs.accidentCount &&
            lhs.fatalCount == rhs.fatalCount &&
            lhs.dominantType == rhs.dominantType &&
            lhs.coordinate.latitude == rhs.coordinate.latitude &&
            lhs.coordinate.longitude == rhs.coordinate.longitude
    }

    var alertTitle: String {
        fatalCount > 0 ? "⚠️ 死亡事故発生エリアに接近中" : "⚠️ 事故多発地点に接近中"
    }

    var alertBody: String {
        "周辺150m以内で過去に\(accidentCount)件の人身事故（うち死亡\(fatalCount)件・最多: \(dominantType)）が発生しています。速度を落として周囲を確認してください。"
    }
}

/// 事故統計およびSNS速報から周辺の危険度と事故多発ホットスポットを算出するアナライザー。
enum DangerAnalyzer {
    /// 指定座標から半径 `radiusMeters` 以内の事故とSNS速報を集計し、危険度診断結果を返す。
    static func evaluate(
        center: CLLocationCoordinate2D,
        accidentsInRadius: [AccidentRecord],
        allSNSReports: [SNSAccidentReport],
        radiusMeters: Double = 500.0
    ) -> AreaDangerAssessment {
        let total = accidentsInRadius.count
        let fatalCount = accidentsInRadius.filter(\.isFatal).count
        let nightCount = accidentsInRadius.filter(\.isNighttime).count
        let nightRatio = total > 0 ? Double(nightCount) / Double(total) : 0.0

        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let nearbySNS = allSNSReports.filter { report in
            let loc = CLLocation(latitude: report.latitude, longitude: report.longitude)
            return loc.distance(from: centerLocation) <= radiusMeters * 2.0
        }.count

        // スコア計算: 負傷事故1件=2点、死亡事故1件=25点、SNS直近速報1件=8点（上限100点）
        let rawScore = total * 2 + fatalCount * 25 + nearbySNS * 8
        let score = min(100, max(0, rawScore))

        let level: DangerLevel
        switch score {
        case 0..<15: level = .safe
        case 15..<40: level = .caution
        case 40..<70: level = .warning
        default: level = .critical
        }

        // 最多事故類型を 집계
        var typeHistogram: [UInt8: Int] = [:]
        for record in accidentsInRadius {
            typeHistogram[record.accidentTypeCode, default: 0] += 1
        }
        let topCode = typeHistogram.max(by: { $0.value < $1.value })?.key
        let dominantType = topCode.map { AccidentCodebook.accidentTypeName(for: $0) } ?? "データなし"

        let advice: String
        if fatalCount > 0 {
            advice = "半径\(Int(radiusMeters))m以内で死亡事故が\(fatalCount)件発生しています。交差点進入時や横断歩道手前での一時停止・減速を徹底してください。"
        } else if total >= 20 {
            advice = "事故が非常に集中しているエリアです（\(dominantType)が多発）。車間距離を十分にとり、右左折時の巻き込みに注意してください。"
        } else if nightRatio >= 0.45 && total >= 5 {
            advice = "夜間・薄暮時の事故割合が\(Int((nightRatio * 100).rounded()))%と高い地点です。早めのライト点灯と歩行者の見落としに注意してください。"
        } else if total > 0 {
            advice = "過去に\(total)件の人身事故が記録されています。見通しの悪い交差点や自転車の飛び出しに注意しましょう。"
        } else {
            advice = "半径\(Int(radiusMeters))m以内の公式事故記録は僅少ですが、引き続き安全運転を心がけてください。"
        }

        return AreaDangerAssessment(
            radiusMeters: radiusMeters,
            score: score,
            level: level,
            totalAccidents: total,
            fatalAccidents: fatalCount,
            nightAccidentRatio: nightRatio,
            nearbySNSCount: nearbySNS,
            dominantAccidentType: dominantType,
            safetyAdvice: advice
        )
    }

    /// 表示領域内の事故レコード群から、約150mメッシュ単位で事故が集中しているホットスポット（多発地点）を抽出する。
    static func detectHotspots(
        from records: [AccidentRecord],
        minimumCount: Int = 5,
        maxHotspots: Int = 15
    ) -> [AccidentHotspot] {
        guard !records.isEmpty else { return [] }

        // 約0.00135度 ≒ 150m グリッドでバケット化
        let gridStep = 0.00135
        struct GridKey: Hashable {
            let latBucket: Int
            let lonBucket: Int
        }

        var buckets: [GridKey: [AccidentRecord]] = [:]
        for rec in records {
            let key = GridKey(
                latBucket: Int((rec.latitude / gridStep).rounded()),
                lonBucket: Int((rec.longitude / gridStep).rounded())
            )
            buckets[key, default: []].append(rec)
        }

        var hotspots: [AccidentHotspot] = []
        for (key, group) in buckets {
            let fatalCount = group.filter(\.isFatal).count
            // 死亡事故が1件以上、または負傷事故が minimumCount 件以上のセルを多発地点とする
            guard group.count >= minimumCount || fatalCount > 0 else { continue }

            let avgLat = group.map(\.latitude).reduce(0, +) / Double(group.count)
            let avgLon = group.map(\.longitude).reduce(0, +) / Double(group.count)

            var typeHist: [UInt8: Int] = [:]
            for r in group { typeHist[r.accidentTypeCode, default: 0] += 1 }
            let topType = typeHist.max(by: { $0.value < $1.value })
                .map { AccidentCodebook.accidentTypeName(for: $0.key) } ?? "人身事故"

            hotspots.append(
                AccidentHotspot(
                    id: "hotspot-\(key.latBucket)-\(key.lonBucket)",
                    coordinate: CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon),
                    accidentCount: group.count,
                    fatalCount: fatalCount,
                    dominantType: topType
                )
            )
        }

        return hotspots
            .sorted { ($0.fatalCount * 10 + $0.accidentCount) > ($1.fatalCount * 10 + $1.accidentCount) }
            .prefix(maxHotspots)
            .map { $0 }
    }
}
