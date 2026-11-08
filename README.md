# 交通事故チェックアプリ (iOS / SwiftUI + Google Maps SDK)

過去の交通事故統計（警察庁オープンデータ・全国約57.8万件）と、SNS・速報から抽出した最新データ（出典をSNS・未確認と明記）を Google マップ上に重ねて表示し、現在地周辺の危険度判定や事故多発地点への接近通知を行う iOS アプリです。

---

## 主な機能

1. **過去の交通事故マップ表示（ピン・クラスタリング / ヒートマップ切替）**
   - 警察庁「交通事故統計情報のオープンデータ」（2024年・2025年本票、計 577,915 件）を32バイト固定長バイナリ（`accidents.bin`）として同梱し、メモリマップドI/O（`.mappedIfSafe`）で高速検索・描画します。
   - Google 公式の [`google-maps-ios-utils`](https://github.com/googlemaps/google-maps-ios-utils) によるマーカークラスタリング（`GMUClusterManager`）とヒートマップ（`GMUHeatmapTileLayer`）に対応しています。
   - **APIキー未設定時の自動フォールバック**: `Config/Secrets.xcconfig` に Google Maps API キーを設定する前でもクラッシュせず、自動的に互換マップ（MapKit）で全機能を動作確認できます。

2. **最新データのSNS・速報表示（無料データソース活用・出典明記）**
   - 有料APIを一切使わず、無料の公開データソース（**Mastodon 公開ハッシュタグタイムライン `#交通事故`** および **Google ニュース RSS**）から最新の事故投稿・速報を取得し、**国土地理院の無料住所検索API**（`https://msearch.gsi.go.jp/address-search/AddressSearch`）で緯度経度に変換します。
   - 地図上には紫色のピンで区別して描画され、詳細シートやバッジに **「出典: SNS / 速報 [未確認情報]」** と明確に表示します。

3. **事故詳細シート**
   - 発生日時、死亡/負傷区分、死者数・負傷者数、天候、昼夜、路面状態、道路形状、信号機の有無、事故類型、当事者A/Bの種別・年齢層・損傷程度、都道府県、座標、データ出典を表示します。

4. **絞り込みフィルタ・主要都市ジャンプ**
   - 発生年（すべて / 2025年 / 2024年）、重大度（死亡事故のみ / 負傷事故のみ）、時間帯（昼間 / 夜間）、天候、事故類型、SNS未確認速報の表示ON/OFFを切り替えられます。

5. **現在地周辺の危険度スコア表示 ＆ 事故多発地点の接近通知**
   - 半径500m以内の事故件数・死亡事故数・夜間事故割合・最多事故類型から危険度スコア（0〜100）と安全運転アドバイスをリアルタイム算出します。
   - 150mメッシュで事故が集中しているブラックスポット（事故多発地点）を自動抽出し、接近時にローカル通知と画面上部バナーで警告します（15分間の再通知クールダウン付き）。

---

## セットアップ手順

### 1. Google Maps API キーの設定（任意）

APIキーはソースコードに直接記述せず、Git管理外の `Config/Secrets.xcconfig` で管理します。

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

`Config/Secrets.xcconfig` を開き、Google Cloud Console で「Maps SDK for iOS」を有効化した API キーを設定してください。

```xcconfig
GOOGLE_MAPS_API_KEY = AIzaSy...
```

> **補足**: API キーを設定しない場合でも、アプリは自動的に MapKit 互換モードで起動し、全機能を確認できます。

### 2. データ更新スクリプト（無料データソース）

- **公式オープンデータの再生成**:
  ```bash
  python3 scripts/build_accident_data.py --years 2024 2025
  ```
- **最新SNS・速報データの取得・更新**:
  ```bash
  python3 scripts/fetch_sns_accidents.py
  ```
  また、GitHub Actions（[`.github/workflows/update_sns_feed.yml`](.github/workflows/update_sns_feed.yml)）により、無料枠で6時間ごとに自動更新する構成を備えています。

---

## テスト・静的解析・CI/CD（Anti-Gravity 開発方針準拠）

- **Python ユニットテスト**:
  ```bash
  python3 -m unittest discover -s tests -v
  ```
- **Swift コアロジック単体テスト**:
  ```bash
  swiftc -parse-as-library \
    TrafficAccidentCheck/Utilities/AppLogger.swift \
    TrafficAccidentCheck/Models/AccidentRecord.swift \
    TrafficAccidentCheck/Models/SNSAccidentReport.swift \
    TrafficAccidentCheck/Models/AccidentFilter.swift \
    TrafficAccidentCheck/Services/AccidentDataStore.swift \
    TrafficAccidentCheck/Services/SNSAccidentService.swift \
    TrafficAccidentCheck/Services/DangerAnalyzer.swift \
    scripts/run_swift_core_tests.swift \
    -o /tmp/core_tests && /tmp/core_tests
  ```
- **Xcode テストターゲットビルド**:
  ```bash
  xcodebuild -project TrafficAccidentCheck.xcodeproj \
    -scheme TrafficAccidentCheck \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO \
    build-for-testing
  ```
- **GitHub Actions / セキュリティ管理**:
  - [`.github/workflows/ci.yml`](.github/workflows/ci.yml): Push / PR 時に Python テスト・Flake8・SwiftLint・Swift 単体テスト・Xcode ビルドを自動実行
  - [`.github/workflows/codeql.yml`](.github/workflows/codeql.yml): CodeQL による脆弱性スキャン
  - [`.github/dependabot.yml`](.github/dependabot.yml): Dependabot による依存パッケージの脆弱性自動チェック
