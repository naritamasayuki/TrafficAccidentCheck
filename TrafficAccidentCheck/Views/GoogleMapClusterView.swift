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

                // ホットスポット（事故多発150m圏）のサークルを更新
                for circle in hotspotCircles { circle.map = nil }
                hotspotCircles.removeAll()
                for spot in hotspots.prefix(8) {
                    let circle = GMSCircle(position: spot.coordinate, radius: 150)
                    circle.fillColor = (spot.fatalCount > 0 ? UIColor.systemRed : UIColor.systemOrange)
                        .withAlphaComponent(0.14)
                    circle.strokeColor = (spot.fatalCount > 0 ? UIColor.systemRed : UIColor.systemOrange)
                        .withAlphaComponent(0.6)
                    circle.strokeWidth = 1.5
                    circle.map = mapView
                    hotspotCircles.append(circle)
                }
            }

            if snsIDs != lastRenderedSNSIDs {
                lastRenderedSNSIDs = snsIDs
                for marker in snsMarkers { marker.map = nil }
                snsMarkers.removeAll()

                for report in snsReports {
                    let marker = GMSMarker(position: report.coordinate)
                    marker.title = "【SNS・未確認】\(report.extractedLocation)"
                    marker.snippet = report.title
                    marker.icon = GMSMarker.markerImage(with: .systemPurple)
                    marker.userData = report
                    marker.zIndex = 100
                    marker.map = mapView
                    snsMarkers.append(marker)
                }
            }
        }

        // MARK: - GMUClusterRendererDelegate

        func renderer(_ renderer: GMUClusterRenderer, willRenderMarker marker: GMSMarker) {
            if let item = marker.userData as? AccidentClusterItem {
                let rec = item.record
                marker.title = rec.summaryTitle
                marker.snippet = rec.formattedDateTime
                marker.icon = GMSMarker.markerImage(with: rec.isFatal ? .systemRed : .systemOrange)
                marker.zIndex = rec.isFatal ? 50 : 10
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
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
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

            // ホットスポット（事故多発エリア）サークル
            ForEach(hotspots.prefix(10)) { spot in
                MapCircle(center: spot.coordinate, radius: 150)
                    .foregroundStyle((spot.fatalCount > 0 ? Color.red : Color.orange).opacity(0.22))
                    .stroke(spot.fatalCount > 0 ? Color.red : Color.orange, lineWidth: 1.5)
            }

            // 公式事故データ（ピン表示またはヒートマップサークル）
            ForEach(records.prefix(displayMode == .heatmap ? 450 : 300)) { rec in
                if displayMode == .heatmap {
                    MapCircle(center: rec.coordinate, radius: rec.isFatal ? 120 : 65)
                        .foregroundStyle((rec.isFatal ? Color.red : Color.orange).opacity(rec.isFatal ? 0.35 : 0.18))
                } else {
                    Annotation(rec.isFatal ? "死亡" : "負傷", coordinate: rec.coordinate) {
                        Button {
                            onSelectAccident(rec)
                        } label: {
                            Image(systemName: rec.isFatal ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: rec.isFatal ? 18 : 13, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(rec.isFatal ? 5 : 3.5)
                                .background(rec.isFatal ? Color.red : Color.orange, in: Circle())
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
                        span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
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
            let approxZoom = Float(max(4.0, min(20.0, log2(360.0 / max(0.001, region.span.longitudeDelta)))))
            onRegionChanged(box, region.center, approxZoom)
        }
    }
}
