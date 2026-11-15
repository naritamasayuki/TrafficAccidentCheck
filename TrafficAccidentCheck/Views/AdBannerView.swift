import AppTrackingTransparency
import GoogleMobileAds
import SwiftUI
import UIKit

/// Google Mobile Ads SDK の初期化と ATT（App Tracking Transparency）許可リクエストを管理するサービス。
@MainActor
final class AdMobService: ObservableObject {
    static let shared = AdMobService()

    @Published private(set) var isInitialized = false
    private var hasStartedFlow = false
    let configuration: AdMobConfiguration

    private init() {
        self.configuration = AdMobConfiguration.current()
    }

    /// アプリがアクティブになった後、ATTトラッキング許可の確認完了を待ってから Google Mobile Ads SDK を初期化する。
    func startAdFlowAfterActive() {
        guard !hasStartedFlow else {
            initializeIfNeeded()
            return
        }
        hasStartedFlow = true

        Task { @MainActor in
            // iOS 17+ でウィンドウが完全に前面化してからATTダイアログを表示するための短い待機
            try? await Task.sleep(nanoseconds: 600_000_000)
            let status = ATTrackingManager.trackingAuthorizationStatus
            if status == .notDetermined {
                let newStatus = await ATTrackingManager.requestTrackingAuthorization()
                AppLogger.ad.info("ATTトラッキング許可ステータス更新: \(String(describing: newStatus.rawValue))")
            }
            self.initializeIfNeeded()
        }
    }

    /// Info.plist の `GADApplicationIdentifier` を検証した上で Google Mobile Ads SDK を安全に初期化する。
    func initializeIfNeeded() {
        guard !isInitialized else { return }

        let plistAppID = (Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard AdMobConfiguration.isValidAppID(plistAppID) else {
            AppLogger.ad.warning("GADApplicationIdentifier が未設定または不正なため、SDK初期化をスキップしプレースホルダ表示に切り替えます。")
            return
        }

        MobileAds.shared.start { status in
            let adapterCount = status.adapterStatusesByClassName.count
            AppLogger.ad.info("Google Mobile Ads SDK 初期化完了 (アダプタ数: \(adapterCount), テスト広告モード: \(self.configuration.isUsingTestAds))")
        }
        isInitialized = true
    }

    /// iOS 14.5+ 向けの ATT（トラッキング許可）ダイアログを表示する。
    func requestTrackingAuthorizationIfNeeded() {
        startAdFlowAfterActive()
    }
}

/// `BannerView` を SwiftUI で表示するための UIViewRepresentable。
struct GADBannerRepresentableView: UIViewRepresentable {
    let adUnitID: String
    let width: CGFloat
    @Binding var isAdLoaded: Bool
    @Binding var loadErrorDescription: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> BannerView {
        let adSize = currentOrientationAnchoredAdaptiveBanner(width: max(320, width))
        let bannerView = BannerView(adSize: adSize)
        bannerView.adUnitID = adUnitID
        bannerView.delegate = context.coordinator
        bannerView.rootViewController = Self.findRootViewController()
        bannerView.load(Request())
        return bannerView
    }

    func updateUIView(_ bannerView: BannerView, context: Context) {
        context.coordinator.parent = self
        if bannerView.rootViewController == nil {
            bannerView.rootViewController = Self.findRootViewController()
        }
    }

    private static func findRootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController {
                return root
            }
        }
        return scenes.first?.windows.first?.rootViewController
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        var parent: GADBannerRepresentableView

        init(parent: GADBannerRepresentableView) {
            self.parent = parent
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            AppLogger.ad.info("AdMob バナー広告の読み込みに成功しました (UnitID: \(bannerView.adUnitID ?? "-"))")
            Task { @MainActor in
                parent.isAdLoaded = true
                parent.loadErrorDescription = nil
            }
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            AppLogger.logError(AppLogger.ad, context: "AdMob バナー広告の読み込み失敗", error: error)
            Task { @MainActor in
                parent.isAdLoaded = false
                parent.loadErrorDescription = error.localizedDescription
            }
        }
    }
}

/// 画面最下部に常駐する広告バナーコンテナビュー。
/// オフライン時や広告取得エラー時もレイアウト崩れや強制終了を起こさず、控えめな枠を維持する。
struct AdBannerContainerView: View {
    @ObservedObject private var adService = AdMobService.shared
    @State private var isAdLoaded = false
    @State private var loadErrorDescription: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.secondarySystemBackground)

                if adService.isInitialized {
                    GADBannerRepresentableView(
                        adUnitID: adService.configuration.bannerUnitID,
                        width: max(320, proxy.size.width),
                        isAdLoaded: $isAdLoaded,
                        loadErrorDescription: $loadErrorDescription
                    )
                    .opacity(isAdLoaded ? 1.0 : 0.0)
                }

                if !isAdLoaded {
                    HStack(spacing: 6) {
                        Image(systemName: "megaphone.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(adService.configuration.isUsingTestAds ? "広告スペース（AdMob テストモード）" : "広告スペース")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 52)
        .overlay(alignment: .top) {
            Divider()
        }
        .onAppear {
            adService.startAdFlowAfterActive()
        }
    }
}

/// 共通UI仕様に基づく下部バナー広告ビューの型エイリアス。
typealias AdBannerView = AdBannerContainerView
