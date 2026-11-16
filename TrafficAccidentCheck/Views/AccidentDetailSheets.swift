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

                Section("位置・出典情報") {
                    detailRow(
                        label: "緯度・経度",
                        value: String(format: "北緯 %.5f°, 東経 %.5f°", record.latitude, record.longitude),
                        icon: "location.fill"
                    )
                    detailRow(
                        label: "データ出典",
                        value: "警察庁 交通事故統計オープンデータ（\(record.year)年本票）",
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
                            Text(mode.rawValue).tag(mode)
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

                Section("公式オープンデータの絞り込み") {
                    Picker("発生年", selection: $filter.yearFilter) {
                        Text(YearFilter.recentThreeYears.displayText(latestYear: latestYear))
                            .tag(YearFilter.recentThreeYears)
                        Text(YearFilter.all.displayText(latestYear: latestYear))
                            .tag(YearFilter.all)
                        ForEach(availableYears, id: \.self) { year in
                            Text("\(year)年のみ").tag(YearFilter.specific(year))
                        }
                    }

                    Picker("事故内容（重大度）", selection: $filter.severity) {
                        ForEach(SeverityFilter.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }

                    Picker("発生時間帯（昼夜）", selection: $filter.timeOfDay) {
                        ForEach(TimeOfDayFilter.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }

                    Picker("天候", selection: $filter.weather) {
                        ForEach(WeatherFilter.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }

                    Picker("事故類型", selection: $filter.accidentType) {
                        ForEach(AccidentTypeFilter.allCases) { item in
                            Text(item.rawValue).tag(item)
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
                            onJumpToCoordinate(city.coord, city.name)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "location.magnifyingglass")
                                Text(city.name)
                                Spacer()
                            }
                        }
                    }
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
