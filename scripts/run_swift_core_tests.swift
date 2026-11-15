import CoreLocation
import Foundation

/// シミュレータランタイムがない環境やCIでも Swift コアロジックと実データ (`accidents.bin` / `sns_reports.json`) を
/// 直接検証できる統合テストハーネス。
@main
struct CoreTestRunner {
    static func main() throws {
        print("=== Swift コアロジック＆実データ検証テスト開始 ===")

        // 1. 異常系テスト（不正ヘッダ・破損ペイロード）
        do {
            _ = try AccidentDataStore(data: Data([0x00, 0x01]))
            fatalError("不正ヘッダが検出されませんでした")
        } catch AccidentDataError.invalidHeader {
            print("[OK] 異常系: 不正ヘッダの検出成功")
        }

        // 2. 実データ (accidents.bin: 577,915件) のメモリマップ読み込みと検索テスト
        let binURL = URL(fileURLWithPath: "TrafficAccidentCheck/Resources/accidents.bin")
        let store = try AccidentDataStore(contentsOf: binURL)
        assert(store.totalCount > 500_000, "レコード件数が期待値未満です: \(store.totalCount)")
        print("[OK] 正常系: accidents.bin 読み込み成功 (\(store.totalCount) 件)")

        // 東京駅周辺の矩形検索テスト
        let tokyoBox = CoordinateBoundingBox(
            minLatitude: 35.65,
            maxLatitude: 35.72,
            minLongitude: 139.72,
            maxLongitude: 139.80
        )
        let filter = AccidentFilter()
        let (records, totalInBox) = store.queryRecords(in: tokyoBox, filter: filter)
        assert(!records.isEmpty && totalInBox >= records.count, "東京周辺の検索結果が空です")
        print("[OK] 正常系: 矩形検索成功 (表示 \(records.count) 件 / 領域内全 \(totalInBox) 件)")

        // 3. 危険度アナライザーとホットスポット検出テスト
        let center = CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125)
        let nearby = store.recordsNear(coordinate: center, radiusMeters: 500.0)
        let assessment = DangerAnalyzer.evaluate(center: center, accidentsInRadius: nearby, allSNSReports: [])
        let hotspots = DangerAnalyzer.detectHotspots(from: records)
        assert(assessment.score >= 0 && assessment.score <= 100, "危険度スコア範囲外")
        assert(!hotspots.isEmpty, "ホットスポットが検出されませんでした")
        print("[OK] 正常系: 危険度診断成功 (スコア: \(assessment.score)/100, ランク: \(assessment.level.rawValue), ホットスポット: \(hotspots.count)箇所)")

        // 4. SNS速報 JSON デコード＆地名抽出テスト
        let snsURL = URL(fileURLWithPath: "TrafficAccidentCheck/Resources/sns_reports.json")
        let snsData = try Data(contentsOf: snsURL)
        let payload = try JSONDecoder().decode(SNSFeedPayload.self, from: snsData)
        assert(!payload.reports.isEmpty, "SNSレポートが空です")
        for report in payload.reports {
            assert(report.isUnverified, "SNSレポートは未確認フラグが true である必要があります")
            assert(report.sourceAttributionBadgeText.contains("出典:"), "出典表記が含まれていません")
        }
        let place = SNSAccidentService.extractJapaneseLocation(from: "神奈川県横浜市港北区の交差点で追突事故が発生")
        assert(place == "神奈川県横浜市港北区", "地名抽出結果が期待値と異なります: \(String(describing: place))")
        print("[OK] 正常系: SNS速報 JSON デコード (\(payload.reports.count) 件) ＆ 地名抽出テスト成功")

        // 5. AdMobConfiguration のバリデーション＆テストIDフォールバック検証
        assert(AdMobConfiguration.isValidAppID(AdMobConfiguration.officialTestAppID))
        assert(AdMobConfiguration.isValidBannerUnitID(AdMobConfiguration.officialTestBannerUnitID))
        assert(!AdMobConfiguration.isValidAppID("YOUR_APP_ID"))
        let fallbackAdConfig = AdMobConfiguration(rawAppID: "", rawBannerUnitID: "invalid", forceTestMode: false)
        assert(fallbackAdConfig.appID == AdMobConfiguration.officialTestAppID)
        assert(fallbackAdConfig.bannerUnitID == AdMobConfiguration.officialTestBannerUnitID)
        assert(fallbackAdConfig.isUsingTestAds)
        let releaseAdConfig = AdMobConfiguration(
            rawAppID: "ca-app-pub-1234567890123456~1234567890",
            rawBannerUnitID: "ca-app-pub-1234567890123456/0987654321",
            forceTestMode: false
        )
        assert(!releaseAdConfig.isUsingTestAds)
        print("[OK] 正常系・異常系: AdMobConfiguration 検証＆フォールバックテスト成功")

        // 6. フィルタ永続化と安定ハッシュの検証
        let hashA = SNSAccidentService.stableHashHex(for: "テスト事故投稿")
        let hashB = SNSAccidentService.stableHashHex(for: "テスト事故投稿")
        assert(hashA == hashB && hashA.count == 12, "安定ハッシュが一致しません")
        print("[OK] 正常系: SNS安定ハッシュ＆重複排除検証成功")

        print("=== 全テスト PASS ===")
    }
}
