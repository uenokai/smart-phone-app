import Foundation

/// Places API を呼ぶためのインターフェース（テストでは差し替える）
protocol PlacesSearching: Sendable {
    /// 指定した円の中の場所を検索する。1回の呼び出しで最大20件
    func searchNearby(
        center: GeoPoint,
        radiusMeters: Double,
        types: [String],
        rankByDistance: Bool,
        maxResults: Int
    ) async throws -> [Place]

    /// 口コミ本文・営業時間・連絡先を含む詳細を取得する
    func fetchDetails(placeId: String) async throws -> Place
}

/// Google Places API (New) との連携を行うサービス
///
/// 旧 Places API は 2026年10月以降、新規の Google Cloud プロジェクトでは有効化できなくなったため、
/// places.googleapis.com/v1 のエンドポイントを使う。
/// New API は返す項目を X-Goog-FieldMask で明示する必要があり、含めた項目の最高ランク（Pro / Enterprise / Enterprise + Atmosphere）で課金される。
final class GooglePlacesService: PlacesSearching, @unchecked Sendable {
    private let apiKey: String
    private let session: URLSession
    private let bundleIdentifier: String?
    private let languageCode = "ja"
    private let regionCode = "JP"

    static let placeholderKey = "YOUR_API_KEY_HERE"

    /// Nearby Search で取る項目（Enterprise ランク：評価・口コミ数・価格帯・営業中まで）
    /// 口コミ本文（Enterprise + Atmosphere）は上位の候補だけ Place Details で別途取る
    static let searchFieldMask = [
        "places.id", "places.displayName", "places.location",
        "places.formattedAddress", "places.shortFormattedAddress",
        "places.types", "places.primaryType", "places.businessStatus",
        "places.googleMapsUri", "places.photos",
        "places.rating", "places.userRatingCount", "places.priceLevel",
        "places.currentOpeningHours"
    ].joined(separator: ",")

    /// Place Details で取る項目（Enterprise + Atmosphere ランク：口コミ本文まで）
    static let detailsFieldMask = [
        "id", "displayName", "location",
        "formattedAddress", "shortFormattedAddress",
        "types", "primaryType", "businessStatus",
        "googleMapsUri", "photos",
        "rating", "userRatingCount", "priceLevel",
        "currentOpeningHours", "regularOpeningHours",
        "nationalPhoneNumber", "websiteUri",
        "editorialSummary", "reviews"
    ].joined(separator: ",")

    init(
        apiKey: String = Bundle.main.infoDictionary?["GOOGLE_PLACES_API_KEY"] as? String ?? "",
        session: URLSession = .shared,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.apiKey = apiKey
        self.session = session
        self.bundleIdentifier = bundleIdentifier
    }

    /// APIキーが設定済みか
    var isConfigured: Bool {
        !apiKey.isEmpty && apiKey != Self.placeholderKey
    }

    // MARK: - PlacesSearching

    func searchNearby(
        center: GeoPoint,
        radiusMeters: Double,
        types: [String],
        rankByDistance: Bool,
        maxResults: Int = 20
    ) async throws -> [Place] {
        guard isConfigured else { throw PlacesAPIError.missingAPIKey }
        guard let url = URL(string: "https://places.googleapis.com/v1/places:searchNearby") else {
            throw PlacesAPIError.invalidURL
        }

        let body = NearbySearchRequest(
            includedTypes: types,
            maxResultCount: min(max(maxResults, 1), 20),
            rankPreference: rankByDistance ? "DISTANCE" : "POPULARITY",
            languageCode: languageCode,
            regionCode: regionCode,
            locationRestriction: .init(circle: .init(
                center: .init(latitude: center.latitude, longitude: center.longitude),
                radius: min(max(radiusMeters, 1), 50_000)
            ))
        )

        var request = makeRequest(url: url, fieldMask: Self.searchFieldMask)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await perform(request)
        let decoded = try decode(NearbySearchResponse.self, from: data)
        return (decoded.places ?? []).compactMap { Self.convert($0) }
    }

    func fetchDetails(placeId: String) async throws -> Place {
        guard isConfigured else { throw PlacesAPIError.missingAPIKey }
        guard let url = URL(string: "https://places.googleapis.com/v1/places/\(placeId)") else {
            throw PlacesAPIError.invalidURL
        }
        var request = makeRequest(url: url, fieldMask: Self.detailsFieldMask)
        request.httpMethod = "GET"
        request.url = url.appendingQueryItems([
            URLQueryItem(name: "languageCode", value: languageCode),
            URLQueryItem(name: "regionCode", value: regionCode)
        ])

        let data = try await perform(request)
        let decoded = try decode(NewPlace.self, from: data)
        guard let place = Self.convert(decoded) else {
            throw PlacesAPIError.invalidResponse(statusCode: 200)
        }
        return place
    }

