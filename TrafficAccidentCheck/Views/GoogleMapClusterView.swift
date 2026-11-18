import CoreLocation
import GoogleMaps
import GoogleMapsUtils
import MapKit
import SwiftUI
import UIKit

/// GoogleMapsUtils のクラスタリング対象となる事故アイテム。
final class AccidentClusterItem: NSObject, GMUClusterItem {
    let position: CLLocationCoordinate2D
    let record: AccidentRecord

    init(record: AccidentRecord) {
        self.record = record
        self.position = record.coordinate
        super.init()
    }
}

/// Google Maps SDK (`GMSMapView` + `GMUClusterManager` + `GMUHeatmapTileLayer`) を SwiftUI に統合するビュー。
struct GoogleMapContainerView: UIViewRepresentable {
    let records: [AccidentRecord]
    let snsReports: [SNSAccidentReport]
    let hotspots: [AccidentHotspot]
    let displayMode: MapDisplayMode
    @Binding var cameraCenter: CLLocationCoordinate2D
    @Binding var cameraZoom: Float
    let cameraMoveTrigger: Int
    let onRegionChanged: (CoordinateBoundingBox, CLLocationCoordinate2D, Float) -> Void
    let onSelectAccident: (AccidentRecord) -> Void
    let onSelectSNSReport: (SNSAccidentReport) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition.camera(
            withLatitude: cameraCenter.latitude,
            longitude: cameraCenter.longitude,
            zoom: cameraZoom
        )
        let mapView = GMSMapView(options: options)
        mapView.isMyLocationEnabled = true
        mapView.settings.myLocationButton = true
        mapView.settings.compassButton = true
        mapView.settings.rotateGestures = true
        mapView.settings.zoomGestures = true

