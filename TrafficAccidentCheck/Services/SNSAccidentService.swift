import CoreLocation
import Foundation

/// SNSおよび無料ニュースRSSから最新の事故速報（未確認情報）を取得・ジオコーディングするサービス。
/// 有料APIを一切使わず、Mastodon公開タグAPI・GoogleニュースRSS・国土地理院の無料住所検索APIを組み合わせる。
final class SNSAccidentService: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// バンドルに同梱された初期データ (`sns_reports.json`) を読み込む。
    func loadBundledReports(bundle: Bundle = .main) -> [SNSAccidentReport] {
        guard let url = bundle.url(forResource: "sns_reports", withExtension: "json") else {
            AppLogger.network.warning("sns_reports.json がバンドル内に見つかりません。")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(SNSFeedPayload.self, from: data)
            AppLogger.network.info("同梱SNS速報データを読み込みました: \(payload.reports.count) 件")
            return payload.reports
        } catch {
            AppLogger.logError(AppLogger.network, context: "同梱SNS JSONのデコード失敗", error: error)
            return []
        }
    }

    /// 無料の公開データソース（Mastodon公開タグ + GoogleニュースRSS + 国土地理院API）から最新のSNS・速報を取得する。
    /// ネットワーク切断やAPIエラーが発生した場合はログを記録し、既存の同梱データとマージして返す。
    func fetchLatestFreeSNSReports(existingReports: [SNSAccidentReport]) async -> [SNSAccidentReport] {
        var candidates: [RawSNSPost] = []

        async let mastodonTask = fetchMastodonTagPosts()
        async let newsTask = fetchGoogleNewsRSSPosts()

        let (mastodonPosts, newsPosts) = await (mastodonTask, newsTask)
        candidates.append(contentsOf: mastodonPosts)
        candidates.append(contentsOf: newsPosts)

        var newReports: [SNSAccidentReport] = []
        var geocodeCache: [String: CLLocationCoordinate2D] = [:]

        for post in candidates {
            guard Self.isTrafficAccidentRelated(post.text) else { continue }
            guard let place = Self.extractJapaneseLocation(from: post.text) else { continue }

            let coordinate: CLLocationCoordinate2D
            if let cached = geocodeCache[place] {
                coordinate = cached
            } else if let resolved = await geocodeWithGSI(placeName: place) {
                geocodeCache[place] = resolved
                coordinate = resolved
            } else {
                continue
            }

            let id = "sns-live-\(abs(post.text.prefix(40).hashValue))"
            let report = SNSAccidentReport(
                id: id,
                title: String(post.text.prefix(65)),
                body: String(post.text.prefix(280)),
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                extractedLocation: place,
                postedAt: post.postedAt,
                sourceName: post.sourceName,
                sourceType: post.sourceType,
                sourceURL: post.url,
                isUnverified: true,
                category: Self.inferCategory(from: post.text)
            )
            if !newReports.contains(where: { $0.id == report.id || $0.title == report.title }) {
                newReports.append(report)
            }
            if newReports.count >= 20 {
                break
            }
        }

        // 既存データと重複排除して結合
        var combined = newReports
        for item in existingReports where !combined.contains(where: { $0.id == item.id || $0.title == item.title }) {
            combined.append(item)
        }
        AppLogger.network.info("SNS速報の更新完了: 新規 \(newReports.count) 件 / 合計 \(combined.count) 件")
        return combined
    }

    // MARK: - Text Analysis (Unit Testable)

    private static let accidentKeywords = ["事故", "衝突", "追突", "玉突き", "横転", "はねられ", "通行止", "接触"]
    private static let excludeKeywords = ["放送事故", "原発事故", "医療事故", "事故物件", "ガチャ", "ゲーム"]
    private static let invalidLocationWords = [
        "事故", "交通", "警察", "病院", "現場", "車線", "道路", "高速", "交差点",
        "運転", "男性", "女性", "死亡", "重傷", "軽傷", "意識", "搬送", "逮捕",
        "発生", "衝突", "追突", "通行", "規制", "渋滞", "車両", "乗用", "貨物"
    ]

    /// 投稿テキストが実際の道路交通事故に関する内容かどうかを判定する。
    static func isTrafficAccidentRelated(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if excludeKeywords.contains(where: { text.contains($0) }) {
            return false
        }
        return accidentKeywords.contains(where: { text.contains($0) })
    }

    /// 投稿テキストから日本の地名（都道府県＋市区町村など）を抽出する。
    static func extractJapaneseLocation(from text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let normalized = text.replacingOccurrences(of: "東京・", with: "東京都")
        let prefList = "北海道|青森県|岩手県|宮城県|秋田県|山形県|福島県|茨城県|栃木県|群馬県|埼玉県|千葉県|東京都|神奈川県|新潟県|富山県|石川県|福井県|山梨県|長野県|岐阜県|静岡県|愛知県|三重県|滋賀県|京都府|大阪府|兵庫県|奈良県|和歌山県|鳥取県|島根県|岡山県|広島県|山口県|徳島県|香川県|愛媛県|高知県|福岡県|佐賀県|長崎県|熊本県|大分県|宮崎県|鹿児島県|沖縄県"
        let patterns = [
            "((?:\(prefList))[一-龥]{1,6}市[一-龥]{1,5}区)",
            "((?:\(prefList))[^\\s、。！？「」『』（）()・]{1,10}?(?:市|区|町|村))",
            "([一-龥]{2,5}市[一-龥]{1,5}区)",
            "([一-龥]{2,6}(?:市|区|町|村))"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            let matches = regex.matches(in: normalized, range: nsRange)
            for match in matches {
                guard let range = Range(match.range(at: 1), in: normalized) else { continue }
                let candidate = String(normalized[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if invalidLocationWords.contains(where: { candidate.contains($0) }) {
                    continue
                }
                if candidate.count >= 3 {
                    return candidate
                }
            }
        }
        return nil
    }

    /// 投稿本文から事故カテゴリラベルを推定する。
    static func inferCategory(from text: String) -> String {
        if text.contains("歩行者") || text.contains("はねられ") {
            return "人対車両（未確認）"
        }
        if text.contains("単独") || text.contains("ガードレール") || text.contains("電柱") {
            return "車両単独（未確認）"
        }
        if text.contains("踏切") || text.contains("列車") {
            return "列車・踏切（未確認）"
        }
        return "車両相互・その他（未確認）"
    }

    // MARK: - Free Public Endpoints

    private struct RawSNSPost: Sendable {
        let text: String
        let postedAt: String
        let sourceName: String
        let sourceType: String
        let url: String
    }

    private func fetchMastodonTagPosts() async -> [RawSNSPost] {
        guard let encodedTag = "交通事故".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://mstdn.jp/api/v1/timelines/tag/\(encodedTag)?limit=15") else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6.0
        request.setValue("TrafficAccidentCheckApp/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }
            return array.compactMap { item -> RawSNSPost? in
                guard let content = item["content"] as? String else { return nil }
                let plainText = content.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let createdAt = (item["created_at"] as? String) ?? ""
                let postURL = (item["url"] as? String) ?? "https://mstdn.jp"
                let account = item["account"] as? [String: Any]
                let acct = (account?["acct"] as? String) ?? "mstdn.jp"
                return RawSNSPost(
                    text: plainText,
                    postedAt: createdAt,
                    sourceName: "SNS (Mastodon @\(acct))",
                    sourceType: "sns_mastodon",
                    url: postURL
                )
            }
        } catch {
            AppLogger.logError(AppLogger.network, context: "Mastodon公開タグ取得エラー", error: error)
            return []
        }
    }

    private func fetchGoogleNewsRSSPosts() async -> [RawSNSPost] {
        var components = URLComponents(string: "https://news.google.com/rss/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: "交通事故 交差点 OR 国道 when:3d"),
            URLQueryItem(name: "hl", value: "ja"),
            URLQueryItem(name: "gl", value: "JP"),
            URLQueryItem(name: "ceid", value: "JP:ja")
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6.0
        request.setValue("TrafficAccidentCheckApp/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let xmlString = String(data: data, encoding: .utf8) else {
                return []
            }
            return Self.parseSimpleRSSItems(xmlString)
        } catch {
            AppLogger.logError(AppLogger.network, context: "GoogleニュースRSS取得エラー", error: error)
            return []
        }
    }

    private static func parseSimpleRSSItems(_ xml: String) -> [RawSNSPost] {
        var results: [RawSNSPost] = []
        let itemBlocks = xml.components(separatedBy: "<item>").dropFirst().prefix(20)
        for block in itemBlocks {
            let title = extractXMLTag("title", in: block) ?? ""
            let link = extractXMLTag("link", in: block) ?? "https://news.google.com"
            let pubDate = extractXMLTag("pubDate", in: block) ?? ""
            let source = extractXMLTag("source", in: block) ?? "速報"
            if !title.isEmpty {
                results.append(
                    RawSNSPost(
                        text: title,
                        postedAt: pubDate,
                        sourceName: "SNS・速報 (\(source))",
                        sourceType: "sns_news",
                        url: link
                    )
                )
            }
        }
        return results
    }

    private static func extractXMLTag(_ tag: String, in text: String) -> String? {
        let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
            .replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 国土地理院の無料住所検索APIで地名を緯度経度に変換する。
    private func geocodeWithGSI(placeName: String) async -> CLLocationCoordinate2D? {
        guard let encoded = placeName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://msearch.gsi.go.jp/address-search/AddressSearch?q=\(encoded)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        request.setValue("TrafficAccidentCheckApp/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = array.first,
                  let geometry = first["geometry"] as? [String: Any],
                  let coords = geometry["coordinates"] as? [Double],
                  coords.count >= 2 else {
                return nil
            }
            let lon = coords[0]
            let lat = coords[1]
            guard (20.0...46.0).contains(lat), (122.0...154.0).contains(lon) else {
                return nil
            }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } catch {
            AppLogger.logError(AppLogger.network, context: "国土地理院APIジオコーディングエラー (\(placeName))", error: error)
            return nil
        }
    }
}
