import SwiftUI

/// iOS版 交通事故チェックアプリのエントリポイント。
/// Apple 標準の MapKit を用いて全国57.8万件の交通事故統計オープンデータを高速に可視化する。
@main
struct TrafficAccidentCheckApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(isGoogleMapsConfigured: false)
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
