import CoreLocation
import SwiftUI

/// 公式交通事故レコード（警察庁オープンデータ）の詳細表示シート。
struct AccidentDetailSheet: View {
    let record: AccidentRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: record.isFatal ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(record.isFatal ? .red : .orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.summaryTitle)
                                .font(.headline)
                            Text(record.formattedDateTime)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Label("死者数: \(record.deaths)名", systemImage: "person.fill.xmark")
                            .foregroundStyle(record.deaths > 0 ? .red : .secondary)
                        Spacer()
                        Label("負傷者数: \(record.injuries)名", systemImage: "bandage.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.subheadline.bold())
                } header: {
                    Text("事故概要（公式統計データ）")
                }

                Section("発生時の道路・気象状況") {
                    detailRow(
                        label: "都道府県",
                        value: AccidentCodebook.prefectureName(for: record.prefectureCode),
                        icon: "mappin.and.ellipse"
                    )
                    detailRow(
                        label: "昼夜区分",
                        value: AccidentCodebook.dayNightName(for: record.dayNightCode),
                        icon: record.isNighttime ? "moon.stars.fill" : "sun.max.fill"
                    )
                    detailRow(
                        label: "天候",
                        value: AccidentCodebook.weatherName(for: record.weatherCode),
                        icon: AccidentCodebook.weatherSymbol(for: record.weatherCode)
                    )
                    detailRow(
                        label: "路面状態",
                        value: AccidentCodebook.roadSurfaceName(for: record.roadSurfaceCode),
                        icon: "road.lanes"
                    )
                    detailRow(
                        label: "道路形状",
                        value: AccidentCodebook.roadShapeName(for: record.roadShapeCode),
                        icon: "arrow.triangle.branch"
                    )
                    detailRow(
                        label: "信号機",
                        value: AccidentCodebook.signalName(for: record.signalCode),
                        icon: "light.beacon.max.fill"
                    )
                }

                Section("当事者情報") {
                    let partyAInfo = "\(AccidentCodebook.partyTypeName(for: record.partyACode)) / "
                        + "\(AccidentCodebook.ageGroupName(for: record.ageACode))"
                        + "（\(AccidentCodebook.injuryDegreeName(for: record.injuryACode))）"
                    detailRow(
                        label: "当事者A（第一当事者）",
                        value: partyAInfo,
                        icon: "car.fill"
                    )
                    let partyBInfo = "\(AccidentCodebook.partyTypeName(for: record.partyBCode)) / "
                        + "\(AccidentCodebook.ageGroupName(for: record.ageBCode))"
                        + "（\(AccidentCodebook.injuryDegreeName(for: record.injuryBCode))）"
                    detailRow(
                        label: "当事者B（相手方）",
                        value: partyBInfo,
                        icon: "person.2.fill"
                    )
                }

