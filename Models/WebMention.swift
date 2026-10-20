import Foundation

/// ネット上でその店に言及しているページ1件
struct WebMention: Codable, Equatable, Identifiable {
    var id: String { url }
    let title: String
    let url: String
    let domain: String
    let snippet: String
    let kind: Kind

    /// 言及の種類
    /// 「本物の口コミ」として数えるのは genuine のみ。
    /// promotional（広告・タイアップ・プレスリリース）は評価に使わず、media（テレビ・ニュース）は「すでに有名」の根拠として扱う
    enum Kind: String, Codable, CaseIterable {
        /// ブログ・SNS・個人投稿など、第三者が自分の意思で書いたもの
        case genuine
        /// 食べログ・Retty などの掲載サイト（店の存在確認にはなるが口コミとしては数えない）
        case listing
        /// テレビ・新聞・雑誌・ニュースサイト
        case media
        /// プレスリリース・PR・タイアップ・広告型の掲載サイト
        case promotional
        /// 店の公式サイト・SNS（自己申告なので口コミではない）
        case official
        /// 分類できなかったもの
        case other

        var label: String {
            switch self {
            case .genuine: return "口コミ"
            case .listing: return "掲載サイト"
            case .media: return "メディア"
            case .promotional: return "PR・広告"
            case .official: return "公式"
            case .other: return "その他"
            }
        }
    }
}

/// 掲載サイトの点数（食べログなど）。Google とは別の評価源として使う
struct ListingRating: Codable, Equatable {
    /// サイト名（例：食べログ）
    let site: String
    /// 点数（食べログは 5点満点・小数2桁）
    let score: Double
    /// 口コミ件数（取れた場合）
    let reviewCount: Int?
    let url: String
}

/// 1店舗分のネット言及の集計
struct WebMentionSummary: Codable, Equatable {
    /// 取得日時（キャッシュの有効期限判定に使う）
    let fetchedAt: Date
    /// 検索に使ったクエリ
    let query: String
    /// 種類ごとの件数（ドメイン単位で重複を除いた数）
    let counts: [WebMention.Kind: Int]
    /// 表示用の言及（本物の口コミを優先、最大10件）
    let mentions: [WebMention]
    /// 掲載サイトから読み取れた点数（食べログなど）
    let listingRatings: [ListingRating]

    var genuineCount: Int { counts[.genuine] ?? 0 }
    var mediaCount: Int { counts[.media] ?? 0 }
    var promotionalCount: Int { counts[.promotional] ?? 0 }
    var listingCount: Int { counts[.listing] ?? 0 }

    /// 本物の口コミとして表示する言及
    var genuineMentions: [WebMention] { mentions.filter { $0.kind == .genuine } }

    /// 食べログの点数（読み取れた場合）
    var tabelogRating: ListingRating? {
        listingRatings.first { $0.site == ListingRating.tabelogSite }
    }

    // Dictionary のキーが enum だと JSON ではキーが文字列にならないため、文字列キーに変換して保存する
    enum CodingKeys: String, CodingKey {
        case fetchedAt, query, counts, mentions, listingRatings
    }

    init(
        fetchedAt: Date,
        query: String,
        counts: [WebMention.Kind: Int],
        mentions: [WebMention],
        listingRatings: [ListingRating] = []
    ) {
        self.fetchedAt = fetchedAt
        self.query = query
        self.counts = counts
        self.mentions = mentions
        self.listingRatings = listingRatings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)
        query = try c.decode(String.self, forKey: .query)
        mentions = try c.decodeIfPresent([WebMention].self, forKey: .mentions) ?? []
        listingRatings = try c.decodeIfPresent([ListingRating].self, forKey: .listingRatings) ?? []
        let raw = try c.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
        var converted: [WebMention.Kind: Int] = [:]
        for (key, value) in raw {
            if let kind = WebMention.Kind(rawValue: key) {
                converted[kind] = value
            }
        }
        counts = converted
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fetchedAt, forKey: .fetchedAt)
        try c.encode(query, forKey: .query)
        try c.encode(mentions, forKey: .mentions)
        try c.encode(listingRatings, forKey: .listingRatings)
        var raw: [String: Int] = [:]
        for (kind, value) in counts {
            raw[kind.rawValue] = value
        }
        try c.encode(raw, forKey: .counts)
    }
}

extension ListingRating {
    static let tabelogSite = "食べログ"
}
