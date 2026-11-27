# App Store Connect 登録用メタデータ（事故マップ / TrafficAccidentCheck）

## 基本情報
- **Bundle ID**: `com.naritamasayuki.TrafficAccidentCheck`
- **SKU**: `TrafficAccidentCheck-001`
- **プライマリ言語**: 日本語（`ja`）
- **カテゴリ**: プライマリ「ナビゲーション」 / セカンダリ「天気・ユーティリティ」または「ライフスタイル」
- **価格**: 無料（アプリ内課金なし / 広告あり）
- **年齢制限指定**: `4+`
- **プライバシーポリシー URL**: `https://naritamasayuki.github.io/TrafficAccidentCheck/privacy-policy.html`（※ GitHub Pages 有効化後）
- **サポート URL**: `https://github.com/naritamasayuki/TrafficAccidentCheck/issues`

---

## 1. 日本語（ja）
- **アプリ名（30文字以内）**: `事故マップ - 交通事故チェック`
- **サブタイトル（30文字以内）**: `周辺の危険度診断と事故多発地の音声案内`
- **プロモーションテキスト（170文字以内）**:
  `警察庁の交通事故オープンデータとSNS速報をマップ上に可視化。現在地周辺100mの危険度診断や、事故多発ゾーンへの接近を音声でお知らせします。`
- **キーワード（100文字以内・カンマ区切り）**:
  `交通事故,事故マップ,ハザードマップ,安全運転,ドライブ,音声案内,ヒヤリハット,交差点,危険度,警察庁`
- **概要（説明文）**:
```
「事故マップ」は、警察庁が公開している交通事故統計オープンデータをもとに、全国の交通事故発生地点を地図上でひと目で確認できる安全運転・歩行サポートアプリです。

【主な機能】
1. 事故の程度による3段階色分け＆ワンタップ表示切替
・赤：死亡事故 / 橙：複数負傷（2名以上） / 黄：負傷（1名） / 紫：SNS・速報（未確認情報）
・マップ下部のタグをタップするだけで、見たい種類だけを瞬時に表示・非表示に切り替えできます。

2. 事故多発ゾーン（ホットスポット）の強調表示
・直近1年間で半径150m圏内に事故が集中している危険エリアを、二重リングと「多発 ○件」バッジで分かりやすく強調します。

3. 周辺危険度スコア診断（初期値：半径100m）
・現在地やマップ中心から半径100m（300m / 500m / 1kmへ変更可能）の事故件数・死亡事故・夜間割合から危険度を0〜100点で診断します。

4. 接近時の音声アナウンス＆通知（バックグラウンド対応）
・事故多発地点に近づくと、音声アナウンスと通知でお知らせします（設定により画面消灯中も案内可能）。

5. 豊富な絞り込み・ヒートマップ表示
・初期表示は直近3年分。発生年・重大度・昼夜・天候・事故類型での絞り込みや、ピン表示／ヒートマップ切り替えに対応。

6. 多言語対応
・日本語・英語・中国語（簡体字／繁体字）の表示および音声案内に自動対応しています。

※本アプリは警察庁が公開しているオープンデータを利用した独自の民間アプリであり、警察庁・政府機関・自治体等を代表するものではありません。
```

---

## 2. 英語（en-US）
- **App Name**: `Accident Map - Safety Check`
- **Subtitle**: `Local Crash Risk & Voice Alerts`
- **Promotional Text**:
  `Visualize official traffic accident open data in Japan on an interactive map. Check 100m area risk scores and get voice alerts near accident hotspots.`
- **Keywords**:
  `traffic accident,hazard map,safe driving,voice alert,intersection,road safety,japan`
- **Description**:
```
"Accident Map" is a driving and walking safety support app that visualizes traffic accident open data published by Japan's National Police Agency.

Key Features:
1. Color-Coded Severity & Quick Toggle
- Red: Fatal / Orange: Multiple Injuries (2+) / Yellow: 1 Injury / Purple: Unverified SNS Reports.
- Tap the bottom legend tags to toggle each category on or off.

2. Highlighted Accident Hotspots
- Areas with frequent accidents within 150m over the past year are highlighted with double rings and count badges.

3. Local Risk Score (Default: 100m Radius)
- Evaluates risk (0–100) within 100m (adjustable to 300m / 500m / 1km) based on total crashes, fatalities, and nighttime ratio.

4. Voice & Proximity Alerts (Background Mode Supported)
- Receive concise voice warnings and notifications when approaching accident hotspots.

5. Filters & Heatmap Mode
- Defaults to the last 3 years; filter by year, severity, day/night, weather, and accident type, or switch between pins and heatmap.

6. Multi-Language Support
- Supports Japanese, English, and Chinese (Simplified & Traditional) for both UI and voice alerts.

Note: This is an independent private app using public open data and is not affiliated with any government agency.
```

---

## 3. 中国語簡体字（zh-Hans） / 繁体字（zh-Hant）
- **アプリ名（簡体字 / 繁体字）**: `事故地图 - 交通事故安全检查` / `事故地圖 - 交通事故安全檢查`
- **サブタイトル（簡体字 / 繁体字）**: `周边风险评估与事故多发地语音提醒` / `周邊風險評估與事故多發地語音提醒`
- **概要（簡体字）**:
  `基于日本警察厅公开开放数据，在地图上直观展示交通事故发生地点。支持按严重程度（死亡/多人受伤/受伤/SNS快报）分色显示与一键切换、100米周边风险评分、事故多发区高亮标识以及接近时的语音和通知提醒。`

---

## 4. App Review（審査担当者向けメモ）
```
- 本アプリは警察庁公開のオープンデータ（https://www.npa.go.jp/publications/statistics/koutsuu/opendata/index_opendata.html）を利用した民間アプリであり、政府機関を代表するものではありません。アプリ内にも免責事項を明記しています。
- 位置情報（バックグラウンド含む）は、ユーザーが「バックグラウンドON」を有効にした場合のみ、アプリを開いたまま画面を消灯した状態で事故多発地点への接近音声案内・通知を行うために使用します。位置情報は端末内処理のみで外部サーバーへ送信されません。
- 上部バーの「絞り込み・都市選択」ボタンから開くシート内の「音声アナウンス・接近警告のサンプル再生（音量確認）」から、接近通知・音声案内の動作をご確認いただけます。
```