    // MARK: - Photos

    /// 写真の実体URLを取得する
    /// iOS のバンドルID制限付きキーはヘッダーで渡す必要があるため、リダイレクトを追わず JSON（photoUri）で受け取り、
    /// 返ってきた googleusercontent の URL を AsyncImage に渡す
    func fetchPhotoURL(photoName: String, maxWidthPx: Int = 800) async throws -> URL {
        guard isConfigured else { throw PlacesAPIError.missingAPIKey }
        guard var components = URLComponents(string: "https://places.googleapis.com/v1/\(photoName)/media") else {
            throw PlacesAPIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "maxWidthPx", value: "\(min(max(maxWidthPx, 1), 4800))"),
            URLQueryItem(name: "skipHttpRedirect", value: "true")
        ]
        guard let url = components.url else { throw PlacesAPIError.invalidURL }
        var request = makeRequest(url: url, fieldMask: nil)
        request.httpMethod = "GET"
        let data = try await perform(request)
        let decoded = try decode(PhotoMediaResponse.self, from: data)
        guard let photoURL = URL(string: decoded.photoUri) else {
            throw PlacesAPIError.invalidURL
        }
        return photoURL
    }

    // MARK: - Enrichment

    /// 検索結果の上位に詳細情報（口コミ本文など）を付加する
    /// Details API の呼び出し回数を抑えるため上位のみを対象とし、取得に失敗した場合は元の情報をそのまま使う
    func enrichPlacesWithDetails(_ places: [Place], limit: Int = 15) async -> [Place] {
        var enriched = places
        await withTaskGroup(of: (Int, Place)?.self) { group in
            for (index, place) in places.prefix(limit).enumerated() {
                group.addTask {
                    guard let detail = try? await self.fetchDetails(placeId: place.id) else {
                        return nil
                    }
                    return (index, Self.merge(original: place, detail: detail))
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

    /// Nearby Search の結果をベースに、Details で取れた情報を上書きマージする
    static func merge(original: Place, detail: Place) -> Place {
        var merged = Place(
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
        merged.primaryType = detail.primaryType ?? original.primaryType
        merged.businessStatus = detail.businessStatus ?? original.businessStatus
        merged.googleMapsURL = detail.googleMapsURL ?? original.googleMapsURL
        merged.photoName = detail.photoName ?? original.photoName
        merged.reviewDetails = detail.reviewDetails ?? original.reviewDetails
        merged.editorialSummary = detail.editorialSummary ?? original.editorialSummary
        merged.webMentions = original.webMentions
        return merged
    }

    // MARK: - Private

    private func makeRequest(url: URL, fieldMask: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        if let fieldMask = fieldMask {
            request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        }
        // iOS アプリ制限付きのキーを使う場合に必要
        if let bundleIdentifier = bundleIdentifier {
            request.setValue(bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PlacesAPIError.networkError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PlacesAPIError.invalidResponse(statusCode: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            // New API はエラーを {"error": {"code", "message", "status"}} で返す
            if let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw PlacesAPIError.apiError(status: apiError.error.status ?? "\(http.statusCode)", message: apiError.error.message ?? "")
            }
            throw PlacesAPIError.invalidResponse(statusCode: http.statusCode)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw PlacesAPIError.decodingError(error)
        }
    }

    // MARK: - Conversion

    /// New API のレスポンスをアプリのモデルに変換する。座標が無いものは扱えないので nil
    static func convert(_ raw: NewPlace) -> Place? {
        guard let location = raw.location else { return nil }
        let name = raw.displayName?.text ?? ""
        let types = raw.types ?? []
        var place = Place(
            id: raw.id,
            name: name,
            category: Place.PlaceCategory.from(types: types, primaryType: raw.primaryType),
            latitude: location.latitude,
            longitude: location.longitude,
            address: raw.shortFormattedAddress ?? raw.formattedAddress ?? "",
            priceLevel: priceLevelValue(raw.priceLevel),
            rating: raw.rating,
            userRatingsTotal: raw.userRatingCount,
            openingHours: convertOpeningHours(current: raw.currentOpeningHours, regular: raw.regularOpeningHours),
            website: raw.websiteUri,
            phoneNumber: raw.nationalPhoneNumber,
            reviews: raw.reviews?.compactMap { $0.text?.text ?? $0.originalText?.text }
        )
        place.primaryType = raw.primaryType
        place.businessStatus = raw.businessStatus
        place.googleMapsURL = raw.googleMapsUri
        place.photoName = raw.photos?.first?.name
        place.editorialSummary = raw.editorialSummary?.text
        place.reviewDetails = raw.reviews?.map { review in
            PlaceReview(
                rating: review.rating.map { Int($0.rounded()) },
                text: review.text?.text ?? review.originalText?.text ?? "",
                publishedAt: review.publishTime.flatMap { parseRFC3339($0) },
                authorName: review.authorAttribution?.displayName
            )
        }
        return place
    }

    /// PRICE_LEVEL_* をアプリの 1〜4 に変換する（無料は最安扱い、未指定は nil）
    static func priceLevelValue(_ raw: String?) -> Int? {
        switch raw {
        case "PRICE_LEVEL_FREE", "PRICE_LEVEL_INEXPENSIVE": return 1
        case "PRICE_LEVEL_MODERATE": return 2
        case "PRICE_LEVEL_EXPENSIVE": return 3
        case "PRICE_LEVEL_VERY_EXPENSIVE": return 4
        default: return nil
        }
    }

    private static func convertOpeningHours(current: NewOpeningHours?, regular: NewOpeningHours?) -> OpeningHours? {
        guard current != nil || regular != nil else { return nil }
        return OpeningHours(
            isOpen: current?.openNow ?? true,
            weekday: regular?.weekdayDescriptions ?? current?.weekdayDescriptions,
            nextOpeningTime: nil,
            nextClosingTime: nil
        )
    }

    /// "2024-05-01T12:34:56.123456Z" と "2024-05-01T12:34:56Z" の両方を読む
    static func parseRFC3339(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

// MARK: - Request / Response Models (Places API (New))

struct NearbySearchRequest: Encodable {
    let includedTypes: [String]
    let maxResultCount: Int
    let rankPreference: String
    let languageCode: String
    let regionCode: String
    let locationRestriction: LocationRestriction

    struct LocationRestriction: Encodable {
        let circle: Circle
    }
    struct Circle: Encodable {
        let center: LatLng
        let radius: Double
    }
}

struct LatLng: Codable {
    let latitude: Double
    let longitude: Double
}

struct NearbySearchResponse: Decodable {
    /// 該当なしのときは {} が返り places キー自体が無い
    let places: [NewPlace]?
}

struct NewPlace: Decodable {
    let id: String
    let displayName: LocalizedText?
    let location: LatLng?
    let formattedAddress: String?
    let shortFormattedAddress: String?
    let types: [String]?
    let primaryType: String?
    let businessStatus: String?
    let googleMapsUri: String?
    let photos: [NewPhoto]?
    let rating: Double?
    let userRatingCount: Int?
    let priceLevel: String?
    let currentOpeningHours: NewOpeningHours?
    let regularOpeningHours: NewOpeningHours?
    let nationalPhoneNumber: String?
    let websiteUri: String?
    let editorialSummary: LocalizedText?
    let reviews: [NewReview]?
}

struct LocalizedText: Decodable {
    let text: String?
    let languageCode: String?
}

struct NewPhoto: Decodable {
    let name: String
    let widthPx: Int?
    let heightPx: Int?
}

struct NewOpeningHours: Decodable {
    let openNow: Bool?
    let weekdayDescriptions: [String]?
}

struct NewReview: Decodable {
    let rating: Double?
    let text: LocalizedText?
    let originalText: LocalizedText?
    let publishTime: String?
    let relativePublishTimeDescription: String?
    let authorAttribution: AuthorAttribution?

    struct AuthorAttribution: Decodable {
        let displayName: String?
        let uri: String?
    }
}

struct PhotoMediaResponse: Decodable {
    let name: String?
    let photoUri: String
}

struct APIErrorEnvelope: Decodable {
    let error: APIErrorBody
    struct APIErrorBody: Decodable {
        let code: Int?
        let message: String?
        let status: String?
    }
}

// MARK: - Errors

enum PlacesAPIError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse(statusCode: Int)
    case apiError(status: String, message: String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Google Places API キーが設定されていません（Info.plist の GOOGLE_PLACES_API_KEY）"
        case .invalidURL:
            return "不正なURLです"
        case .invalidResponse(let statusCode):
            return "APIレスポンスが無効です（HTTP \(statusCode)）"
        case .apiError(let status, let message):
            return "Google Places API エラー（\(status)）：\(message)"
        case .decodingError(let error):
            return "レスポンスのデコードに失敗：\(error.localizedDescription)"
        case .networkError(let error):
            return "ネットワークエラー：\(error.localizedDescription)"
        }
    }
}

// MARK: - URL helper

extension URL {
    func appendingQueryItems(_ items: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.queryItems = (components.queryItems ?? []) + items
        return components.url ?? self
    }
}
