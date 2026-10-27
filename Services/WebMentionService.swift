import Foundation

/// ネット検索エンジンのインターフェース（テストでは差し替える）
protocol WebSearching: Sendable {
    func search(query: String, count: Int) async throws -> [WebSearchResult]
}

/// Brave Search API クライアント
///
/// Google Custom Search JSON API は新規受付を終了したため、Brave Search API を使う。
/// 料金は Search プランで 1,000 件あたり $5、毎月 $5 分（約1,000件）の無料枠がある（2026年10月時点、要カード登録）。
final class BraveSearchClient: WebSearching, @unchecked Sendable {
    private let apiKey: String
    private let session: URLSession

    static let placeholderKey = "YOUR_BRAVE_API_KEY_HERE"

    init(
        apiKey: String = Bundle.main.infoDictionary?["BRAVE_SEARCH_API_KEY"] as? String ?? "",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.session = session
    }

    var isConfigured: Bool {
        !apiKey.isEmpty && apiKey != Self.placeholderKey
    }

    func search(query: String, count: Int = 20) async throws -> [WebSearchResult] {
        guard isConfigured else { throw WebSearchError.missingAPIKey }
        guard var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search") else {
            throw WebSearchError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "\(min(max(count, 1), 20))"),
            URLQueryItem(name: "country", value: "JP"),
            URLQueryItem(name: "search_lang", value: "jp"),
            URLQueryItem(name: "ui_lang", value: "ja-JP"),
            URLQueryItem(name: "safesearch", value: "off")
        ]
        guard let url = components.url else { throw WebSearchError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebSearchError.invalidResponse(statusCode: -1)
        }
        if http.statusCode == 429 {
            throw WebSearchError.rateLimited
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WebSearchError.invalidResponse(statusCode: http.statusCode)
        }
        let decoded = try JSONDecoder().decode(BraveSearchResponse.self, from: data)
        return (decoded.web?.results ?? []).map {
            WebSearchResult(title: $0.title ?? "", url: $0.url, description: $0.description ?? "")
        }
    }
}

struct BraveSearchResponse: Decodable {
    let web: Web?
    struct Web: Decodable {
        let results: [Item]?
    }
    struct Item: Decodable {
        let title: String?
        let url: String
        let description: String?
    }
}

enum WebSearchError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse(statusCode: Int)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Brave Search API キーが設定されていません（Info.plist の BRAVE_SEARCH_API_KEY）"
        case .invalidURL: return "不正なURLです"
        case .invalidResponse(let code): return "ネット検索のレスポンスが無効です（HTTP \(code)）"
        case .rateLimited: return "ネット検索の呼び出し上限に達しました"
        }
    }
}

/// 店ごとのネット言及の集計をファイルに保存し、一定期間は再検索しない
actor WebMentionCache {
    private var entries: [String: WebMentionSummary] = [:]
    private let fileURL: URL?
    private let ttl: TimeInterval
    private var loaded = false

    init(fileURL: URL? = WebMentionCache.defaultFileURL, ttl: TimeInterval = 14 * 24 * 3600) {
        self.fileURL = fileURL
        self.ttl = ttl
    }

    static var defaultFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("web_mentions.json")
    }

    func summary(for placeId: String, now: Date = Date()) -> WebMentionSummary? {
        loadIfNeeded()
        guard let entry = entries[placeId] else { return nil }
        guard now.timeIntervalSince(entry.fetchedAt) < ttl else {
            entries.removeValue(forKey: placeId)
            return nil
        }
        return entry
    }

    func store(_ summary: WebMentionSummary, for placeId: String) {
        loadIfNeeded()
        entries[placeId] = summary
        save()
    }

    func clear() {
        entries = [:]
        save()
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([String: WebMentionSummary].self, from: data)) ?? [:]
    }

    private func save() {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// 候補の店について、ネット上の言及を検索して集計する
///
/// 1店につき1回の検索で済ませ、結果はキャッシュする。検索に失敗した店は「情報なし」として扱い、検索全体は失敗させない
final class WebMentionService: @unchecked Sendable {
    private let client: WebSearching
    private let cache: WebMentionCache
    private let maxConcurrent: Int

    init(client: WebSearching, cache: WebMentionCache = WebMentionCache(), maxConcurrent: Int = 2) {
        self.client = client
        self.cache = cache
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// 指定した店のネット言及を集計して返す（placeId → 集計）
    func summaries(for places: [Place]) async -> [String: WebMentionSummary] {
        var results: [String: WebMentionSummary] = [:]
        var pending: [Place] = []

        for place in places {
            if let cached = await cache.summary(for: place.id) {
                results[place.id] = cached
            } else {
                pending.append(place)
            }
        }

        // 同時実行数を抑えて順に処理する（検索APIの呼び出し上限対策）
        var index = 0
        while index < pending.count {
            let batch = Array(pending[index..<min(index + maxConcurrent, pending.count)])
            index += batch.count
            await withTaskGroup(of: (String, WebMentionSummary?).self) { group in
                for place in batch {
                    group.addTask {
                        (place.id, await self.fetchSummary(for: place))
                    }
                }
                for await (id, summary) in group {
                    if let summary = summary {
                        results[id] = summary
                    }
                }
            }
        }
        return results
    }

    private func fetchSummary(for place: Place) async -> WebMentionSummary? {
        let query = WebMentionAnalyzer.buildQuery(placeName: place.name, address: place.address)
        let results: [WebSearchResult]
        do {
            results = try await client.search(query: query, count: 20)
        } catch WebSearchError.rateLimited {
            // 一度だけ待って再試行する
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let retried = try? await client.search(query: query, count: 20) else { return nil }
            results = retried
        } catch {
            return nil
        }
        let summary = WebMentionAnalyzer.summarize(
            results: results,
            query: query,
            placeName: place.name,
            officialWebsite: place.website
        )
        await cache.store(summary, for: place.id)
        return summary
    }
}
