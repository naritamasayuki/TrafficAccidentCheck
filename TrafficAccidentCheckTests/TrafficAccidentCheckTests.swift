import CoreLocation
import XCTest
@testable import TrafficAccidentCheck

/// 交通事故チェックアプリのユニットテストスイート。
/// バイナリデコーダ、異常系エラーハンドリング、フィルタ条件、危険度算出、SNS地名抽出を網羅的に検証する。
final class TrafficAccidentCheckTests: XCTestCase {

    // MARK: - 1. AccidentDataStore 正常系・異常系テスト

    func testDataStoreRejectsInvalidHeader() {
        let invalidData = Data([0x00, 0x01, 0x02])
        XCTAssertThrowsError(try AccidentDataStore(data: invalidData)) { error in
            guard case AccidentDataError.invalidHeader = error else {
                XCTFail("期待された invalidHeader エラーではありません: \(error)")
                return
            }
        }
    }

    func testDataStoreRejectsCorruptedPayloadSize() {
        var header = Data([0x54, 0x41, 0x43, 0x44]) // "TACD"
        var version: UInt32 = 1
        var count: UInt32 = 5 // 5件分(160B)を宣言しつつ実データがない異常ケース
        var reserved: UInt32 = 0
        withUnsafeBytes(of: &version) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &count) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &reserved) { header.append(contentsOf: $0) }

        XCTAssertThrowsError(try AccidentDataStore(data: header)) { error in
            guard case AccidentDataError.corruptedPayload = error else {
                XCTFail("期待された corruptedPayload エラーではありません: \(error)")
                return
            }
        }
    }

    func testDataStoreDecodeAndBoundingBoxQuery() throws {
        // 1件のテスト用バイナリレコードを構築（東京駅付近・2025年・死亡事故・夜間・雨）
        var blob = Data([0x54, 0x41, 0x43, 0x44])
        var version: UInt32 = 1
        var count: UInt32 = 1
        var reserved: UInt32 = 0
        withUnsafeBytes(of: &version) { blob.append(contentsOf: $0) }
        withUnsafeBytes(of: &count) { blob.append(contentsOf: $0) }
        withUnsafeBytes(of: &reserved) { blob.append(contentsOf: $0) }

        var latE6: Int32 = 35_681_236
        var lonE6: Int32 = 139_767_125
        var year: UInt16 = 2025
        withUnsafeBytes(of: &latE6) { blob.append(contentsOf: $0) }
        withUnsafeBytes(of: &lonE6) { blob.append(contentsOf: $0) }
        withUnsafeBytes(of: &year) { blob.append(contentsOf: $0) }

        let fields: [UInt8] = [
            11, // month
            8,  // day
            22, // hour
            15, // minute
            1,  // severity (死亡)
            1,  // deaths
            2,  // injuries
            3,  // weather (雨)
            22, // dayNight (夜)
            2,  // surface (湿潤)
            1,  // road (交差点)
            1,  // signal
            1,  // type (人対車両)
            1,  // weekday
            3,  // holiday
            3,  // partyA (普通乗用車)
            61, // partyB (歩行者)
            45, // ageA
            65, // ageB
            30, // pref (東京都)
            4,  // injuryA
            1   // injuryB (死亡)
        ]
        blob.append(contentsOf: fields)

        let store = try AccidentDataStore(data: blob)
        XCTAssertEqual(store.totalCount, 1)

        let rec = try XCTUnwrap(store.record(at: 0))
        XCTAssertEqual(rec.year, 2025)
        XCTAssertTrue(rec.isFatal)
        XCTAssertTrue(rec.isNighttime)
        XCTAssertEqual(rec.latitude, 35.681236, accuracy: 0.00001)
        XCTAssertEqual(rec.longitude, 139.767125, accuracy: 0.00001)
        XCTAssertEqual(AccidentCodebook.prefectureName(for: rec.prefectureCode), "東京都")

        // 範囲外インデックスは nil を返しクラッシュしないこと
        XCTAssertNil(store.record(at: -1))
        XCTAssertNil(store.record(at: 99))

        // フィルタ検索の検証
        let box = CoordinateBoundingBox(
            minLatitude: 35.60,
            maxLatitude: 35.75,
            minLongitude: 139.70,
            maxLongitude: 139.85
        )
        var filter = AccidentFilter()
        filter.severity = .fatalOnly
        filter.timeOfDay = .nighttime
        let (matched, total) = store.queryRecords(in: box, filter: filter)
        XCTAssertEqual(total, 1)
        XCTAssertEqual(matched.first?.id, 0)

        // 条件不一致フィルタでは0件になること
        filter.timeOfDay = .daytime
        let (_, daytimeTotal) = store.queryRecords(in: box, filter: filter)
        XCTAssertEqual(daytimeTotal, 0)
    }

    // MARK: - 2. DangerAnalyzer 危険度算出・ホットスポット検出テスト

    func testDangerAnalyzerEvaluatesHighRiskArea() {
        let center = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)
        let fatalRecord = AccidentRecord(
            id: 1,
            latitude: 35.6813,
            longitude: 139.7672,
            year: 2025,
            month: 5,
            day: 10,
            hour: 21,
            minute: 30,
            severityCode: 1,
            deaths: 1,
            injuries: 0,
            weatherCode: 1,
            dayNightCode: 22,
            roadSurfaceCode: 1,
            roadShapeCode: 1,
            signalCode: 1,
            accidentTypeCode: 1,
            weekdayCode: 7,
            holidayCode: 3,
            partyACode: 3,
            partyBCode: 61,
            ageACode: 35,
            ageBCode: 75,
            prefectureCode: 30,
            injuryACode: 4,
            injuryBCode: 1
        )

        let assessment = DangerAnalyzer.evaluate(
            center: center,
            accidentsInRadius: [fatalRecord],
            allSNSReports: []
        )
        XCTAssertGreaterThanOrEqual(assessment.score, 25)
        XCTAssertEqual(assessment.fatalAccidents, 1)
        XCTAssertEqual(assessment.dominantAccidentType, "人対車両（歩行者事故）")

        let hotspots = DangerAnalyzer.detectHotspots(from: [fatalRecord], minimumCount: 5)
        XCTAssertEqual(hotspots.count, 1, "死亡事故を含むセルは件数閾値未満でもホットスポットとして抽出されるべき")
    }

    // MARK: - 3. SNSAccidentService 地名抽出・出典表示テスト

    func testSNSLocationExtractionAndAttribution() {
        XCTAssertTrue(SNSAccidentService.isTrafficAccidentRelated("東京都品川区の交差点でトラックと乗用車が衝突事故"))
        XCTAssertFalse(SNSAccidentService.isTrafficAccidentRelated("昨日の配信は放送事故だった"))

        let extracted = SNSAccidentService.extractJapaneseLocation(
            from: "“正面部分が大破”トラックと乗用車が交差点で衝突事故 東京・品川区"
        )
        XCTAssertEqual(extracted, "東京都品川区")

        let report = SNSAccidentReport(
            id: "test-01",
            title: "テスト事故投稿",
            body: "テスト本文",
            latitude: 35.68,
            longitude: 139.76,
            extractedLocation: "東京都新宿区",
            postedAt: "2026-11-08T00:00:00Z",
            sourceName: "SNS (Bluesky)",
            sourceType: "sns_bluesky",
            sourceURL: "https://bsky.app",
            isUnverified: true,
            category: "車両相互（未確認）"
        )
        XCTAssertTrue(report.sourceAttributionBadgeText.contains("出典:"))
        XCTAssertTrue(report.sourceAttributionBadgeText.contains("未確認情報"))
    }

    // MARK: - 4. AdMobConfiguration 設定検証・フォールバックテスト

    func testAdMobConfigurationValidationAndFallback() {
        XCTAssertTrue(AdMobConfiguration.isValidAppID(AdMobConfiguration.officialTestAppID))
        XCTAssertTrue(AdMobConfiguration.isValidBannerUnitID(AdMobConfiguration.officialTestBannerUnitID))
        XCTAssertFalse(AdMobConfiguration.isValidAppID("YOUR_APP_ID"))
        XCTAssertFalse(AdMobConfiguration.isValidBannerUnitID("$(ADMOB_BANNER_UNIT_ID)"))

        // プレースホルダや不正値が渡された場合は公式テストIDへフォールバックすること
        let fallbackConfig = AdMobConfiguration(
            rawAppID: "YOUR_APP_ID",
            rawBannerUnitID: "INVALID_UNIT_ID",
            forceTestMode: false
        )
        XCTAssertEqual(fallbackConfig.appID, AdMobConfiguration.officialTestAppID)
        XCTAssertEqual(fallbackConfig.bannerUnitID, AdMobConfiguration.officialTestBannerUnitID)
        XCTAssertTrue(fallbackConfig.isUsingTestAds)

        // 本番IDが設定され、かつ forceTestMode == false (Release) の場合は本番IDが採用されること
        let prodAppID = "ca-app-pub-1234567890123456~1234567890"
        let prodUnitID = "ca-app-pub-1234567890123456/0987654321"
        let releaseConfig = AdMobConfiguration(
            rawAppID: prodAppID,
            rawBannerUnitID: prodUnitID,
            forceTestMode: false
        )
        XCTAssertEqual(releaseConfig.appID, prodAppID)
        XCTAssertEqual(releaseConfig.bannerUnitID, prodUnitID)
        XCTAssertFalse(releaseConfig.isUsingTestAds)

        // Debug時 (forceTestMode == true) は本番IDが設定されていても自己クリック防止のためテストユニットIDになること
        let debugConfig = AdMobConfiguration(
            rawAppID: prodAppID,
            rawBannerUnitID: prodUnitID,
            forceTestMode: true
        )
        XCTAssertEqual(debugConfig.bannerUnitID, AdMobConfiguration.officialTestBannerUnitID)
        XCTAssertTrue(debugConfig.isUsingTestAds)
    }

    // MARK: - 5. フィルタ設定の永続化と重複排除テスト

    func testAccidentFilterPersistenceAndHotspotDeduplication() {
        let suiteName = "TrafficAccidentCheckTests.FilterSuite"
        guard let testDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("テスト用UserDefaultsの生成に失敗")
            return
        }
        testDefaults.removePersistentDomain(forName: suiteName)

        var customFilter = AccidentFilter()
        XCTAssertEqual(customFilter.yearFilter, .recentThreeYears)
        XCTAssertEqual(customFilter.diagnosisRadius, .r100)
        XCTAssertEqual(customFilter.diagnosisRadius.meters, 100.0, accuracy: 0.001)
        XCTAssertFalse(customFilter.hasActiveCriteria)

        XCTAssertTrue(YearFilter.recentThreeYears.matches(year: 2025, latestYear: 2025))
        XCTAssertTrue(YearFilter.recentThreeYears.matches(year: 2024, latestYear: 2025))
        XCTAssertTrue(YearFilter.recentThreeYears.matches(year: 2023, latestYear: 2025))
        XCTAssertFalse(YearFilter.recentThreeYears.matches(year: 2022, latestYear: 2025))

        customFilter.yearFilter = .specific(2025)
        customFilter.diagnosisRadius = .r500
        XCTAssertTrue(customFilter.hasActiveCriteria)
        customFilter.severity = .fatalOnly
        customFilter.displayMode = .heatmap
        customFilter.showSNSReports = false
        customFilter.save(to: testDefaults)

        let restored = AccidentFilter.loadSaved(defaults: testDefaults)
        XCTAssertEqual(restored, customFilter)

        // 同一IDの事故レコードが重複して渡された場合でも二重カウントされないこと
        let rec = AccidentRecord(
            id: 42,
            latitude: 35.6812,
            longitude: 139.7671,
            year: 2025,
            month: 1,
            day: 1,
            hour: 12,
            minute: 0,
            severityCode: 1,
            deaths: 1,
            injuries: 0,
            weatherCode: 1,
            dayNightCode: 12,
            roadSurfaceCode: 1,
            roadShapeCode: 1,
            signalCode: 1,
            accidentTypeCode: 21,
            weekdayCode: 1,
            holidayCode: 3,
            partyACode: 3,
            partyBCode: 3,
            ageACode: 35,
            ageBCode: 45,
            prefectureCode: 30,
            injuryACode: 1,
            injuryBCode: 2
        )
        let spots = DangerAnalyzer.detectHotspots(from: [rec, rec, rec], minimumCount: 3)
        XCTAssertEqual(spots.first?.accidentCount, 1)

        XCTAssertEqual(
            SNSAccidentService.stableHashHex(for: "東京都新宿区で追突事故"),
            SNSAccidentService.stableHashHex(for: "東京都新宿区で追突事故")
        )

        var draft = BugReportDraft()
        draft.category = .locationAndVoice
        draft.detailText = "音声アナウンスのテスト報告"
        let body = draft.buildFormattedBody(
            appVersion: "1.0 (1)",
            osVersion: "iOS 18.0",
            filter: customFilter,
            isGoogleMapsConfigured: false
        )
        XCTAssertTrue(body.contains("現在地追従・音声アナウンス"))
        XCTAssertTrue(body.contains("音声アナウンスのテスト報告"))
        XCTAssertNotNil(
            draft.buildGitHubIssueURL(
                appVersion: "1.0 (1)",
                osVersion: "iOS 18.0",
                filter: customFilter,
                isGoogleMapsConfigured: false
            )
        )
    }
}
