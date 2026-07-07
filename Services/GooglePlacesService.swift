import Foundation

/// Google Places API との連携を行うサービス
class GooglePlacesService {
    private let apiKey: String
    private let baseURL = "https://maps.googleapis.com/maps/api/place"
    private let session: URLSession

    init(apiKey: String = Bundle.main.infoDictionary?["GOOGLE_PLACES_API_KEY"] as? String ?? "") {
        self.apiKey = apiKey
        self.session = URLSession.shared
    }

    /// 指定座標の近くのお店を検索
    func searchPlaces(
        latitude: Double,
        longitude: Double,
        filter: SearchFilter
    ) async throws -> [Place] {
        guard !apiKey.isEmpty else {
            throw PlacesAPIError.missingAPIKey
        }

        let urlString = buildSearchURL(
            latitude: latitude,
            longitude: longitude,
            filter: filter
        )

        guard let url = URL(string: urlString) else {
            throw PlacesAPIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlacesAPIError.invalidResponse
        }

        let searchResult = try JSONDecoder().decode(PlacesSearchResponse.self, from: data)
        return searchResult.results.map { convertToPlace($0) }
    }

    /// お店の詳細情報を取得（口コミ本文・営業時間・連絡先を含む）
    func getPlaceDetails(placeId: String) async throws -> Place {
        guard !apiKey.isEmpty else {
            throw PlacesAPIError.missingAPIKey
        }

        // fields指定でAPI課金を抑えつつ、口コミ本文まで取得する
        let fields = "place_id,name,geometry,formatted_address,types,rating,user_ratings_total,price_level,opening_hours,website,formatted_phone_number,reviews"
        let urlString = "\(baseURL)/details/json?place_id=\(placeId)&fields=\(fields)&language=ja&key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            throw PlacesAPIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlacesAPIError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(PlaceDetailsResponse.self, from: data)
        return convertDetailToPlace(decoded.result)
    }

    /// 検索結果の上位に詳細情報（口コミ本文など）を付加する
    /// Details APIの呼び出し回数を抑えるため上位のみを対象とし、
    /// 取得に失敗した場合は元の情報をそのまま使う
    func enrichPlacesWithDetails(_ places: [Place], limit: Int = 15) async -> [Place] {
        var enriched = places
        await withTaskGroup(of: (Int, Place)?.self) { group in
            for (index, place) in places.prefix(limit).enumerated() {
                group.addTask {
                    guard let detail = try? await self.getPlaceDetails(placeId: place.id) else {
                        return nil
                    }
                    return (index, self.merge(original: place, detail: detail))
                }
            }
            for await result in group {
                if let (index, place) = result {
                    enriched[index] = place
                }
            }
        }
        return enriched
    }

    // MARK: - Private Methods

