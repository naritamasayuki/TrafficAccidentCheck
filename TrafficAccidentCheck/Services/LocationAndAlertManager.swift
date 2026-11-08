import Combine
import CoreLocation
import Foundation
import UserNotifications

/// 現在地の追跡および事故多発地点（ホットスポット）への接近検知・ローカル通知を管理するクラス。
@MainActor
final class LocationAndAlertManager: NSObject, ObservableObject {
    /// デフォルトの初期座標（東京駅周辺）
    static let defaultCoordinate = CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125)

    @Published private(set) var userCoordinate: CLLocationCoordinate2D?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isProximityAlertEnabled: Bool = true
    @Published var activeHotspotAlert: AccidentHotspot?

    private let locationManager = CLLocationManager()
    private var monitoredHotspots: [AccidentHotspot] = []
    private var notifiedHotspotTimestamps: [String: Date] = [:]
    /// 同一ホットスポットに対する再通知クールダウン秒数（15分）
    private let alertCooldownSeconds: TimeInterval = 900
    /// 接近判定距離（メートル）
    private let triggerDistanceMeters: Double = 150.0

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 25.0
        authorizationStatus = locationManager.authorizationStatus
    }

    /// 位置情報とローカル通知の権限をリクエストし、測位を開始する。
    func requestPermissionsAndStart() {
        locationManager.requestWhenInUseAuthorization()
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
        requestNotificationPermission()
    }

    /// ローカル通知権限をリクエストする。
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                AppLogger.logError(AppLogger.location, context: "通知権限リクエストエラー", error: error)
            } else {
                AppLogger.location.info("通知権限ステータス: \(granted ? "許可" : "未許可")")
            }
        }
    }

    /// 監視対象の事故多発ホットスポット一覧を更新し、現在地との距離を即時評価する。
    func updateMonitoredHotspots(_ hotspots: [AccidentHotspot]) {
        self.monitoredHotspots = hotspots
        if let current = userCoordinate {
            evaluateProximity(at: current)
        }
    }

    /// シミュレータやテスト用に任意の座標へ移動した際の接近判定を実行する。
    func simulateApproach(to coordinate: CLLocationCoordinate2D) {
        self.userCoordinate = coordinate
        evaluateProximity(at: coordinate)
    }

    /// 指定座標がホットスポットの半径150m以内に入ったか判定し、該当すれば通知を送出する。
    func evaluateProximity(at coordinate: CLLocationCoordinate2D) {
        guard isProximityAlertEnabled, !monitoredHotspots.isEmpty else { return }

        let userLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let now = Date()

        for hotspot in monitoredHotspots {
            let spotLoc = CLLocation(latitude: hotspot.coordinate.latitude, longitude: hotspot.coordinate.longitude)
            let distance = userLoc.distance(from: spotLoc)
            guard distance <= triggerDistanceMeters else { continue }

            if let lastNotified = notifiedHotspotTimestamps[hotspot.id],
               now.timeIntervalSince(lastNotified) < alertCooldownSeconds {
                continue
            }

            notifiedHotspotTimestamps[hotspot.id] = now
            activeHotspotAlert = hotspot
            sendLocalNotification(for: hotspot, distanceMeters: Int(distance.rounded()))
            AppLogger.location.notice("事故多発地点への接近を検知: \(hotspot.id) (距離 \(Int(distance))m)")
            break
        }
    }

    private func sendLocalNotification(for hotspot: AccidentHotspot, distanceMeters: Int) {
        let content = UNMutableNotificationContent()
        content.title = hotspot.alertTitle
        content.body = "前方約\(distanceMeters)m: \(hotspot.alertBody)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "hotspot-\(hotspot.id)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.logError(AppLogger.location, context: "ローカル通知送信エラー", error: error)
            }
        }
    }
}

extension LocationAndAlertManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.locationManager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let coord = latest.coordinate
        Task { @MainActor in
            self.userCoordinate = coord
            self.evaluateProximity(at: coord)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLogger.logError(AppLogger.location, context: "CLLocationManager測位エラー", error: error)
    }
}
