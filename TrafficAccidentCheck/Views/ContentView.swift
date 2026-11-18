import CoreLocation
import SwiftUI

/// メイン画面ビュー。
/// 地図表示、現在地自動追従、現在地周辺の危険度スコアカード、クイックフィルタ、SNS速報更新、事故多発地点の接近警告＆音声アナウンスを統合する。
struct ContentView: View {
    let isGoogleMapsConfigured: Bool

    @StateObject private var locationManager = LocationAndAlertManager()
    @State private var dataStore: AccidentDataStore = AccidentDataStore.emptyStore()
    @State private var dataLoadErrorMessage: String?

    @State private var filter = AccidentFilter.loadSaved()
    @State private var visibleRecords: [AccidentRecord] = []
    @State private var totalMatchedInBox: Int = 0
    @State private var hotspots: [AccidentHotspot] = []

    @State private var snsReports: [SNSAccidentReport] = []
    @State private var isRefreshingSNS = false
    @State private var lastSNSUpdatedText: String = L10n.tr("同梱データ読込済")

    @State private var cameraCenter = LocationAndAlertManager.defaultCoordinate
    @State private var cameraZoom: Float = 17.5
    @State private var cameraMoveTrigger: Int = 0
    @State private var hasCenteredOnInitialUserLocation = false
    @State private var currentBoundingBox = CoordinateBoundingBox(
        minLatitude: LocationAndAlertManager.defaultCoordinate.latitude - 0.00125,
        maxLatitude: LocationAndAlertManager.defaultCoordinate.latitude + 0.00125,
        minLongitude: LocationAndAlertManager.defaultCoordinate.longitude - 0.00125,
        maxLongitude: LocationAndAlertManager.defaultCoordinate.longitude + 0.00125
    )

    @State private var dangerAssessment: AreaDangerAssessment?
    @State private var selectedAccident: AccidentRecord?
    @State private var selectedSNSReport: SNSAccidentReport?
    @State private var isShowingFilterSheet = false
    @State private var isShowingBugReportSheet = false
    @State private var isShowingDangerDetail = false

    private let snsService = SNSAccidentService()

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 8) {
                topDangerBar
                quickControlBar

                #if DEBUG
                if !isGoogleMapsConfigured {
                    apiKeyNoticeBanner
                }
                #endif

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
            .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AdBannerView()
        }
        .sheet(item: $selectedAccident) { record in
            AccidentDetailSheet(record: record)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedSNSReport) { report in
            SNSReportDetailSheet(
                report: report,
                onHideReport: {
                    filter.hiddenSNSReportIDs.insert(report.id)
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isShowingFilterSheet) {
            FilterSheet(
                filter: $filter,
                isFollowingUser: $locationManager.isFollowingUser,
                isProximityAlertEnabled: $locationManager.isProximityAlertEnabled,
                isVoiceAnnouncementEnabled: $locationManager.isVoiceAnnouncementEnabled,
                isBackgroundModeEnabled: $locationManager.isBackgroundModeEnabled,
                latestYear: dataStore.latestYear,
                availableYears: dataStore.availableYears,
                onJumpToCoordinate: { coord, _ in
                    locationManager.isFollowingUser = false
                    jumpToCoordinate(coord)
                },
                onSimulateHotspotAlert: {
                    let targetSpot = hotspots.first ?? AccidentHotspot(
                        id: "hotspot-demo",
                        coordinate: locationManager.userCoordinate ?? cameraCenter,
                        accidentCount: 6,
                        fatalCount: 1,
                        dominantType: "車両相互（衝突・追突等）"
                    )
                    locationManager.simulateApproach(to: targetSpot)
                },
                onOpenBugReport: {
                    isShowingBugReportSheet = true
                }
            )
        }
        .sheet(isPresented: $isShowingBugReportSheet) {
            BugReportSheetView(filter: filter, isGoogleMapsConfigured: isGoogleMapsConfigured)
        }
        .onChange(of: filter) { _, newFilter in
            newFilter.save()
            refreshMapData()
        }
        .onChange(of: locationManager.locationUpdateCount) { _, _ in
            guard let userCoord = locationManager.userCoordinate else { return }
            if !hasCenteredOnInitialUserLocation || locationManager.isFollowingUser {
                hasCenteredOnInitialUserLocation = true
                followUserCoordinate(userCoord)
            } else {
                refreshMapData()
            }
        }
        .task {
            await initializeAppData()
        }
    }

    @ViewBuilder
    private var mapLayer: some View {
        let activeSNS = filter.showSNSReports
            ? snsReports.filter { !filter.hiddenSNSReportIDs.contains($0.id) }
            : []
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
                onSelectAccident: { selectedAccident = $0 },
                onSelectSNSReport: { selectedSNSReport = $0 }
            )
        } else {
            FallbackMapKitView(
                records: visibleRecords,
                snsReports: activeSNS,
                hotspots: hotspots,
                displayMode: filter.displayMode,
                userCoordinate: locationManager.userCoordinate,
                cameraCenter: $cameraCenter,
                cameraMoveTrigger: cameraMoveTrigger,
                onRegionChanged: { box, center, zoom in
                    currentBoundingBox = box
                    cameraCenter = center
                    cameraZoom = zoom
                    refreshMapData()
                },
                onSelectAccident: { selectedAccident = $0 },
                onSelectSNSReport: { selectedSNSReport = $0 }
            )
        }
    }
}