    private func buildSearchURL(
        latitude: Double,
        longitude: Double,
        filter: SearchFilter
    ) -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.googleapis.com"
        components.path = "/maps/api/place/nearbysearch/json"

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "location", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "radius", value: "\(Int(filter.maxDistance * 1000))"),
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "language", value: "ja"),
            URLQueryItem(name: "type", value: filter.categories.first?.rawValue ?? "restaurant"),
            // Google の price_level は 0〜4、アプリのUIは 1〜4（0=無料は範囲に含める）
            URLQueryItem(name: "minprice", value: "\(max(0, filter.minPriceLevel - 1))"),
            URLQueryItem(name: "maxprice", value: "\(min(4, filter.maxPriceLevel))")
        ]

        if filter.includeOpen {
            queryItems.append(URLQueryItem(name: "opennow", value: "true"))
        }

        if !filter.name.isEmpty {
            queryItems.append(URLQueryItem(name: "keyword", value: filter.name))
        }

        components.queryItems = queryItems
        return components.url?.absoluteString ?? ""
    }

    private func convertToPlace(_ result: PlacesSearchResult) -> Place {
        return Place(
            id: result.placeId,
            name: result.name,
            category: Place.PlaceCategory(rawValue: result.types.first ?? "") ?? .restaurant,
            latitude: result.geometry.location.lat,
            longitude: result.geometry.location.lng,
            address: result.vicinity ?? "",
            priceLevel: result.priceLevel,
            rating: result.rating,
            userRatingsTotal: result.userRatingsTotal,
            openingHours: result.openingHours?.openNow.map {
                OpeningHours(isOpen: $0, weekday: nil, nextOpeningTime: nil, nextClosingTime: nil)
            },
            website: nil,
            phoneNumber: nil,
            reviews: result.reviews?.map { $0.text }
        )
    }

    private func convertDetailToPlace(_ detail: PlaceDetail) -> Place {
        return Place(
            id: detail.placeId,
            name: detail.name,
            category: Place.PlaceCategory(rawValue: detail.types.first ?? "") ?? .restaurant,
            latitude: detail.geometry.location.lat,
            longitude: detail.geometry.location.lng,
            address: detail.formattedAddress ?? "",
            priceLevel: detail.priceLevel,
            rating: detail.rating,
            userRatingsTotal: detail.userRatingsTotal,
            openingHours: convertOpeningHours(detail.openingHours),
            website: detail.website,
            phoneNumber: detail.formattedPhoneNumber,
            reviews: detail.reviews?.map { $0.text }
        )
    }

    /// Nearby Searchの結果をベースに、Details APIで取れた情報を上書きマージする
    private func merge(original: Place, detail: Place) -> Place {
        return Place(
            id: original.id,
            name: detail.name.isEmpty ? original.name : detail.name,
            category: original.category,
            latitude: original.latitude,
            longitude: original.longitude,
            address: detail.address.isEmpty ? original.address : detail.address,
            priceLevel: detail.priceLevel ?? original.priceLevel,
            rating: detail.rating ?? original.rating,
            userRatingsTotal: detail.userRatingsTotal ?? original.userRatingsTotal,
            openingHours: detail.openingHours ?? original.openingHours,
            website: detail.website ?? original.website,
            phoneNumber: detail.phoneNumber ?? original.phoneNumber,
            reviews: detail.reviews ?? original.reviews
        )
    }

    private func convertOpeningHours(_ hours: PlaceOpeningHours?) -> OpeningHours? {
        guard let hours = hours else { return nil }
        return OpeningHours(
            isOpen: hours.openNow ?? false,
            weekday: hours.weekdayText,
            nextOpeningTime: nil,
            nextClosingTime: nil
        )
    }
}

// MARK: - API Response Models

struct PlacesSearchResponse: Codable {
    let results: [PlacesSearchResult]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case results
        case nextPageToken = "next_page_token"
    }
}

struct PlacesSearchResult: Codable {
    let placeId: String
    let name: String
    let geometry: PlacesGeometry
    let vicinity: String?
    let types: [String]
    let rating: Double?
    let userRatingsTotal: Int?
    let priceLevel: Int?
    let openingHours: PlacesOpeningHours?
    let reviews: [PlacesReview]?

    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case name, geometry, vicinity, types, rating
        case userRatingsTotal = "user_ratings_total"
        case priceLevel = "price_level"
        case openingHours = "opening_hours"
        case reviews
    }
}

struct PlaceDetailsResponse: Codable {
    let result: PlaceDetail
}

struct PlaceDetail: Codable {
    let placeId: String
    let name: String
    let geometry: PlacesGeometry
    let formattedAddress: String?
    let types: [String]
    let rating: Double?
    let userRatingsTotal: Int?
    let priceLevel: Int?
    let openingHours: PlaceOpeningHours?
    let website: String?
    let formattedPhoneNumber: String?
    let reviews: [PlacesReview]?

    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case name, geometry
        case formattedAddress = "formatted_address"
        case types, rating
        case userRatingsTotal = "user_ratings_total"
        case priceLevel = "price_level"
        case openingHours = "opening_hours"
        case website
        case formattedPhoneNumber = "formatted_phone_number"
        case reviews
    }
}

struct PlacesGeometry: Codable {
    let location: PlacesLocation
}

struct PlacesLocation: Codable {
    let lat: Double
    let lng: Double
}

struct PlacesOpeningHours: Codable {
    let openNow: Bool?
    let weekdayText: [String]?

    enum CodingKeys: String, CodingKey {
        case openNow = "open_now"
        case weekdayText = "weekday_text"
    }
}

struct PlaceOpeningHours: Codable {
    let openNow: Bool?
    let weekdayText: [String]?

    enum CodingKeys: String, CodingKey {
        case openNow = "open_now"
        case weekdayText = "weekday_text"
    }
}

struct PlacesReview: Codable {
    let text: String
}

// MARK: - Errors

enum PlacesAPIError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Google Places API キーが設定されていません"
        case .invalidURL:
            return "不正なURLです"
        case .invalidResponse:
            return "APIレスポンスが無効です"
        case .decodingError(let error):
            return "レスポンスのデコードに失敗：\(error)"
        case .networkError(let error):
            return "ネットワークエラー：\(error)"
        }
    }
}
