# iOS アプリ App Store 提出・申請ガイド（AI 連携用手順書）

このドキュメントは、iOS アプリを **Antigravity（AI）と連携しながら最短・スムーズに App Store へ提出するための手順書** です。  
別アプリを提出する際も、このファイルを新しいワークスペースにコピーするか参照させることで、迷わず同じ流れで提出できます。

---

## 0. AI（Antigravity）への最初の指示テンプレート

新しいアプリのフォルダを開いたら、最初に以下のように指示するとスムーズです：

> 「`docs/app-store-submission-guide.md` の手順に沿って、このアプリの App Store 提出準備からビルド・アップロード・提出サポートまで進めてください。」

---

## フェーズ 1：事前チェックとコード側の仕上げ（主に AI が実施）

AI が以下の項目を自動確認・整備します。

- [ ] **Bundle Identifier の確認**: 一意の ID（例：`com.yourname.AppName`）になっているか
- [ ] **バージョン・ビルド番号の確認**:
  - `MARKETING_VERSION`（例：`1.0`）
  - `CURRENT_PROJECT_VERSION`（初回 `1`、再アップロード時は `2`, `3`… へ自動インクリメント）
- [ ] **対象デバイスの設定（`TARGETED_DEVICE_FAMILY`）**:
  - iPhone 専用アプリの場合は **`1`（iPhone のみ）** に設定する  
    （※ `1,2` のままだと App Store Connect で iPad 用スクリーンショットが必須になり手間が増えます）
- [ ] **Signing & Capabilities**:
  - `DEVELOPMENT_TEAM` が設定され、`CODE_SIGN_STYLE = Automatic` になっているか
- [ ] **プライバシーマニフェスト（`PrivacyInfo.xcprivacy`）**:
  - 必要な API 利用理由（例：`UserDefaults` 等）が記載され、ターゲットに含まれているか
- [ ] **多言語対応（ローカライズ）**:
  - UI 文言（`Localizable.xcstrings`）および権限説明・アプリ名（`InfoPlist.xcstrings`）が `ja` / `en` 等に対応しているか
  - `knownRegions` にすべての対応言語が登録されているか
- [ ] **機密情報の保護**:
  - API キー等（`Secrets.xcconfig` や `.env`）が `.gitignore` に含まれており、Git にコミットされていないか

---

## フェーズ 2：提出用素材・ドキュメントの準備（AI ＋ ユーザー）

### AI が作成・加工する項目
- [ ] **メタデータ原稿（`docs/app-store-metadata.md`）の作成**:
  - アプリ名 / サブタイトル / プロモーションテキスト / 概要 / キーワード（100文字以内） / サポート URL / 著作権表記
- [ ] **プライバシーポリシー HTML（`docs/privacy-policy.html`）の作成**:
  - アプリ名・取得データ・問い合わせ先・多言語表記（JA/EN 等）を反映
- [ ] **スクリーンショットの規格サイズ調整**:
  - ユーザーが撮影した画面画像を指定サイズ（例：iPhone 6.3 インチ `1260×2736` 等、JPEG/PNG）へリサイズ・変換

### ユーザーが用意する項目
- [ ] **アプリアイコン**: 1024×1024 px（透過なし）
- [ ] **アプリ実画面のスクリーンショット**: シミュレータまたは実機で撮影（最低 1〜3 枚）

---

## フェーズ 3：ビルドと App Store Connect へのアップロード（AI または Xcode）

### コマンドラインまたは Xcode で実行
- **Xcode で行う場合**:
  1. 実行先デバイスを **「Any iOS Device (arm64)」** に選択
  2. メニュー **「Product」→「Archive」**
  3. Organizer から **「Distribute App」→「App Store Connect」→「Upload」**
- **AI が CLI（`xcodebuild`）で実行する場合**:
  - Archive → `ExportOptions.plist`（`method: app-store-connect`）を用いてアップロードまで一括実行

> [!NOTE]
> アップロード成功後、App Store Connect 上でビルドが処理完了して選択可能になるまで **数分〜15分程度** かかります。

---