// MARK: - ContentView Subviews & Logic

extension ContentView {
    private var topDangerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let assessment = dangerAssessment {
                    Image(systemName: assessment.level.symbolName)
                        .font(.title2)
                        .foregroundStyle(colorForDanger(assessment.level))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            let radiusInt = Int(assessment.radiusMeters)
                            let radiusText = radiusInt >= 1000 ? "\(radiusInt / 1000)km" : "\(radiusInt)m"
                            Text("周辺\(radiusText)危険度: \(assessment.level.localizedName)")
                                .font(.subheadline.bold())
                            Text("(\(assessment.score)/100)")
                                .font(.caption.monospacedDigit().bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(colorForDanger(assessment.level).opacity(0.18), in: Capsule())
                        }
                        let nightPct = Int((assessment.nightAccidentRatio * 100).rounded())
                        Text("人身事故 \(assessment.totalAccidents)件（死亡 \(assessment.fatalAccidents)件 / 夜間 \(nightPct)%）")
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
                pillButton(
                    title: locationManager.isFollowingUser ? "現在地追従中" : "現在地へ移動",
                    icon: locationManager.isFollowingUser ? "location.fill" : "location",
                    activeColor: locationManager.isFollowingUser ? .blue : nil
                ) {
                    locationManager.isFollowingUser.toggle()
                    if locationManager.isFollowingUser {
                        if let coord = locationManager.userCoordinate {
                            followUserCoordinate(coord)
                        } else {
                            locationManager.requestPermissionsAndStart()
                        }
                    }
                }

                pillButton(
                    title: locationManager.isVoiceAnnouncementEnabled ? "音声案内ON" : "音声案内OFF",
                    icon: locationManager.isVoiceAnnouncementEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    activeColor: locationManager.isVoiceAnnouncementEnabled ? .teal : nil
                ) {
                    locationManager.isVoiceAnnouncementEnabled.toggle()
                }

                pillButton(
                    title: locationManager.isBackgroundModeEnabled ? "バックグラウンドON" : "バックグラウンドOFF",
                    icon: locationManager.isBackgroundModeEnabled ? "moon.stars.fill" : "moon.stars",
                    activeColor: locationManager.isBackgroundModeEnabled ? .indigo : nil
                ) {
                    locationManager.isBackgroundModeEnabled.toggle()
                }

                pillButton(
                    title: filter.hasActiveCriteria ? "絞り込み中" : "絞り込み・都市選択",
                    icon: "slider.horizontal.3",
                    activeColor: filter.hasActiveCriteria ? .accentColor : nil
                ) {
                    isShowingFilterSheet = true
                }

                pillButton(
                    title: filter.displayMode == .cluster ? "ヒートマップへ切替" : "ピン表示へ切替",
                    icon: filter.displayMode == .cluster ? "flame.fill" : "mappin.and.ellipse",
                    activeColor: nil
                ) {
                    filter.displayMode = (filter.displayMode == .cluster) ? .heatmap : .cluster
                }

                pillButton(
                    title: "死亡事故のみ",
                    icon: "xmark.octagon.fill",
                    activeColor: filter.severity == .fatalOnly ? .red : nil
                ) {
                    filter.severity = (filter.severity == .fatalOnly) ? .all : .fatalOnly
                }

                pillButton(
                    title: L10n.format("SNS速報(未確認): %d件", snsReports.count),
                    icon: filter.showSNSReports ? "checkmark.circle.fill" : "circle",
                    activeColor: filter.showSNSReports ? .purple : nil
                ) { filter.showSNSReports.toggle() }

                pillButton(
                    title: isRefreshingSNS ? "更新中..." : "SNS更新",
                    icon: "arrow.clockwise",
                    activeColor: nil
                ) {
                    guard !isRefreshingSNS else { return }
                    Task { await refreshSNSFeed() }
                }

                pillButton(title: "バグ報告", icon: "ladybug.fill", activeColor: nil) {
                    isShowingBugReportSheet = true
                }
            }
        }
    }

    private func pillButton(title: String, icon: String, activeColor: Color?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(LocalizedStringKey(title), systemImage: icon)
                .font(.caption.bold())
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(activeColor ?? Color(.secondarySystemBackground))
                .foregroundStyle(activeColor != nil ? .white : .primary)
                .clipShape(Capsule())
        }
    }

    private var apiKeyNoticeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "map.fill")
                .foregroundStyle(.orange)
            Text("開発用表示: Config/Secrets.xcconfig に Google Maps APIキーを設定すると SDK 描画に切り替わります")
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
            Image(systemName: "speaker.wave.3.fill")
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                legendToggleChip(
                    label: "死亡",
                    color: .red,
                    isActive: filter.showFatalAccidents
                ) {
                    filter.toggleVisibility(for: .fatal)
                }
                legendToggleChip(
                    label: "複数負傷",
                    color: .orange,
                    isActive: filter.showMultipleInjuryAccidents
                ) {
                    filter.toggleVisibility(for: .multipleInjury)
                }
                legendToggleChip(
                    label: "負傷(1名)",
                    color: .yellow,
                    isActive: filter.showSingleInjuryAccidents
                ) {
                    filter.toggleVisibility(for: .singleInjury)
                }
                legendToggleChip(
                    label: "SNS",
                    color: .purple,
                    isActive: filter.showSNSReports
                ) {
                    filter.showSNSReports.toggle()
                }
            }

            HStack {
                Text("タップで表示切替")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("表示 \(visibleRecords.count)/\(totalMatchedInBox)件")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    private func legendToggleChip(
        label: String,
        color: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(isActive ? color : Color.gray.opacity(0.35))
                    .overlay(Circle().stroke(color, lineWidth: isActive ? 0 : 1.5))
                    .frame(width: 12, height: 12)
                Text(LocalizedStringKey(label))
                    .font(.footnote.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .strikethrough(!isActive)
                    .foregroundStyle(isActive ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .background(
                isActive ? color.opacity(0.18) : Color.secondary.opacity(0.08),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? color.opacity(0.65) : Color.gray.opacity(0.3), lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.format("%@の表示切り替え", L10n.tr(label)))
        .accessibilityValue(L10n.tr(isActive ? "表示中" : "非表示"))
    }

    private func initializeAppData() async {
        locationManager.requestPermissionsAndStart()

        do {
            let store = try AccidentDataStore()
            self.dataStore = store
        } catch {
            self.dataLoadErrorMessage = error.localizedDescription
        }

        self.snsReports = snsService.loadBundledReports()

        if let userCoord = locationManager.userCoordinate {
            hasCenteredOnInitialUserLocation = true
            followUserCoordinate(userCoord)
        } else {
            refreshMapData()
        }

        await refreshSNSFeed()
    }

    private func refreshMapData() {
        let queryResult = dataStore.queryRecords(in: currentBoundingBox, filter: filter)
        visibleRecords = queryResult.records
        totalMatchedInBox = queryResult.totalMatchedInBox

        let targetCoord = locationManager.userCoordinate ?? cameraCenter
        let radius = filter.diagnosisRadius.meters
        let nearbyRecords = dataStore.recordsNear(coordinate: targetCoord, radiusMeters: radius, filter: filter)
        let hotspotSource = nearbyRecords.isEmpty ? queryResult.records : (queryResult.records + nearbyRecords)
        let detectedHotspots = DangerAnalyzer.detectHotspots(
            from: hotspotSource,
            minimumCount: 5,
            targetYear: dataStore.latestYear
        )
        hotspots = detectedHotspots
        locationManager.updateMonitoredHotspots(detectedHotspots)

        dangerAssessment = DangerAnalyzer.evaluate(
            center: targetCoord,
            accidentsInRadius: nearbyRecords,
            allSNSReports: snsReports,
            radiusMeters: radius
        )
    }

    private func refreshSNSFeed() async {
        guard !isRefreshingSNS else { return }
        isRefreshingSNS = true
        defer { isRefreshingSNS = false }

        snsReports = await snsService.fetchLatestFreeSNSReports(existingReports: snsReports)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        lastSNSUpdatedText = L10n.format("%@ 更新", formatter.string(from: Date()))
        refreshMapData()
    }

    private func followUserCoordinate(_ coord: CLLocationCoordinate2D) {
        cameraCenter = coord
        cameraZoom = 17.5
        cameraMoveTrigger += 1
        currentBoundingBox = CoordinateBoundingBox(
            minLatitude: coord.latitude - 0.00125,
            maxLatitude: coord.latitude + 0.00125,
            minLongitude: coord.longitude - 0.00125,
            maxLongitude: coord.longitude + 0.00125
        )
        refreshMapData()
    }

    private func jumpToCoordinate(_ coord: CLLocationCoordinate2D) {
        cameraCenter = coord
        cameraZoom = 17.5
        cameraMoveTrigger += 1
        currentBoundingBox = CoordinateBoundingBox(
            minLatitude: coord.latitude - 0.00125,
            maxLatitude: coord.latitude + 0.00125,
            minLongitude: coord.longitude - 0.00125,
            maxLongitude: coord.longitude + 0.00125
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
