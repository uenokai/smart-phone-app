import Foundation

/// お店またはスポットを表すデータモデル
struct Place: Identifiable, Codable {
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

    enum PlaceCategory: String, Codable, CaseIterable {
        case restaurant = "restaurant"
        case cafe = "cafe"
        case bar = "bar"
        case touristAttraction = "tourist_attraction"
        case museum = "museum"
        case park = "park"
    }
}

struct OpeningHours: Codable {
    let isOpen: Bool
    let weekday: [String]?
    let nextOpeningTime: Date?
    let nextClosingTime: Date?
}

/// 検索フィルター条件
struct SearchFilter: Codable {
    var name: String = ""
    var categories: [Place.PlaceCategory] = [.restaurant]
    var minPriceLevel: Int = 1
    var maxPriceLevel: Int = 4
    var minRating: Double = 0.0
    var maxDistance: Double = 5.0 // km
    var tags: [String] = []
    var includeOpen: Bool = true
    var sortBy: SortOption = .distance

    enum SortOption: String, Codable {
        case distance = "distance"
        case rating = "rating"
        case name = "name"
    }
}

extension SearchFilter {
    /// 取得済みデータに対して適用するクライアント側フィルター
    /// （Nearby Search APIだけでは絞り込めない条件をここで判定する）
    /// 情報が欠落している場合（価格・評価・営業時間が不明）は除外しない
    func matches(_ place: Place) -> Bool {
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
