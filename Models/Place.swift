import Foundation

/// お店またはスポットを表すデータモデル
struct Place: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let category: PlaceCategory
    let latitude: Double
    let longitude: Double
    let address: String
    let priceLevel: Int? // 1-4
    let rating: Double? // 0.0-5.0
    let userRatingsTotal: Int? // 口コミ数（少ないほど「まだ知られていない」場所）
    let openingHours: OpeningHours?
    let website: String?
    let phoneNumber: String?
    let reviews: [String]? // 口コミのスニペット

    // 以下は Places API (New) 移行時に追加した項目。
    // 旧バージョンで保存したお気に入り（UserDefaults）もデコードできるよう、すべて省略可能にしている。
    /// Googleが付けた主カテゴリ（例: ramen_restaurant）
    var primaryType: String? = nil
    /// 営業状態（OPERATIONAL / CLOSED_TEMPORARILY / CLOSED_PERMANENTLY / FUTURE_OPENING）
    var businessStatus: String? = nil
    /// Googleマップ上のページ
    var googleMapsURL: String? = nil
    /// 先頭の写真のリソース名（places/.../photos/...）。写真本体は別途取得する
    var photoName: String? = nil
    /// 口コミの詳細（評価・本文・投稿日）。有益判定で使う
    var reviewDetails: [PlaceReview]? = nil
    /// Googleの編集部による一言説明
    var editorialSummary: String? = nil
    /// ネット上の言及の集計結果（取得後に付与される）
    var webMentions: WebMentionSummary? = nil

    enum PlaceCategory: String, Codable, CaseIterable {
        case restaurant = "restaurant"
        case cafe = "cafe"
        case bar = "bar"
        case touristAttraction = "tourist_attraction"
        case museum = "museum"
        case park = "park"

        /// Places API (New) の includedTypes に渡す型名
        var includedTypes: [String] {
            switch self {
            case .restaurant: return ["restaurant"]
            case .cafe: return ["cafe", "coffee_shop"]
            case .bar: return ["bar"]
            case .touristAttraction: return ["tourist_attraction"]
            case .museum: return ["museum"]
            case .park: return ["park"]
            }
        }

        var label: String {
            switch self {
            case .restaurant: return "レストラン"
            case .cafe: return "カフェ"
            case .bar: return "バー"
            case .touristAttraction: return "観光地"
            case .museum: return "博物館"
            case .park: return "公園"
            }
        }

        /// Google の types 配列からアプリ内カテゴリを決める
        static func from(types: [String], primaryType: String?) -> PlaceCategory {
            let all = Set(types + [primaryType].compactMap { $0 })
            if !all.isDisjoint(with: ["cafe", "coffee_shop"]) { return .cafe }
            if all.contains("bar") { return .bar }
            if all.contains("museum") { return .museum }
            if all.contains("park") { return .park }
            if all.contains("tourist_attraction") { return .touristAttraction }
            return .restaurant
        }
    }

    /// 営業中（恒久閉店・一時休業ではない）か。不明な場合は営業中と見なす
    var isOperational: Bool {
        guard let status = businessStatus else { return true }
        return status == "OPERATIONAL" || status == "BUSINESS_STATUS_UNSPECIFIED"
    }

    /// 取得できた口コミのうち最も新しい投稿日
    var latestReviewDate: Date? {
        reviewDetails?.compactMap { $0.publishedAt }.max()
    }
}

/// Google の口コミ1件
struct PlaceReview: Codable, Equatable {
    let rating: Int?
    let text: String
    let publishedAt: Date?
    let authorName: String?

    /// 招待・モニター・PR などの表記があり「本物の口コミ」と見なせないもの
    var isSuspected: Bool {
        ReviewAuthenticity.isSuspectedPromotional(text)
    }
}

struct OpeningHours: Codable, Equatable {
    let isOpen: Bool
    let weekday: [String]?
    let nextOpeningTime: Date?
    let nextClosingTime: Date?
}

/// 検索フィルター条件
struct SearchFilter: Codable, Equatable {
    var name: String = ""
    var categories: [Place.PlaceCategory] = [.restaurant]
    var minPriceLevel: Int = 1
    var maxPriceLevel: Int = 4
    var minRating: Double = 0.0
    /// 検索半径（km）。都内は店の密度が高く、広げるほど取りこぼしが増えるため既定は2km
    var maxDistance: Double = 2.0
    var tags: [String] = []
    var includeOpen: Bool = true
    var sortBy: SortOption = .distance
    /// 候補集めの徹底度（API呼び出し回数の上限）
    var thoroughness: Thoroughness = .standard

    enum SortOption: String, Codable {
        case distance = "distance"
        case rating = "rating"
        case name = "name"
    }

    /// 候補集めにどれだけAPI呼び出しを使うか
    /// 範囲を小さな円に分けて距離順で取得するため、回数が多いほど人気店に埋もれた店まで拾える
    enum Thoroughness: String, Codable, CaseIterable {
        case quick = "quick"
        case standard = "standard"
        case thorough = "thorough"

        var maxAPICalls: Int {
            switch self {
            case .quick: return 4
            case .standard: return 8
            case .thorough: return 16
            }
        }

        var label: String {
            switch self {
            case .quick: return "速い"
            case .standard: return "標準"
            case .thorough: return "徹底"
            }
        }
    }

    init() {}

    // 旧バージョンで保存したプリセットには thoroughness が無いため、欠けている項目は既定値で補う
    enum CodingKeys: String, CodingKey {
        case name, categories, minPriceLevel, maxPriceLevel, minRating, maxDistance, tags, includeOpen, sortBy, thoroughness
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        categories = try c.decodeIfPresent([Place.PlaceCategory].self, forKey: .categories) ?? [.restaurant]
        minPriceLevel = try c.decodeIfPresent(Int.self, forKey: .minPriceLevel) ?? 1
        maxPriceLevel = try c.decodeIfPresent(Int.self, forKey: .maxPriceLevel) ?? 4
        minRating = try c.decodeIfPresent(Double.self, forKey: .minRating) ?? 0.0
        maxDistance = try c.decodeIfPresent(Double.self, forKey: .maxDistance) ?? 2.0
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        includeOpen = try c.decodeIfPresent(Bool.self, forKey: .includeOpen) ?? true
        sortBy = try c.decodeIfPresent(SortOption.self, forKey: .sortBy) ?? .distance
        thoroughness = try c.decodeIfPresent(Thoroughness.self, forKey: .thoroughness) ?? .standard
    }
}

extension SearchFilter {
    /// 取得済みデータに対して適用するクライアント側フィルター
    /// （Nearby Search (New) は価格帯・最低評価・営業中の絞り込みに対応していないためここで判定する）
    /// 情報が欠落している場合（価格・評価・営業時間が不明）は除外しない
    func matches(_ place: Place) -> Bool {
        if !place.isOperational {
            return false
        }
        let keyword = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty && !place.name.localizedCaseInsensitiveContains(keyword) {
            return false
        }
        if let priceLevel = place.priceLevel,
           priceLevel < minPriceLevel || priceLevel > maxPriceLevel {
            return false
        }
        if minRating > 0, let rating = place.rating, rating < minRating {
            return false
        }
        if includeOpen, let hours = place.openingHours, !hours.isOpen {
            return false
        }
        return true
    }
}
