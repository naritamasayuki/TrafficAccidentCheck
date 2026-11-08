import CoreLocation
import SwiftUI

/// メイン画面ビュー。
/// 地図表示、現在地周辺の危険度スコアカード、クイックフィルタ、SNS速報更新、事故多発地点の接近警告を統合する。
struct ContentView: View {
    let isGoogleMapsConfigured: Bool

    @StateObject private var locationManager = LocationAndAlertManager()
    @State private var dataStore: AccidentDataStore = AccidentDataStore.emptyStore()
    @State private var dataLoadErrorMessage: String?

    @State private var filter = AccidentFilter()
    @State private var visibleRecords: [AccidentRecord] = []
    @State private var totalMatchedInBox: Int = 0
    @State private var hotspots: [AccidentHotspot] = []

    @State private var snsReports: [SNSAccidentReport] = []
    @State private var isRefreshingSNS = false
    @State private var lastSNSUpdatedText: String = "同梱データ読込済"

    @State private var cameraCenter = LocationAndAlertManager.defaultCoordinate
    @State private var cameraZoom: Float = 14.5
    @State private var cameraMoveTrigger: Int = 0
    @State private var currentBoundingBox = CoordinateBoundingBox(
        minLatitude: 35.660,
        maxLatitude: 35.705,
        minLongitude: 139.740,
        maxLongitude: 139.795
    )

    @State private var dangerAssessment: AreaDangerAssessment?
    @State private var selectedAccident: AccidentRecord?
    @State private var selectedSNSReport: SNSAccidentReport?
    @State private var isShowingFilterSheet = false
    @State private var isShowingDangerDetail = false

    private let snsService = SNSAccidentService()

