import GoogleMaps
import SwiftUI

/// iOS版 交通事故チェックアプリのエントリポイント。
/// APIキーはソースコードに直接記述せず、`Config/Secrets.xcconfig`（または環境変数 `GOOGLE_MAPS_API_KEY`）経由で注入する。
@main
struct TrafficAccidentCheckApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let isGoogleMapsConfigured: Bool

    init() {
        let envKey = ProcessInfo.processInfo.environment["GOOGLE_MAPS_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let plistKey = (Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let candidateKey = (envKey?.isEmpty == false ? envKey : plistKey) ?? ""
        if !candidateKey.isEmpty && candidateKey != "YOUR_API_KEY_HERE" && !candidateKey.hasPrefix("$(") {
            GMSServices.provideAPIKey(candidateKey)
            self.isGoogleMapsConfigured = true
            AppLogger.map.info("Google Maps SDK の初期化が完了しました。")
        } else {
            self.isGoogleMapsConfigured = false
            AppLogger.map.notice("Google Maps APIキーが未設定のため、互換マップ（MapKit）モードで起動します。")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(isGoogleMapsConfigured: isGoogleMapsConfigured)
                .task {
                    AdMobService.shared.startAdFlowAfterActive()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        AdMobService.shared.startAdFlowAfterActive()
                    }
                }
        }
    }
}
