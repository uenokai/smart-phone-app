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
