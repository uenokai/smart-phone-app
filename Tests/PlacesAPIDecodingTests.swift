import XCTest
@testable import LocalRecommend

/// Places API (New) のレスポンスをアプリのモデルへ変換できることを確認する（通信は行わない）
final class PlacesAPIDecodingTests: XCTestCase {

    private let nearbyJSON = """
    {
      "places": [
        {
          "id": "ChIJ_test_1",
          "displayName": { "text": "喫茶 山小屋", "languageCode": "ja" },
          "location": { "latitude": 35.658, "longitude": 139.701 },
          "formattedAddress": "日本、〒150-0043 東京都渋谷区道玄坂２丁目１２−３",
          "shortFormattedAddress": "道玄坂２丁目１２−３, 渋谷区",
          "types": ["cafe", "coffee_shop", "food", "point_of_interest", "establishment"],
          "primaryType": "cafe",
          "businessStatus": "OPERATIONAL",
          "googleMapsUri": "https://maps.google.com/?cid=123",
          "photos": [ { "name": "places/ChIJ_test_1/photos/abc", "widthPx": 1200, "heightPx": 800 } ],
          "rating": 4.6,
          "userRatingCount": 23,
          "priceLevel": "PRICE_LEVEL_MODERATE",
          "currentOpeningHours": { "openNow": true, "weekdayDescriptions": ["月曜日: 10時00分～19時00分"] }
        },
        {
          "id": "ChIJ_test_2",
          "displayName": { "text": "閉店した店", "languageCode": "ja" },
          "location": { "latitude": 35.659, "longitude": 139.702 },
          "types": ["restaurant"],
          "businessStatus": "CLOSED_PERMANENTLY"
        },
        {
          "id": "ChIJ_no_location",
          "displayName": { "text": "座標なし", "languageCode": "ja" }
        }
      ]
    }
    """

    private let detailsJSON = """
    {
      "id": "ChIJ_test_1",
      "displayName": { "text": "喫茶 山小屋", "languageCode": "ja" },
      "location": { "latitude": 35.658, "longitude": 139.701 },
      "formattedAddress": "日本、〒150-0043 東京都渋谷区道玄坂２丁目１２−３",
      "types": ["cafe"],
      "primaryType": "cafe",
      "businessStatus": "OPERATIONAL",
      "rating": 4.6,
      "userRatingCount": 23,
      "priceLevel": "PRICE_LEVEL_INEXPENSIVE",
      "regularOpeningHours": { "weekdayDescriptions": ["月曜日: 10時00分～19時00分", "火曜日: 定休日"] },
      "currentOpeningHours": { "openNow": false },
      "nationalPhoneNumber": "03-1234-5678",
      "websiteUri": "https://example.com/yamagoya",
      "editorialSummary": { "text": "路地裏の小さな喫茶店", "languageCode": "ja" },
      "reviews": [
        {
          "name": "places/ChIJ_test_1/reviews/r1",
          "rating": 5,
          "text": { "text": "常連さんが多い落ち着いた店", "languageCode": "ja" },
          "publishTime": "2026-09-01T12:34:56.123456Z",
          "authorAttribution": { "displayName": "太郎" }
        },
        {
          "name": "places/ChIJ_test_1/reviews/r2",
          "rating": 4,
          "originalText": { "text": "オープン前にご招待いただきました", "languageCode": "ja" },
          "publishTime": "2025-03-10T09:00:00Z"
        }
      ]
    }
    """

    func testNearbySearch_レスポンスをPlaceに変換できる() throws {
        let decoded = try JSONDecoder().decode(NearbySearchResponse.self, from: Data(nearbyJSON.utf8))
        let places = (decoded.places ?? []).compactMap { GooglePlacesService.convert($0) }

        XCTAssertEqual(places.count, 2, "座標の無い場所は扱えないので除かれる")

        let cafe = places[0]
        XCTAssertEqual(cafe.id, "ChIJ_test_1")
        XCTAssertEqual(cafe.name, "喫茶 山小屋")
        XCTAssertEqual(cafe.category, .cafe)
        XCTAssertEqual(cafe.latitude, 35.658)
        XCTAssertEqual(cafe.address, "道玄坂２丁目１２−３, 渋谷区", "短い住所を優先する")
        XCTAssertEqual(cafe.priceLevel, 2)
        XCTAssertEqual(cafe.rating, 4.6)
        XCTAssertEqual(cafe.userRatingsTotal, 23)
        XCTAssertEqual(cafe.openingHours?.isOpen, true)
        XCTAssertEqual(cafe.photoName, "places/ChIJ_test_1/photos/abc")
        XCTAssertEqual(cafe.googleMapsURL, "https://maps.google.com/?cid=123")
        XCTAssertTrue(cafe.isOperational)

        let closed = places[1]
        XCTAssertEqual(closed.category, .restaurant)
        XCTAssertFalse(closed.isOperational)
        XCTAssertFalse(SearchFilter().matches(closed), "恒久閉店の店は検索条件に合致しない")
    }

    func testNearbySearch_該当なしの空レスポンスを読める() throws {
        let decoded = try JSONDecoder().decode(NearbySearchResponse.self, from: Data("{}".utf8))
        XCTAssertNil(decoded.places)
    }

