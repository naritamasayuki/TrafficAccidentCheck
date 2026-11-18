import CoreLocation
import Foundation

/// SNSおよびニュース速報から抽出された最新の未確認事故情報モデル。
/// 公式の警察庁オープンデータとは明確に区別し、「出典: SNS（未確認）」として地図上に表示する。
struct SNSAccidentReport: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let body: String
    let latitude: Double
    let longitude: Double
    let extractedLocation: String
    let postedAt: String
    let sourceName: String
    let sourceType: String
    let sourceURL: String
    let isUnverified: Bool
    let category: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// UI上で必ず明示する出典・未確認ラベル
    var sourceAttributionBadgeText: String {
        L10n.format("出典: %@ [未確認情報]", sourceName)
    }
}

/// `sns_reports.json` のルート構造。
struct SNSFeedPayload: Codable, Sendable {
    let generatedAt: String
    let disclaimer: String
    let reports: [SNSAccidentReport]
}