        context.coordinator.setupClusterManager(for: mapView)
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateCameraIfNeeded(on: mapView)
        context.coordinator.updateOverlays(
            on: mapView,
            records: records,
            snsReports: snsReports,
            hotspots: hotspots,
            displayMode: displayMode
        )
    }

    final class Coordinator: NSObject, GMSMapViewDelegate, GMUClusterManagerDelegate, GMUClusterRendererDelegate {
        var parent: GoogleMapContainerView
        private var clusterManager: GMUClusterManager?
        private var heatmapLayer: GMUHeatmapTileLayer?
        private var snsMarkers: [GMSMarker] = []
        private var hotspotCircles: [GMSCircle] = []
        private var hotspotMarkers: [GMSMarker] = []
        private var lastRenderedRecordIDs: [Int] = []
        private var lastRenderedSNSIDs: [String] = []
        private var lastDisplayMode: MapDisplayMode?
        private var lastCameraMoveTrigger: Int = 0

        init(parent: GoogleMapContainerView) {
            self.parent = parent
            self.lastCameraMoveTrigger = parent.cameraMoveTrigger
        }

        func setupClusterManager(for mapView: GMSMapView) {
            let buckets: [NSNumber] = [10, 50, 100, 500, 1000]
            let colors: [UIColor] = [
                UIColor.systemOrange,
                UIColor(red: 0.95, green: 0.45, blue: 0.10, alpha: 1.0),
                UIColor.systemRed,
                UIColor(red: 0.75, green: 0.05, blue: 0.15, alpha: 1.0),
                UIColor(red: 0.45, green: 0.0, blue: 0.20, alpha: 1.0)
            ]
            let iconGenerator = GMUDefaultClusterIconGenerator(buckets: buckets, backgroundColors: colors)
            guard let algorithm = GMUNonHierarchicalDistanceBasedAlgorithm(clusterDistancePoints: 75) else {
                AppLogger.map.error("クラスタリングアルゴリズムの初期化に失敗しました。")
                return
            }
            let renderer = GMUDefaultClusterRenderer(mapView: mapView, clusterIconGenerator: iconGenerator)
            renderer.minimumClusterSize = 4
            renderer.maximumClusterZoom = 18
            renderer.delegate = self

            let manager = GMUClusterManager(map: mapView, algorithm: algorithm, renderer: renderer)
            manager.setDelegate(self, mapDelegate: self)
            self.clusterManager = manager

            let heatmap = GMUHeatmapTileLayer()
            heatmap.radius = 35
            heatmap.opacity = 0.75
            heatmap.gradient = GMUGradient(
                colors: [
                    UIColor.systemGreen.withAlphaComponent(0.6),
                    UIColor.systemYellow.withAlphaComponent(0.85),
                    UIColor.systemOrange,
                    UIColor.systemRed
                ],
                startPoints: [0.15, 0.45, 0.75, 1.0],
                colorMapSize: 256
            )
            self.heatmapLayer = heatmap
        }

        func updateCameraIfNeeded(on mapView: GMSMapView) {
            guard parent.cameraMoveTrigger != lastCameraMoveTrigger else { return }
            lastCameraMoveTrigger = parent.cameraMoveTrigger
            let camera = GMSCameraPosition.camera(
                withLatitude: parent.cameraCenter.latitude,
                longitude: parent.cameraCenter.longitude,
                zoom: parent.cameraZoom
            )
            mapView.animate(to: camera)
        }

        func updateOverlays(
            on mapView: GMSMapView,
            records: [AccidentRecord],
            snsReports: [SNSAccidentReport],
            hotspots: [AccidentHotspot],
            displayMode: MapDisplayMode
        ) {
            let recordIDs = records.map(\.id)
            let snsIDs = snsReports.map(\.id)

            if recordIDs != lastRenderedRecordIDs || displayMode != lastDisplayMode {
                lastRenderedRecordIDs = recordIDs
                lastDisplayMode = displayMode

                clusterManager?.clearItems()
                switch displayMode {
                case .cluster:
                    heatmapLayer?.map = nil
                    let items = records.map { AccidentClusterItem(record: $0) }
                    clusterManager?.add(items)
                    clusterManager?.cluster()
                case .heatmap:
                    clusterManager?.cluster()
                    if records.isEmpty {
                        heatmapLayer?.map = nil
                    } else {
                        let weighted = records.map { rec in
                            GMUWeightedLatLng(
                                coordinate: rec.coordinate,
                                intensity: rec.isFatal ? 6.0 : 1.5
                            )
                        }
                        heatmapLayer?.weightedData = weighted
                        heatmapLayer?.map = nil
                        heatmapLayer?.map = mapView
                        heatmapLayer?.clearTileCache()
                    }
                }

                // ホットスポット（事故多発150m圏）を二重リング＋警告バッジで強調表示
                for circle in hotspotCircles { circle.map = nil }
                hotspotCircles.removeAll()
                for marker in hotspotMarkers { marker.map = nil }
                hotspotMarkers.removeAll()

                for spot in hotspots.prefix(10) {
                    let baseColor = spot.fatalCount > 0
                        ? UIColor(red: 0.85, green: 0.05, blue: 0.12, alpha: 1.0)
                        : UIColor(red: 0.95, green: 0.38, blue: 0.02, alpha: 1.0)

                    // 外側警戒リング（150m）
                    let outerCircle = GMSCircle(position: spot.coordinate, radius: 150)
                    outerCircle.fillColor = baseColor.withAlphaComponent(0.22)
                    outerCircle.strokeColor = baseColor.withAlphaComponent(0.95)
                    outerCircle.strokeWidth = 3.0
                    outerCircle.zIndex = 30
                    outerCircle.map = mapView
                    hotspotCircles.append(outerCircle)

                    // 内側コア強調リング（65m）
                    let innerCircle = GMSCircle(position: spot.coordinate, radius: 65)
                    innerCircle.fillColor = baseColor.withAlphaComponent(0.32)
                    innerCircle.strokeColor = UIColor.white.withAlphaComponent(0.9)
                    innerCircle.strokeWidth = 2.0
                    innerCircle.zIndex = 31
                    innerCircle.map = mapView
                    hotspotCircles.append(innerCircle)

                    // 中心の「事故多発」警告バッジマーカー
                    let badgeMarker = GMSMarker(position: spot.coordinate)
                    badgeMarker.title = L10n.format("⚠️ 事故多発ゾーン（%d件）", spot.accidentCount)
                    badgeMarker.snippet = L10n.format("直近1年・半径150m内で%d件発生（うち死亡%d件）", spot.accidentCount, spot.fatalCount)
                    badgeMarker.iconView = Self.makeHotspotBadgeView(for: spot, color: baseColor)
                    badgeMarker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                    badgeMarker.zIndex = 200
                    badgeMarker.map = mapView
                    hotspotMarkers.append(badgeMarker)
                }
            }

            if snsIDs != lastRenderedSNSIDs {
                lastRenderedSNSIDs = snsIDs
                for marker in snsMarkers { marker.map = nil }
                snsMarkers.removeAll()

                for report in snsReports {
                    let marker = GMSMarker(position: report.coordinate)
                    marker.title = L10n.format("【SNS・未確認】%@", report.extractedLocation)
                    marker.snippet = report.title
                    marker.icon = GMSMarker.markerImage(with: .systemPurple)
                    marker.userData = report
                    marker.zIndex = 100
                    marker.map = mapView
                    snsMarkers.append(marker)
                }
            }
        }

        private static func makeHotspotBadgeView(for spot: AccidentHotspot, color: UIColor) -> UIView {
            let label = UILabel()
            label.text = L10n.format("⚠️ 多発 %d件", spot.accidentCount)
            label.font = UIFont.systemFont(ofSize: 11, weight: .heavy)
            label.textColor = .white
            label.textAlignment = .center
            label.sizeToFit()

            let paddingX: CGFloat = 9
            let paddingY: CGFloat = 5
            let container = UIView(frame: CGRect(
                x: 0,
                y: 0,
                width: label.bounds.width + paddingX * 2,
                height: label.bounds.height + paddingY * 2
            ))
            container.backgroundColor = color
            container.layer.cornerRadius = container.bounds.height / 2
            container.layer.borderColor = UIColor.white.cgColor
            container.layer.borderWidth = 2.0
            container.layer.shadowColor = UIColor.black.cgColor
            container.layer.shadowOpacity = 0.35
            container.layer.shadowOffset = CGSize(width: 0, height: 2)
            container.layer.shadowRadius = 3

            label.center = CGPoint(x: container.bounds.midX, y: container.bounds.midY)
            container.addSubview(label)
            return container
        }

        // MARK: - GMUClusterRendererDelegate

        func renderer(_ renderer: GMUClusterRenderer, willRenderMarker marker: GMSMarker) {
            if let item = marker.userData as? AccidentClusterItem {
                let rec = item.record
                marker.title = rec.summaryTitle
                marker.snippet = rec.formattedDateTime
                switch rec.severityLevel {
                case .fatal:
                    marker.icon = GMSMarker.markerImage(with: .systemRed)
                    marker.zIndex = 50
                case .multipleInjury:
                    marker.icon = GMSMarker.markerImage(with: .systemOrange)
                    marker.zIndex = 20
                case .singleInjury:
                    marker.icon = GMSMarker.markerImage(with: .systemYellow)
                    marker.zIndex = 10
                }
            }
        }

        // MARK: - GMUClusterManagerDelegate

        func clusterManager(_ clusterManager: GMUClusterManager, didTap cluster: GMUCluster) -> Bool {
            return false // デフォルトのズームイン動作に委譲
        }

        func clusterManager(_ clusterManager: GMUClusterManager, didTap clusterItem: GMUClusterItem) -> Bool {
            if let item = clusterItem as? AccidentClusterItem {
                parent.onSelectAccident(item.record)
                return true
            }
            return false
        }

        // MARK: - GMSMapViewDelegate

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let report = marker.userData as? SNSAccidentReport {
                parent.onSelectSNSReport(report)
                return true
            }
            if let item = marker.userData as? AccidentClusterItem {
                parent.onSelectAccident(item.record)
                return true
            }
            return false
        }

        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            let visibleRegion = mapView.projection.visibleRegion()
            let lats = [
                visibleRegion.nearLeft.latitude,
                visibleRegion.nearRight.latitude,
                visibleRegion.farLeft.latitude,
                visibleRegion.farRight.latitude
            ]
            let lons = [
                visibleRegion.nearLeft.longitude,
                visibleRegion.nearRight.longitude,
                visibleRegion.farLeft.longitude,
                visibleRegion.farRight.longitude
            ]
            guard let minLat = lats.min(), let maxLat = lats.max(),
                  let minLon = lons.min(), let maxLon = lons.max() else {
                return
            }
            let box = CoordinateBoundingBox(
                minLatitude: minLat,
                maxLatitude: maxLat,
                minLongitude: minLon,
                maxLongitude: maxLon
            )
            parent.onRegionChanged(box, position.target, position.zoom)
        }
    }
}

/// Google Maps APIキーが未設定の際にもクラッシュせず全機能を試せる MapKit フォールバックビュー。
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

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: LocationAndAlertManager.defaultCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.0025, longitudeDelta: 0.0025)
        )
    )

    var body: some View {
        Map(position: $position) {
            UserAnnotation()

            if let userCoord = userCoordinate {
                Annotation("現在地", coordinate: userCoord) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.25))
                            .frame(width: 32, height: 32)
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                            .shadow(radius: 2)
                    }
                }
            }

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
            withAnimation {
                position = .region(
                    MKCoordinateRegion(
                        center: cameraCenter,
                        span: MKCoordinateSpan(latitudeDelta: 0.0025, longitudeDelta: 0.0025)
                    )
                )
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            let region = context.region
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