    func testDetails_口コミの本文と投稿日を読める() throws {
        let decoded = try JSONDecoder().decode(NewPlace.self, from: Data(detailsJSON.utf8))
        let place = try XCTUnwrap(GooglePlacesService.convert(decoded))

        XCTAssertEqual(place.priceLevel, 1)
        XCTAssertEqual(place.phoneNumber, "03-1234-5678")
        XCTAssertEqual(place.website, "https://example.com/yamagoya")
        XCTAssertEqual(place.editorialSummary, "路地裏の小さな喫茶店")
        XCTAssertEqual(place.openingHours?.isOpen, false)
        XCTAssertEqual(place.openingHours?.weekday?.count, 2)

        let reviews = try XCTUnwrap(place.reviewDetails)
        XCTAssertEqual(reviews.count, 2)
        XCTAssertEqual(reviews[0].rating, 5)
        XCTAssertEqual(reviews[0].text, "常連さんが多い落ち着いた店")
        XCTAssertEqual(reviews[0].authorName, "太郎")
        XCTAssertNotNil(reviews[0].publishedAt, "小数秒付きの日時を読める")
        XCTAssertFalse(reviews[0].isSuspected)
        XCTAssertEqual(reviews[1].text, "オープン前にご招待いただきました", "text が無ければ originalText を使う")
        XCTAssertNotNil(reviews[1].publishedAt, "小数秒無しの日時を読める")
        XCTAssertTrue(reviews[1].isSuspected)
        XCTAssertEqual(place.reviews?.count, 2)
        XCTAssertEqual(place.latestReviewDate, reviews[0].publishedAt)
    }

    func testPriceLevel_列挙値を1から4に変換する() {
        XCTAssertEqual(GooglePlacesService.priceLevelValue("PRICE_LEVEL_FREE"), 1)
        XCTAssertEqual(GooglePlacesService.priceLevelValue("PRICE_LEVEL_INEXPENSIVE"), 1)
        XCTAssertEqual(GooglePlacesService.priceLevelValue("PRICE_LEVEL_MODERATE"), 2)
        XCTAssertEqual(GooglePlacesService.priceLevelValue("PRICE_LEVEL_EXPENSIVE"), 3)
        XCTAssertEqual(GooglePlacesService.priceLevelValue("PRICE_LEVEL_VERY_EXPENSIVE"), 4)
        XCTAssertNil(GooglePlacesService.priceLevelValue("PRICE_LEVEL_UNSPECIFIED"))
        XCTAssertNil(GooglePlacesService.priceLevelValue(nil))
    }

    func testParseRFC3339_小数秒の有無どちらも読める() {
        XCTAssertNotNil(GooglePlacesService.parseRFC3339("2026-09-01T12:34:56.123456Z"))
        XCTAssertNotNil(GooglePlacesService.parseRFC3339("2026-09-01T12:34:56Z"))
        XCTAssertNil(GooglePlacesService.parseRFC3339("2026/09/01"))
    }

    func testAPIError_エラーレスポンスを読める() throws {
        let json = """
        { "error": { "code": 403, "message": "The request is missing a valid API key.", "status": "PERMISSION_DENIED" } }
        """
        let decoded = try JSONDecoder().decode(APIErrorEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.error.code, 403)
        XCTAssertEqual(decoded.error.status, "PERMISSION_DENIED")
    }

    func testNearbySearchRequest_JSONにフィールドが含まれる() throws {
        let request = NearbySearchRequest(
            includedTypes: ["cafe", "coffee_shop"],
            maxResultCount: 20,
            rankPreference: "DISTANCE",
            languageCode: "ja",
            regionCode: "JP",
            locationRestriction: .init(circle: .init(center: .init(latitude: 35.0, longitude: 139.0), radius: 500))
        )
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["includedTypes"] as? [String], ["cafe", "coffee_shop"])
        XCTAssertEqual(json["rankPreference"] as? String, "DISTANCE")
        let circle = (json["locationRestriction"] as? [String: Any])?["circle"] as? [String: Any]
        XCTAssertEqual(circle?["radius"] as? Double, 500)
    }

    func testMerge_詳細で取れた情報が検索結果に上書きされる() {
        var original = makePlace(id: "p", name: "検索結果の名前", rating: 4.0, userRatingsTotal: 10)
        original.photoName = "places/p/photos/1"
        original.webMentions = makeMentions(genuine: 2)
        var detail = makePlace(id: "p", name: "詳細の名前", rating: 4.2, userRatingsTotal: 12, reviewDetails: [makeReview("良い店")])
        detail.editorialSummary = "説明"

        let merged = GooglePlacesService.merge(original: original, detail: detail)

        XCTAssertEqual(merged.name, "詳細の名前")
        XCTAssertEqual(merged.rating, 4.2)
        XCTAssertEqual(merged.userRatingsTotal, 12)
        XCTAssertEqual(merged.reviewDetails?.count, 1)
        XCTAssertEqual(merged.editorialSummary, "説明")
        XCTAssertEqual(merged.photoName, "places/p/photos/1", "詳細に無い項目は元の値を残す")
        XCTAssertEqual(merged.webMentions?.genuineCount, 2, "ネット言及は検索結果側の値を保持する")
    }

    func testPlace_旧バージョンで保存したお気に入りをデコードできる() throws {
        // 新しい項目（primaryType など）が無い JSON
        let legacy = """
        {"id":"old","name":"古い店","category":"restaurant","latitude":35.0,"longitude":139.0,"address":"東京都","priceLevel":2,"rating":4.1,"userRatingsTotal":30,"openingHours":null,"website":null,"phoneNumber":null,"reviews":["良い"]}
        """
        let place = try JSONDecoder().decode(Place.self, from: Data(legacy.utf8))
        XCTAssertEqual(place.name, "古い店")
        XCTAssertNil(place.reviewDetails)
        XCTAssertTrue(place.isOperational)
    }
}