## フェーズ 4：App Store Connect での登録・提出（ユーザー操作 ＋ AI ナビゲート）

画面のスクリーンショットをチャットに貼りながら進めると、AI が次に押すべき箇所を正確に案内できます。

1. **アプリ枠の作成**（未作成の場合）:
   - [App Store Connect](https://appstoreconnect.apple.com/) → **「アプリ」→「＋」→「新規アプリ」**
   - プラットフォーム（iOS）、名前、プライマリ言語、バンドル ID、SKU を入力
2. **基本設定（左メニュー上から順）**:
   - **一般 → アプリ情報**: カテゴリ、年齢制限指定を設定
   - **一般 → 価格および配信状況**: 価格（無料等）と配信地域を設定
   - **信頼と安全性 → アプリのプライバシー**:
     - プライバシーポリシー URL を入力（例：`https://<username>.github.io/<repo>/privacy-policy.html`）
     - 収集データ（広告 SDK / 位置情報 / 診断データ等）を回答して **「公開」**
3. **バージョン情報（提出準備中）**:
   - **スクリーンショット** を登録
   - **プロモーションテキスト / 概要 / キーワード / サポート URL** を貼り付け（`docs/app-store-metadata.md` からコピー）
   - **ビルド** 欄の「＋」からアップロード済みのビルドを選択
   - **App Review に関する情報**: 連絡先（氏名・電話・メール）を入力（ログインが必要ならデモアカウントを記載）
   - **バージョンのリリース**: 「このバージョンを自動的にリリース」等を選択
4. **提出**:
   - 右上の **「保存」** → **「審査用に追加」** → **「App Review に提出」**
   - 輸出コンプライアンス（暗号化の使用有無）に回答し、ステータスが **「審査待ち」**（提出されました）になれば完了

---

## フェーズ 5：プライバシーポリシー公開 ＆ リポジトリ同期（提出後の仕上げ）

### 1. プライバシーポリシー URL の公開（GitHub Pages）
GitHub 無料プランでは **Public リポジトリ** でのみ GitHub Pages を利用できます。

- **方法 A（リポジトリを Public にできる場合）**:
  1. 事前に `Secrets.xcconfig` などの機密ファイルがリポジトリに含まれていないことを AI に確認させる
  2. GitHub の **Settings → General → Danger Zone → Change visibility → Make public**
  3. **Settings → Pages** で Source を `Deploy from a branch`、Branch を `main` と `/docs` にして **Save**
- **方法 B（リポジトリを Private のままにしたい場合）**:
  1. プライバシーポリシー掲載専用の **Public リポジトリ**（例：`<username>.github.io`）を作成して `privacy-policy.html` を配置し、Pages を有効化
  2. 公開 URL に合わせて App Store Connect 側のプライバシーポリシー URL を設定
- **公開確認**:
  - 1〜2 分後に公開 URL へアクセスし、HTTP `200` で表示されることを確認する

### 2. GitHub / Google ドライブへの同期
作業完了後、変更をコミットして両方のリモートへプッシュします：

```bash
git push origin main
git push gdrive main
```

---

## よくあるハマりポイントと対策

| 現象 | 原因 | 対策 |
| :--- | :--- | :--- |
| iPad 用スクリーンショットを求められる | `TARGETED_DEVICE_FAMILY` が `1,2`（Universal）になっている | iPhone のみなら `TARGETED_DEVICE_FAMILY = 1` に変更して再ビルド・アップロード |
| GitHub Pages で「Upgrade or make this repository public」と出る | リポジトリが Private になっている（無料プラン制限） | リポジトリを Public に変更するか、公開用別リポジトリで Pages を有効化 |
| Xcode / git で Push 時に認証エラーが出る | 古い credential helper が残っている／トークン未設定 | `~/.gitconfig` の壊れた `credential.helper` を確認し、Xcode Settings → Accounts で GitHub アカウント（Classic PAT: `repo`, `admin:public_key`, `user`）でサインイン |
| アップロードしたビルドが App Store Connect に表示されない | Apple 側での処理中 | 5〜15 分ほど待ってからページを再読み込みする |