                Section {
                    ForEach(SafetyGoodsRecommendation.recommended(for: record)) { item in
                        if let url = item.amazonSearchURL() {
                            SafetyGoodsLinkRow(item: item, url: url)
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text("事故予防のおすすめ交通安全グッズ")
                        Text("PR")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                } footer: {
                    Text("※PR：Amazonのアソシエイトとして、当アプリは適格販売により収入を得ています。")
                }

                Section("位置・出典情報") {
                    detailRow(
                        label: "緯度・経度",
                        value: String(format: "北緯 %.5f°, 東経 %.5f°", record.latitude, record.longitude),
                        icon: "location.fill"
                    )
                    detailRow(
                        label: "データ出典",
                        value: L10n.format("警察庁 交通事故統計オープンデータ（%d年本票）", Int(record.year)),
                        icon: "checkmark.seal.fill"
                    )
                    if let npaURL = URL(
                        string: "https://www.npa.go.jp/publications/statistics/koutsuu/opendata/index_opendata.html"
                    ) {
                        Link(destination: npaURL) {
                            Label("警察庁 オープンデータ公開ページを開く", systemImage: "link")
                                .font(.footnote.bold())
                        }
                    }
                    Text("※本アプリは警察庁が公開しているオープンデータを利用した独自の民間アプリであり、警察庁・政府機関・自治体等を代表するものではなく提携関係もありません。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("事故詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func detailRow(label: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

/// SNSおよびニュース速報（未確認情報）の詳細表示シート。
/// ユーザー要望に基づき、「出典: SNS（未確認情報）」を最上部に明確に表示する。
struct SNSReportDetailSheet: View {
    let report: SNSAccidentReport
    var onHideReport: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.bubble.fill")
                                .foregroundStyle(.white)
                            Text(report.sourceAttributionBadgeText)
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.purple, in: Capsule())

                        Text("この情報はSNSまたは速報フィードから自動抽出された未確認情報です。警察庁の公式統計データではありません。デマ・誤報や位置の誤差が含まれる可能性があります。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("抽出された投稿・速報内容") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(report.title)
                            .font(.headline)
                        if report.body != report.title {
                            Text(report.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    LabeledContent("推定場所", value: report.extractedLocation)
                    LabeledContent("推定分類", value: report.category)
                    LabeledContent("情報ソース", value: report.sourceName)
                    LabeledContent("取得・投稿日時", value: report.postedAt)
                    LabeledContent(
                        "推定座標",
                        value: String(format: "%.4f, %.4f", report.latitude, report.longitude)
                    )
                }

                Section {
                    if let url = URL(string: report.sourceURL),
                       let scheme = url.scheme?.lowercased(),
                       scheme == "https" || scheme == "http" {
                        Button {
                            openURL(url)
                        } label: {
                            Label("元のSNS投稿・速報ページを開く", systemImage: "safari.fill")
                                .font(.subheadline.bold())
                        }
                    }

                    if let onHideReport {
                        Button(role: .destructive) {
                            onHideReport()
                            dismiss()
                        } label: {
                            Label("この未確認速報を誤報・不適切として非表示にする", systemImage: "eye.slash.fill")
                                .font(.subheadline)
                        }
                    }
                }
            }
            .navigationTitle("SNS・速報詳細（未確認）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

/// 絞り込み・表示設定・都市ジャンプシート。
struct FilterSheet: View {
    @Binding var filter: AccidentFilter
    @Binding var isFollowingUser: Bool
    @Binding var isProximityAlertEnabled: Bool
    @Binding var isVoiceAnnouncementEnabled: Bool
    @Binding var isBackgroundModeEnabled: Bool
    var latestYear: UInt16 = AccidentFilter.defaultReferenceYear
    var availableYears: [UInt16] = []
    let onJumpToCoordinate: (CLLocationCoordinate2D, String) -> Void
    let onSimulateHotspotAlert: () -> Void
    var onOpenBugReport: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingFirstResetAlert = false
    @State private var isShowingSecondResetAlert = false

    private let majorCities: [(name: String, coord: CLLocationCoordinate2D)] = [
        ("東京（新宿・都心）", CLLocationCoordinate2D(latitude: 35.6895, longitude: 139.6917)),
        ("東京（東京駅・丸の内）", CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)),
        ("大阪（梅田・キタ）", CLLocationCoordinate2D(latitude: 34.7024, longitude: 135.4959)),
        ("愛知（名古屋・栄）", CLLocationCoordinate2D(latitude: 35.1681, longitude: 136.9066)),
        ("北海道（札幌・大通）", CLLocationCoordinate2D(latitude: 43.0618, longitude: 141.3545)),
        ("福岡（博多駅前）", CLLocationCoordinate2D(latitude: 33.5902, longitude: 130.4207))
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("現在地追従・音声アナウンス・接近通知") {
                    Toggle("移動に合わせてマップを現在地に追従する", isOn: $isFollowingUser)
                    Toggle("事故多発エリア接近時に通知する", isOn: $isProximityAlertEnabled)
                    Toggle("事故現場接近時に音声アナウンスで警告する", isOn: $isVoiceAnnouncementEnabled)
                    Toggle("バックグラウンドモード（画面消灯中も案内を継続）", isOn: $isBackgroundModeEnabled)
                    if isBackgroundModeEnabled {
                        Text("アプリを閉じた状態や画面消灯中も現在地を監視し、多発地点への接近を音声と通知でお知らせします（電池消費が増える場合があります）。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        onSimulateHotspotAlert()
                        dismiss()
                    } label: {
                        Label("音声アナウンス・接近警告のサンプル再生（音量確認）", systemImage: "speaker.wave.3.fill")
                    }
                }

                Section("マップ表示モード") {
                    Picker("表示形式", selection: $filter.displayMode) {
                        ForEach(MapDisplayMode.allCases) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle(isOn: $filter.showSNSReports) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("最新データ（出典: SNS・未確認）を表示")
                            Text("紫色のピンでSNS・ニュース速報からの抽出地点を重ねて表示します")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("事故の程度（色分け）ごとの表示") {
                    Toggle(isOn: $filter.showFatalAccidents) {
                        HStack(spacing: 8) {
                            Circle().fill(Color.red).frame(width: 12, height: 12)
                            Text("死亡事故（赤）")
                        }
                    }
                    Toggle(isOn: $filter.showMultipleInjuryAccidents) {
                        HStack(spacing: 8) {
                            Circle().fill(Color.orange).frame(width: 12, height: 12)
                            Text("複数負傷・2名以上（橙）")
                        }
                    }
                    Toggle(isOn: $filter.showSingleInjuryAccidents) {
                        HStack(spacing: 8) {
                            Circle().fill(Color.yellow).frame(width: 12, height: 12)
                            Text("負傷・1名（黄）")
                        }
                    }
                }

                Section("公式オープンデータの絞り込み") {
                    Picker("発生年", selection: $filter.yearFilter) {
                        Text(YearFilter.recentThreeYears.displayText(latestYear: latestYear))
                            .tag(YearFilter.recentThreeYears)
                        Text(YearFilter.all.displayText(latestYear: latestYear))
                            .tag(YearFilter.all)
                        ForEach(availableYears, id: \.self) { year in
                            Text(L10n.format("%d年のみ", Int(year))).tag(YearFilter.specific(year))
                        }
                    }

                    Picker("事故内容（重大度）", selection: $filter.severity) {
                        ForEach(SeverityFilter.allCases) { item in
                            Text(item.localizedName).tag(item)
                        }
                    }

                    Picker("発生時間帯（昼夜）", selection: $filter.timeOfDay) {
                        ForEach(TimeOfDayFilter.allCases) { item in
                            Text(item.localizedName).tag(item)
                        }
                    }

                    Picker("天候", selection: $filter.weather) {
                        ForEach(WeatherFilter.allCases) { item in
                            Text(item.localizedName).tag(item)
                        }
                    }

                    Picker("事故類型", selection: $filter.accidentType) {
                        ForEach(AccidentTypeFilter.allCases) { item in
                            Text(item.localizedName).tag(item)
                        }
                    }

                    Picker("周辺危険度の診断範囲", selection: $filter.diagnosisRadius) {
                        ForEach(DiagnosisRadiusFilter.allCases) { item in
                            Text(item.displayText).tag(item)
                        }
                    }
                }

                Section("主要都市へジャンプ") {
                    ForEach(majorCities, id: \.name) { city in
                        Button {
                            onJumpToCoordinate(city.coord, L10n.tr(city.name))
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "location.magnifyingglass")
                                Text(LocalizedStringKey(city.name))
                                Spacer()
                            }
                        }
                    }
                }

                Section {
                    ForEach(SafetyGoodsRecommendation.allItems) { item in
                        if let url = item.amazonSearchURL() {
                            SafetyGoodsLinkRow(item: item, url: url)
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text("おすすめ交通安全グッズ（Amazon）")
                        Text("PR")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                } footer: {
                    Text("※PR：Amazonのアソシエイトとして、当アプリは適格販売により収入を得ています。")
                }

                Section("サポート・設定リセット") {
                    if let onOpenBugReport {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                onOpenBugReport()
                            }
                        } label: {
                            Label("バグ・不具合・改善要望を報告する", systemImage: "ladybug.fill")
                        }
                    }

                    Button(role: .destructive) {
                        isShowingFirstResetAlert = true
                    } label: {
                        Label("絞り込み条件をリセット", systemImage: "arrow.counterclockwise")
                    }
                }

                Section("安全運転に関するご注意・データ出典・免責事項") {
                    Text("⚠️ 運転中のスマートフォンの画面注視・操作は大変危険ですので絶対におやめください。走行中は音声アナウンス機能をご活用いただき、画面操作は安全な場所に停車してから行ってください。")
                        .font(.caption)
                        .foregroundStyle(.primary)

                    Text("【公的機関との非提携に関する明記】\n本アプリは警察庁および国土地理院が公開しているオープンデータを利用した独自の民間アプリケーションであり、警察庁・政府機関・自治体等を代表するものではなく、提携・承認関係もありません。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let npaURL = URL(
                        string: "https://www.npa.go.jp/publications/statistics/koutsuu/opendata/index_opendata.html"
                    ) {
                        Link(destination: npaURL) {
                            Label("出典1: 警察庁 交通事故統計情報のオープンデータ", systemImage: "link")
                                .font(.caption)
                        }
                    }

                    if let gsiURL = URL(string: "https://www.gsi.go.jp/") {
                        Link(destination: gsiURL) {
                            Label("出典2: 国土地理院 住所検索API（位置座標変換）", systemImage: "link")
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("絞り込み・設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                }
            }
            .alert("絞り込み条件をリセットしますか？", isPresented: $isShowingFirstResetAlert) {
                Button("いいえ", role: .cancel) {}
                Button("はい", role: .destructive) {
                    isShowingSecondResetAlert = true
                }
            } message: {
                Text("現在設定されている絞り込み条件や表示モードが初期状態に戻ります。")
            }
            .alert("最終確認：本当にリセットしてよろしいですか？", isPresented: $isShowingSecondResetAlert) {
                Button("いいえ", role: .cancel) {}
                Button("リセットする", role: .destructive) {
                    filter = AccidentFilter()
                    filter.save()
                }
            } message: {
                Text("この操作を実行すると、保存されている絞り込み設定が初期化されます。")
            }
        }
    }
}

/// Amazon アソシエイトの交通安全グッズリンク行（PR 表記付き）。
private struct SafetyGoodsLinkRow: View {
    let item: SafetyGoodsRecommendation
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.body)
                    .foregroundStyle(.orange)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(item.titleKey))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(LocalizedStringKey(item.subtitleKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }
}

/// 周辺安全診断結果をSNSシェア用の1枚カード画像として生成・共有するシート。
struct SafetyReportShareSheet: View {
    let locationTitle: String
    let assessment: AreaDangerAssessment
    let periodLabel: String

    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    shareCardContent
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                    if let image = renderedImage {
                        let swiftUIImage = Image(uiImage: image)
                        ShareLink(
                            item: swiftUIImage,
                            preview: SharePreview(
                                L10n.format("交通安全診断: %@", locationTitle),
                                image: swiftUIImage
                            )
                        ) {
                            Label("この診断カードを画像でシェアする", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        ProgressView("シェア画像を生成中...")
                    }

                    Text("※ LINE・X・Instagram やご家族への通学路・引っ越し先の共有にご活用ください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .navigationTitle("診断カードをシェア")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task {
                renderShareImage()
            }
        }
    }

    private var accentColor: Color {
        switch assessment.level {
        case .safe: return .green
        case .caution: return .orange
        case .warning: return .red
        case .critical: return .purple
        }
    }

    private var radiusText: String {
        let r = Int(assessment.radiusMeters)
        return r >= 1000 ? "\(r / 1000)km" : "\(r)m"
    }

    private var shareCardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("事故マップ - 交通安全診断", systemImage: "shield.lefthalf.filled")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text(periodLabel)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.2), in: Capsule())
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(locationTitle)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(L10n.format("半径%@以内の危険度診断", radiusText))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("危険度ランク")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(assessment.level.localizedName)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("リスクスコア")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                    Text("\(assessment.score) / 100")
                        .font(.title2.monospacedDigit().bold())
                        .foregroundStyle(.white)
                }
            }
            .padding(12)
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
                statTile(title: "人身事故", value: "\(assessment.totalAccidents)")
                statTile(title: "死亡事故", value: "\(assessment.fatalAccidents)")
                statTile(title: "夜間割合", value: "\(Int((assessment.nightAccidentRatio * 100).rounded()))%")
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(assessment.currentTimeSlotLabel, systemImage: "clock.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                Text(assessment.currentTimeSlotAdvice)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("出典: 警察庁 交通事故統計オープンデータ")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(18)
        .frame(width: 340)
        .background(
            LinearGradient(
                colors: [accentColor.opacity(0.92), Color.black.opacity(0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(LocalizedStringKey(title))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
            Text(value)
                .font(.headline.monospacedDigit().bold())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @MainActor
    private func renderShareImage() {
        let renderer = ImageRenderer(content: shareCardContent)
        renderer.scale = 3.0
        renderedImage = renderer.uiImage
    }
}

/// お気に入り保存した地点を危険度スコア順に比較・ジャンプできるシート。
struct SavedLocationsSheet: View {
    @Binding var savedLocations: [SavedLocationItem]
    let onSelectLocation: (SavedLocationItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingFirstClearAlert = false
    @State private var isShowingSecondClearAlert = false

    private var sortedLocations: [SavedLocationItem] {
        savedLocations.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.savedAt > rhs.savedAt
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if savedLocations.isEmpty {
                    ContentUnavailableView(
                        "お気に入り地点はまだありません",
                        systemImage: "star.slash",
                        description: Text("地図上部の危険度バーを開き「お気に入り保存」を押すと、自宅や通学路・引っ越し候補の危険度を一覧で比較できます。")
                    )
                } else {
                    List {
                        Section {
                            ForEach(sortedLocations) { item in
                                Button {
                                    onSelectLocation(item)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: item.dangerLevel.symbolName)
                                            .font(.title3)
                                            .foregroundStyle(colorFor(item.dangerLevel))

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.name)
                                                .font(.subheadline.bold())
                                                .foregroundStyle(.primary)
                                            let r = Int(item.radiusMeters)
                                            let radiusText = r >= 1000 ? "\(r / 1000)km" : "\(r)m"
                                            Text("半径\(radiusText)・人身\(item.totalAccidents)件（死亡\(item.fatalAccidents)件）")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("\(item.score)/100")
                                                .font(.subheadline.monospacedDigit().bold())
                                                .foregroundStyle(colorFor(item.dangerLevel))
                                            Text(item.dangerLevel.localizedName)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .onDelete { offsets in
                                let idsToDelete = offsets.map { sortedLocations[$0].id }
                                savedLocations.removeAll { idsToDelete.contains($0.id) }
                                SavedLocationStore.save(savedLocations)
                            }
                        } header: {
                            Text("危険度スコアが高い順に表示（タップで地図へ移動）")
                        }

                        Section {
                            Button(role: .destructive) {
                                isShowingFirstClearAlert = true
                            } label: {
                                Label("お気に入り地点をすべて削除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("お気に入り地点・危険度比較")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("お気に入り地点をすべて削除しますか？", isPresented: $isShowingFirstClearAlert) {
                Button("いいえ", role: .cancel) {}
                Button("はい", role: .destructive) {
                    isShowingSecondClearAlert = true
                }
            } message: {
                Text("保存されているすべての地点データが削除されます。")
            }
            .alert("最終確認：本当にすべて削除しますか？", isPresented: $isShowingSecondClearAlert) {
                Button("いいえ", role: .cancel) {}
                Button("削除する", role: .destructive) {
                    savedLocations.removeAll()
                    SavedLocationStore.save(savedLocations)
                }
            } message: {
                Text("削除したお気に入り地点は元に戻せません。")
            }
        }
    }

    private func colorFor(_ level: DangerLevel) -> Color {
        switch level {
        case .safe: return .green
        case .caution: return .orange
        case .warning: return .red
        case .critical: return .purple
        }
    }
}