    var body: some View {
        ZStack(alignment: .top) {
            // メイン地図レイヤー（Google Maps SDK / 未設定時は MapKit 自動フォールバック）
            mapLayer
                .ignoresSafeArea(edges: .bottom)

            // 上部オーバーレイ（危険度カード・クイックフィルタ・接近警告バナー）
            VStack(spacing: 8) {
                topDangerBar
                quickControlBar

                if !isGoogleMapsConfigured {
                    apiKeyNoticeBanner
                }

                if let errorMsg = dataLoadErrorMessage {
                    errorBanner(message: errorMsg)
                }

                if let alertSpot = locationManager.activeHotspotAlert {
                    hotspotProximityBanner(spot: alertSpot)
                }

                Spacer()

                bottomStatusLegendBar
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .sheet(item: $selectedAccident) { record in
            AccidentDetailSheet(record: record)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedSNSReport) { report in
            SNSReportDetailSheet(report: report)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isShowingFilterSheet) {
            FilterSheet(
                filter: $filter,
                isProximityAlertEnabled: $locationManager.isProximityAlertEnabled,
                onJumpToCoordinate: { coord, _ in
                    jumpToCoordinate(coord)
                },
                onSimulateHotspotAlert: {
                    if let spot = hotspots.first {
                        locationManager.simulateApproach(to: spot.coordinate)
                    }
                }
            )
        }
        .onChange(of: filter) { _, _ in
            refreshMapData()
        }
        .task {
            await initializeAppData()
        }
    }

    // MARK: - Map Layer

    @ViewBuilder
    private var mapLayer: some View {
        let activeSNS = filter.showSNSReports ? snsReports : []
        if isGoogleMapsConfigured {
            GoogleMapContainerView(
                records: visibleRecords,
                snsReports: activeSNS,
                hotspots: hotspots,
                displayMode: filter.displayMode,
                cameraCenter: $cameraCenter,
                cameraZoom: $cameraZoom,
                cameraMoveTrigger: cameraMoveTrigger,
                onRegionChanged: { box, center, zoom in
                    currentBoundingBox = box
                    cameraCenter = center
                    cameraZoom = zoom
                    refreshMapData()
                },
                onSelectAccident: { rec in
                    selectedAccident = rec
                },
                onSelectSNSReport: { report in
                    selectedSNSReport = report
                }
            )
        } else {
            FallbackMapKitView(
                records: visibleRecords,
                snsReports: activeSNS,
                hotspots: hotspots,
                displayMode: filter.displayMode,
                cameraCenter: $cameraCenter,
                cameraMoveTrigger: cameraMoveTrigger,
                onRegionChanged: { box, center, zoom in
                    currentBoundingBox = box
                    cameraCenter = center
                    cameraZoom = zoom
                    refreshMapData()
                },
                onSelectAccident: { rec in
                    selectedAccident = rec
                },
                onSelectSNSReport: { report in
                    selectedSNSReport = report
                }
            )
        }
    }

    // MARK: - Overlay Components

    private var topDangerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let assessment = dangerAssessment {
                    Image(systemName: assessment.level.symbolName)
                        .font(.title2)
                        .foregroundStyle(colorForDanger(assessment.level))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("周辺500m危険度: \(assessment.level.rawValue)")
                                .font(.subheadline.bold())
                            Text("(\(assessment.score)/100)")
                                .font(.caption.monospacedDigit().bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(colorForDanger(assessment.level).opacity(0.18), in: Capsule())
                        }
                        Text("人身事故 \(assessment.totalAccidents)件（死亡 \(assessment.fatalAccidents)件 / 夜間 \(Int((assessment.nightAccidentRatio * 100).rounded()))%）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                    Text("事故統計データを集計中...")
                        .font(.subheadline)
                }

                Spacer()

                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        isShowingDangerDetail.toggle()
                    }
                } label: {
                    Image(systemName: isShowingDangerDetail ? "chevron.up.circle.fill" : "info.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            if isShowingDangerDetail, let assessment = dangerAssessment {
                Divider()
                Text(assessment.safetyAdvice)
                    .font(.caption)
                    .foregroundStyle(.primary)
                HStack {
                    Label("最多類型: \(assessment.dominantAccidentType)", systemImage: "car.2.fill")
                    Spacer()
                    Label("多発地点監視: \(hotspots.count)箇所", systemImage: "bell.badge.fill")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }

    private var quickControlBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    isShowingFilterSheet = true
                } label: {
                    Label(
                        filter.hasActiveCriteria ? "絞り込み中" : "絞り込み・都市選択",
                        systemImage: "slider.horizontal.3"
                    )
                    .font(.caption.bold())
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(filter.hasActiveCriteria ? Color.accentColor : Color(.secondarySystemBackground))
                    .foregroundStyle(filter.hasActiveCriteria ? .white : .primary)
                    .clipShape(Capsule())
                }

                Button {
                    filter.displayMode = (filter.displayMode == .cluster) ? .heatmap : .cluster
                } label: {
                    Label(
                        filter.displayMode == .cluster ? "ヒートマップへ切替" : "ピン表示へ切替",
                        systemImage: filter.displayMode == .cluster ? "flame.fill" : "mappin.and.ellipse"
                    )
                    .font(.caption.bold())
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
                }

                Button {
                    filter.severity = (filter.severity == .fatalOnly) ? .all : .fatalOnly
                } label: {
                    Label("死亡事故のみ", systemImage: "xmark.octagon.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(filter.severity == .fatalOnly ? Color.red : Color(.secondarySystemBackground))
                        .foregroundStyle(filter.severity == .fatalOnly ? .white : .primary)
                        .clipShape(Capsule())
                }

                Button {
                    filter.showSNSReports.toggle()
                } label: {
                    Label(
                        "SNS速報(未確認): \( snsReports.count)件",
                        systemImage: filter.showSNSReports ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.caption.bold())
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(filter.showSNSReports ? Color.purple : Color(.secondarySystemBackground))
                    .foregroundStyle(filter.showSNSReports ? .white : .primary)
                    .clipShape(Capsule())
                }

                Button {
                    Task { await refreshSNSFeed() }
                } label: {
                    HStack(spacing: 4) {
                        if isRefreshingSNS {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("SNS更新")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
                }
                .disabled(isRefreshingSNS)
            }
        }
    }

    private var apiKeyNoticeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "map.fill")
                .foregroundStyle(.orange)
            Text("Config/Secrets.xcconfig に Google Maps APIキーを設定すると Google Maps SDK 描画に切り替わります（現在は互換マップで動作中）")
                .font(.caption2)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
            Spacer()
        }
        .padding(8)
        .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    private func hotspotProximityBanner(spot: AccidentHotspot) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.and.waves.left.and.right.fill")
                .font(.title3)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 3) {
                Text(spot.alertTitle)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                Text(spot.alertBody)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.95))
            }
            Spacer()
            Button {
                locationManager.activeHotspotAlert = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(10)
        .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 5)
    }

    private var bottomStatusLegendBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 9, height: 9)
                Text("死亡事故")
            }
            HStack(spacing: 4) {
                Circle().fill(Color.orange).frame(width: 9, height: 9)
                Text("負傷事故")
            }
            HStack(spacing: 4) {
                Circle().fill(Color.purple).frame(width: 9, height: 9)
                Text("出典:SNS(未確認)")
            }
            Spacer()
            Text("表示 \(visibleRecords.count)/\(totalMatchedInBox)件 (全国\(dataStore.totalCount.formatted())件)")
                .monospacedDigit()
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Data & Actions

    private func initializeAppData() async {
        locationManager.requestPermissionsAndStart()

        // 1. 公式オープンデータバイナリのロード
        do {
            let store = try AccidentDataStore()
            self.dataStore = store
        } catch {
            self.dataLoadErrorMessage = error.localizedDescription
        }

        // 2. 同梱SNS速報データのロード
        let initialSNS = snsService.loadBundledReports()
        self.snsReports = initialSNS

        // 3. 初回マップ領域検索＆危険度計算
        refreshMapData()

        // 4. バックグラウンドで最新の無料SNS・速報フィードを取得
        await refreshSNSFeed()
    }

    private func refreshMapData() {
        let queryResult = dataStore.queryRecords(in: currentBoundingBox, filter: filter)
        visibleRecords = queryResult.records
        totalMatchedInBox = queryResult.totalMatchedInBox

        let detectedHotspots = DangerAnalyzer.detectHotspots(from: queryResult.records)
        hotspots = detectedHotspots
        locationManager.updateMonitoredHotspots(detectedHotspots)

        let targetCoord = locationManager.userCoordinate ?? cameraCenter
        let nearbyRecords = dataStore.recordsNear(coordinate: targetCoord, radiusMeters: 500.0, filter: filter)
        dangerAssessment = DangerAnalyzer.evaluate(
            center: targetCoord,
            accidentsInRadius: nearbyRecords,
            allSNSReports: snsReports,
            radiusMeters: 500.0
        )
    }

    private func refreshSNSFeed() async {
        guard !isRefreshingSNS else { return }
        isRefreshingSNS = true
        defer { isRefreshingSNS = false }

        let updated = await snsService.fetchLatestFreeSNSReports(existingReports: snsReports)
        snsReports = updated
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        lastSNSUpdatedText = "\(formatter.string(from: Date())) 更新"
        refreshMapData()
    }

    private func jumpToCoordinate(_ coord: CLLocationCoordinate2D) {
        cameraCenter = coord
        cameraZoom = 14.5
        cameraMoveTrigger += 1
        currentBoundingBox = CoordinateBoundingBox(
            minLatitude: coord.latitude - 0.02,
            maxLatitude: coord.latitude + 0.02,
            minLongitude: coord.longitude - 0.02,
            maxLongitude: coord.longitude + 0.02
        )
        refreshMapData()
    }

    private func colorForDanger(_ level: DangerLevel) -> Color {
        switch level {
        case .safe: return .green
        case .caution: return .yellow
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
