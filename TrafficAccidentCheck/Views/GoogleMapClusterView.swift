import CoreLocation
import MapKit
import SwiftUI

/// Apple 標準 MapKit を用いて事故ピン・ヒートマップ・ホットスポット・SNS速報を表示するメインマップビュー。
struct FallbackMapKitView: View {
    let records: [AccidentRecord]
    let snsReports: [SNSAccidentReport]
    let hotspots: [AccidentHotspot]
    let displayMode: MapDisplayMode
    let userCoordinate: CLLocationCoordinate2D?
    @Binding var cameraCenter: CLLocationCoordinate2D
    let cameraMoveTrigger: Int
    let onRegionChanged: (CoordinateBoundingBox, CLLocationCoordinate2D, Float) -> Void
    let onSelectAccident: (AccidentRecord) -> Void
    let onSelectSNSReport: (SNSAccidentReport) -> Void
    var onUserInteraction: (() -> Void)? = nil

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: LocationAndAlertManager.defaultCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.0025, longitudeDelta: 0.0025)
        )
    )
    @State private var currentSpan = MKCoordinateSpan(latitudeDelta: 0.0025, longitudeDelta: 0.0025)
    @State private var isProgrammaticMove = false

    var body: some View {
        Map(position: $position) {
            UserAnnotation()

            // ホットスポット（事故多発エリア）を二重リング＋警告バッジで強調表示
            ForEach(hotspots.prefix(10)) { spot in
                let spotColor: Color = spot.fatalCount > 0 ? Color(red: 0.85, green: 0.05, blue: 0.12) : .orange
                MapCircle(center: spot.coordinate, radius: 150)
                    .foregroundStyle(spotColor.opacity(0.24))
                    .stroke(spotColor, lineWidth: 3.0)
                MapCircle(center: spot.coordinate, radius: 65)
                    .foregroundStyle(spotColor.opacity(0.32))
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                Annotation("多発 \(spot.accidentCount)件", coordinate: spot.coordinate) {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2.bold())
                        Text("多発 \(spot.accidentCount)件")
                            .font(.caption2.weight(.heavy))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(spotColor, in: Capsule())
                    .overlay(Capsule().stroke(Color.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                }
            }

            // 公式事故データ（ピン表示またはヒートマップサークル）
            ForEach(records.prefix(displayMode == .heatmap ? 450 : 300)) { rec in
                let markerColor: Color = {
                    switch rec.severityLevel {
                    case .fatal: return .red
                    case .multipleInjury: return .orange
                    case .singleInjury: return .yellow
                    }
                }()
                if displayMode == .heatmap {
                    let radius: Double = rec.severityLevel == .fatal ? 120 : (rec.severityLevel == .multipleInjury ? 85 : 60)
                    let opacity: Double = rec.severityLevel == .fatal ? 0.35 : (rec.severityLevel == .multipleInjury ? 0.24 : 0.18)
                    MapCircle(center: rec.coordinate, radius: radius)
                        .foregroundStyle(markerColor.opacity(opacity))
                } else {
                    Annotation(rec.severityLevel.shortLabel, coordinate: rec.coordinate) {
                        Button {
                            onSelectAccident(rec)
                        } label: {
                            let symbolName: String = {
                                switch rec.severityLevel {
                                case .fatal: return "xmark.octagon.fill"
                                case .multipleInjury: return "exclamationmark.triangle.fill"
                                case .singleInjury: return "exclamationmark.circle.fill"
                                }
                            }()
                            let fgColor: Color = rec.severityLevel == .singleInjury ? .black : .white
                            Image(systemName: symbolName)
                                .font(.system(size: rec.isFatal ? 18 : 13, weight: .bold))
                                .foregroundStyle(fgColor)
                                .padding(rec.isFatal ? 5 : 3.5)
                                .background(markerColor, in: Circle())
                                .shadow(radius: 2)
                        }
                    }
                }
            }

            // SNS速報（未確認情報）マーカー
            ForEach(snsReports) { report in
                Annotation("SNS(未確認): \(report.extractedLocation)", coordinate: report.coordinate) {
                    Button {
                        onSelectSNSReport(report)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                                .font(.caption2)
                            Text("SNS")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.purple, in: Capsule())
                        .overlay(Capsule().stroke(Color.white, lineWidth: 1.5))
                        .shadow(radius: 3)
                    }
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onChange(of: cameraMoveTrigger) { _, _ in
            isProgrammaticMove = true
            withAnimation {
                position = .region(
                    MKCoordinateRegion(
                        center: cameraCenter,
                        span: currentSpan
                    )
                )
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            let region = context.region
            currentSpan = region.span
            if isProgrammaticMove {
                isProgrammaticMove = false
            } else {
                onUserInteraction?()
            }
            let box = CoordinateBoundingBox(
                minLatitude: region.center.latitude - region.span.latitudeDelta / 2.0,
                maxLatitude: region.center.latitude + region.span.latitudeDelta / 2.0,
                minLongitude: region.center.longitude - region.span.longitudeDelta / 2.0,
                maxLongitude: region.center.longitude + region.span.longitudeDelta / 2.0
            )
            let approxZoom = Float(max(4.0, min(20.0, log2(360.0 / max(0.0005, region.span.longitudeDelta)))))
            onRegionChanged(box, region.center, approxZoom)
        }
    }
}
