import AVFoundation
import Combine
import CoreLocation
import Foundation
import UserNotifications

/// 現在地の追跡、マップの現在地追従、および事故多発地点（ホットスポット）への接近検知・音声アナウンス・ローカル通知を管理するクラス。
@MainActor
final class LocationAndAlertManager: NSObject, ObservableObject {
    /// デフォルトの初期座標（測位完了前のフォールバック: 東京駅周辺）
    static let defaultCoordinate = CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125)

    private static let proximityAlertKey = "TrafficAccidentCheck.ProximityAlertEnabled.v1"
    private static let voiceAlertKey = "TrafficAccidentCheck.VoiceAnnouncementEnabled.v1"
    private static let followUserKey = "TrafficAccidentCheck.FollowUserEnabled.v1"
    private static let backgroundModeKey = "TrafficAccidentCheck.BackgroundModeEnabled.v1"

    /// 現在のユーザー位置座標
    @Published private(set) var userCoordinate: CLLocationCoordinate2D?
    /// 現在の移動速度（m/s、不明または停止時は0）
    @Published private(set) var currentSpeedMetersPerSecond: Double = 0
    /// 現在の進行方向（度、無効時は nil）
    private var currentCourseDegrees: Double?
    /// 位置情報が更新されるたびにインクリメントされるトリガー（マップ追従用）
    @Published private(set) var locationUpdateCount: Int = 0
    /// 初回測位が完了したかどうか
    @Published private(set) var hasInitialLocationFix: Bool = false
    /// 位置情報権限ステータス
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// 位置情報権限が拒否または制限されているかどうか
    var isLocationDeniedOrRestricted: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// 移動に合わせてマップを自動追従するかどうか
    @Published var isFollowingUser: Bool {
        didSet {
            UserDefaults.standard.set(isFollowingUser, forKey: Self.followUserKey)
        }
    }

    /// 事故多発地点への接近アラート（バナー＋ローカル通知）を有効にするかどうか
    @Published var isProximityAlertEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isProximityAlertEnabled, forKey: Self.proximityAlertKey)
            if isProximityAlertEnabled {
                requestNotificationPermission()
            }
        }
    }

    /// 事故現場に近づいた際の音声アナウンス（日本語読み上げ）を有効にするかどうか
    @Published var isVoiceAnnouncementEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isVoiceAnnouncementEnabled, forKey: Self.voiceAlertKey)
            if !isVoiceAnnouncementEnabled && speechSynthesizer.isSpeaking {
                speechSynthesizer.stopSpeaking(at: .immediate)
            }
        }
    }

    /// アプリを閉じた状態や画面消灯中もバックグラウンドで接近検知・音声案内を継続するかどうか
    @Published var isBackgroundModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isBackgroundModeEnabled, forKey: Self.backgroundModeKey)
            applyBackgroundLocationSetting()
            if isBackgroundModeEnabled {
                requestPermissionsAndStart()
                requestNotificationPermission()
            }
        }
    }

    /// 現在画面上に表示中の接近警告ホットスポット
    @Published var activeHotspotAlert: AccidentHotspot?

    private let locationManager = CLLocationManager()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var monitoredHotspots: [AccidentHotspot] = []
    private var notifiedHotspotTimestamps: [String: Date] = [:]
    private var lastGlobalAlertTimestamp: Date?
    private var bannerDismissTask: Task<Void, Never>?
    /// 同一ホットスポットに対する再通知クールダウン秒数（15分）
    private let alertCooldownSeconds: TimeInterval = 900
    /// 連続アラートの全体クールダウン秒数（15秒）
    private let globalAlertCooldownSeconds: TimeInterval = 15
    /// 接近判定距離（メートル）
    private let triggerDistanceMeters: Double = 150.0

    override init() {
        let defaults = UserDefaults.standard
        self.isProximityAlertEnabled = defaults.object(forKey: Self.proximityAlertKey) as? Bool ?? true
        self.isVoiceAnnouncementEnabled = defaults.object(forKey: Self.voiceAlertKey) as? Bool ?? true
        self.isFollowingUser = defaults.object(forKey: Self.followUserKey) as? Bool ?? true
        self.isBackgroundModeEnabled = defaults.object(forKey: Self.backgroundModeKey) as? Bool ?? false

        super.init()
        locationManager.delegate = self
        // 移動中のマップ追従と事故現場接近検知のため高精細かつ10m単位で更新を受け取る
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 10.0
        authorizationStatus = locationManager.authorizationStatus
        speechSynthesizer.delegate = self
        applyBackgroundLocationSetting()
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let typeVal = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeVal) else { return }
            Task { @MainActor [weak self] in
                if type == .began {
                    self?.speechSynthesizer.stopSpeaking(at: .immediate)
                }
            }
        }
    }

    /// 実行バンドルの Info.plist にバックグラウンド位置情報モード（`location`）が定義されているか確認する。
    static func supportsBackgroundLocation(in bundle: Bundle = .main) -> Bool {
        let modes = bundle.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        return modes.contains("location")
    }

    /// バックグラウンドモードのON/OFFに応じて CLLocationManager のバックグラウンド更新設定を切り替える。
    private func applyBackgroundLocationSetting() {
        let canUseBackground = Self.supportsBackgroundLocation()
        if isBackgroundModeEnabled && !canUseBackground {
            AppLogger.location.error("Info.plist に UIBackgroundModes(location) が未設定のためバックグラウンド位置情報を有効化できません。")
            return
        }
        if canUseBackground {
            locationManager.allowsBackgroundLocationUpdates = isBackgroundModeEnabled
            locationManager.showsBackgroundLocationIndicator = isBackgroundModeEnabled
        }
        locationManager.pausesLocationUpdatesAutomatically = !isBackgroundModeEnabled
        AppLogger.location.info("バックグラウンドモード設定: \(self.isBackgroundModeEnabled ? "ON" : "OFF")")
    }

    /// 位置情報の権限のみをリクエストし、許可済みなら即座に測位を開始する。
    /// 通知権限は接近警告ON時やユーザー操作時に別途リクエストし、初回起動時のダイアログ連発を防ぐ。
    func requestPermissionsAndStart() {
        authorizationStatus = locationManager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startLocationTrackingImmediately()
        default:
            break
        }
    }

    /// 測位開始時にキャッシュ済み位置情報があれば即座に反映し、連続測位を開始する。
    private func startLocationTrackingImmediately() {
        locationManager.startUpdatingLocation()
        if let cachedLocation = locationManager.location,
           CLLocationCoordinate2DIsValid(cachedLocation.coordinate) {
            applyNewUserCoordinate(cachedLocation.coordinate)
        }
    }

    /// 新しい現在地座標を反映し、マップ追従トリガーと接近判定を更新する。
    private func applyNewUserCoordinate(_ coord: CLLocationCoordinate2D) {
        self.userCoordinate = coord
        self.hasInitialLocationFix = true
        self.locationUpdateCount += 1
        evaluateProximity(at: coord)
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

    /// サンプル再生・音量確認用。現在地座標は一切変更せず、バナー・通知・音声案内のみを実行する。
    func simulateApproach(to hotspot: AccidentHotspot) {
        presentHotspotAlert(hotspot, distanceMeters: 80, forceSpeak: true)
    }

    /// 指定座標がホットスポットの半径150m以内に入ったか判定し、該当すればバナー・通知・音声アナウンスを送出する。
    func evaluateProximity(at coordinate: CLLocationCoordinate2D) {
        guard isProximityAlertEnabled, !monitoredHotspots.isEmpty else { return }

        let now = Date()
        if let lastGlobal = lastGlobalAlertTimestamp,
           now.timeIntervalSince(lastGlobal) < globalAlertCooldownSeconds {
            return
        }

        let userLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        for hotspot in monitoredHotspots {
            let spotLoc = CLLocation(latitude: hotspot.coordinate.latitude, longitude: hotspot.coordinate.longitude)
            let distance = userLoc.distance(from: spotLoc)
            guard distance <= triggerDistanceMeters else { continue }

            // 移動中かつ進行方向が取得できている場合、すでに通り過ぎて背後に回った地点はスキップする
            if let course = currentCourseDegrees, currentSpeedMetersPerSecond >= 2.0, distance > 25.0 {
                let bearing = Self.bearingDegrees(from: coordinate, to: hotspot.coordinate)
                let diff = abs(Self.normalizedAngleDifference(course, bearing))
                if diff > 100.0 {
                    continue
                }
            }

            if let lastNotified = notifiedHotspotTimestamps[hotspot.id],
               now.timeIntervalSince(lastNotified) < alertCooldownSeconds {
                continue
            }

            notifiedHotspotTimestamps[hotspot.id] = now
            lastGlobalAlertTimestamp = now
            let roundedDistance = max(10, Int((distance / 10.0).rounded() * 10))
            presentHotspotAlert(hotspot, distanceMeters: roundedDistance, forceSpeak: false)
            AppLogger.location.notice("事故多発地点への接近を検知・音声案内実行: \(hotspot.id) (距離 \(Int(distance))m)")
            break
        }
    }

    private func presentHotspotAlert(_ hotspot: AccidentHotspot, distanceMeters: Int, forceSpeak: Bool) {
        activeHotspotAlert = hotspot
        bannerDismissTask?.cancel()
        bannerDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            if !Task.isCancelled, self.activeHotspotAlert?.id == hotspot.id {
                self.activeHotspotAlert = nil
            }
        }
        sendLocalNotification(for: hotspot, distanceMeters: distanceMeters)
        if isVoiceAnnouncementEnabled || forceSpeak {
            speakWarning(for: hotspot, distanceMeters: distanceMeters)
        }
    }

    nonisolated static func bearingDegrees(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180.0
        let lon1 = from.longitude * .pi / 180.0
        let lat2 = to.latitude * .pi / 180.0
        let lon2 = to.longitude * .pi / 180.0
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180.0 / .pi
        return fmod(deg + 360.0, 360.0)
    }

    nonisolated static func normalizedAngleDifference(_ a: Double, _ b: Double) -> Double {
        var diff = fmod(b - a + 540.0, 360.0) - 180.0
        if diff < -180.0 { diff += 360.0 }
        return diff
    }

    /// 事故多発地点への接近時に読み上げる音声アナウンス文言を生成する。
    /// 特に事故が多い地区（直近1年間で10件以上、または死亡事故あり）では「要注意ポイントです。」を先頭に付与し、直近1年間の発生件数を読み上げる。
    nonisolated static func warningMessage(for hotspot: AccidentHotspot, distanceMeters: Int) -> String {
        if hotspot.fatalCount > 0 {
            return L10n.format(
                "要注意ポイントです。この先%dメートル付近、直近1年間で死亡事故を含む%d件の事故が発生しました。",
                distanceMeters,
                hotspot.accidentCount
            )
        }
        if hotspot.isHighAlertHotspot {
            return L10n.format(
                "要注意ポイントです。この先%dメートル付近、直近1年間で%d件の事故が発生しました。",
                distanceMeters,
                hotspot.accidentCount
            )
        }
        return L10n.format(
            "この先%dメートル付近、事故多発地点です。直近1年間で%d件の事故が発生しました。",
            distanceMeters,
            hotspot.accidentCount
        )
    }

    /// 日本語音声合成（AVSpeechSynthesizer）で事故現場への接近アナウンスを読み上げる。
    func speakWarning(for hotspot: AccidentHotspot, distanceMeters: Int) {
        let message = Self.warningMessage(for: hotspot, distanceMeters: distanceMeters)

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try audioSession.setActive(true)
        } catch {
            AppLogger.logError(AppLogger.location, context: "音声アナウンス用AVAudioSession設定エラー（通知のみ送出）", error: error)
            return
        }

        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = AVSpeechSynthesisVoice(language: L10n.speechLanguageCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        speechSynthesizer.speak(utterance)
    }

    private func sendLocalNotification(for hotspot: AccidentHotspot, distanceMeters: Int) {
        let content = UNMutableNotificationContent()
        content.title = hotspot.alertTitle
        content.body = L10n.format("前方約%dm: %@", distanceMeters, hotspot.alertBody)
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
                self.startLocationTrackingImmediately()
            }
            if status != .notDetermined {
                AdMobService.shared.startAdFlowAfterActive()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last,
              CLLocationCoordinate2DIsValid(latest.coordinate),
              latest.horizontalAccuracy >= 0,
              latest.horizontalAccuracy <= 100.0,
              abs(latest.timestamp.timeIntervalSinceNow) <= 30.0 else { return }
        let coord = latest.coordinate
        let speed = latest.speed >= 0 ? latest.speed : 0
        let course: Double? = latest.course >= 0 ? latest.course : nil
        Task { @MainActor in
            self.currentSpeedMetersPerSecond = speed
            self.currentCourseDegrees = course
            self.applyNewUserCoordinate(coord)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLogger.logError(AppLogger.location, context: "CLLocationManager測位エラー", error: error)
    }
}

extension LocationAndAlertManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
