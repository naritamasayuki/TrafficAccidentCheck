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
                    detailRow(
                        label: "当事者A（第一当事者）",
                        value: "\(AccidentCodebook.partyTypeName(for: record.partyACode)) / \(AccidentCodebook.ageGroupName(for: record.ageACode))（\(AccidentCodebook.injuryDegreeName(for: record.injuryACode))）",
                        icon: "car.fill"
                    )
                    detailRow(
                        label: "当事者B（相手方）",
                        value: "\(AccidentCodebook.partyTypeName(for: record.partyBCode)) / \(AccidentCodebook.ageGroupName(for: record.ageBCode))（\(AccidentCodebook.injuryDegreeName(for: record.injuryBCode))）",
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

                if let url = URL(string: report.sourceURL),
                   let scheme = url.scheme?.lowercased(),
                   scheme == "https" || scheme == "http" {
                    Section {
                        Button {
                            openURL(url)
                        } label: {
                            Label("元のSNS投稿・速報ページを開く", systemImage: "safari.fill")
                                .font(.subheadline.bold())
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
    @Binding var isProximityAlertEnabled: Bool
    let onJumpToCoordinate: (CLLocationCoordinate2D, String) -> Void
    let onSimulateHotspotAlert: () -> Void
    @Environment(\.dismiss) private var dismiss

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
                    Picker("発生年", selection: $filter.targetYear) {
                        Text("すべて（2024〜2025年）").tag(UInt16?.none)
                        Text("2025年のみ").tag(UInt16?.some(2025))
                        Text("2024年のみ").tag(UInt16?.some(2024))
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
                }

                Section("事故多発地点の接近通知") {
                    Toggle("事故多発エリア接近時に通知する", isOn: $isProximityAlertEnabled)
                    Button {
                        onSimulateHotspotAlert()
                        dismiss()
                    } label: {
                        Label("現在マップ内の事故多発地点への接近通知をテスト", systemImage: "bell.badge.fill")
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

                Section {
                    Button(role: .destructive) {
                        filter = AccidentFilter()
                    } label: {
                        Label("絞り込み条件をリセット", systemImage: "arrow.counterclockwise")
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
        }
    }
}
