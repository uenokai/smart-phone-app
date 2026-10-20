import XCTest
@testable import LocalRecommend

final class SearchFilterTests: XCTestCase {

    // MARK: - 価格帯フィルター

    func testMatches_価格帯の範囲内なら通す() {
        var filter = SearchFilter()
        filter.minPriceLevel = 2
        filter.maxPriceLevel = 3

        XCTAssertTrue(filter.matches(makePlace(priceLevel: 2)))
        XCTAssertTrue(filter.matches(makePlace(priceLevel: 3)))
    }

    func testMatches_価格帯の範囲外なら除外する() {
        var filter = SearchFilter()
        filter.minPriceLevel = 2
        filter.maxPriceLevel = 3

        XCTAssertFalse(filter.matches(makePlace(priceLevel: 1)))
        XCTAssertFalse(filter.matches(makePlace(priceLevel: 4)))
    }

    func testMatches_価格情報がない店は除外しない() {
        var filter = SearchFilter()
        filter.minPriceLevel = 3
        filter.maxPriceLevel = 4

        XCTAssertTrue(filter.matches(makePlace(priceLevel: nil)))
    }

    // MARK: - 最低評価フィルター

    func testMatches_最低評価を下回る店は除外する() {
        var filter = SearchFilter()
        filter.minRating = 4.0

        XCTAssertFalse(filter.matches(makePlace(rating: 3.5)))
        XCTAssertTrue(filter.matches(makePlace(rating: 4.0)))
        XCTAssertTrue(filter.matches(makePlace(rating: 4.5)))
    }

    func testMatches_評価情報がない店は除外しない() {
        var filter = SearchFilter()
        filter.minRating = 4.0

        XCTAssertTrue(filter.matches(makePlace(rating: nil)))
    }

    // MARK: - 営業中フィルター

    func testMatches_営業中のみ指定で営業終了の店は除外する() {
        var filter = SearchFilter()
        filter.includeOpen = true
        let closed = makePlace(openingHours: OpeningHours(
            isOpen: false, weekday: nil, nextOpeningTime: nil, nextClosingTime: nil
        ))

        XCTAssertFalse(filter.matches(closed))
    }

    func testMatches_営業中のみ指定で営業中の店は通す() {
        var filter = SearchFilter()
        filter.includeOpen = true
        let open = makePlace(openingHours: OpeningHours(
            isOpen: true, weekday: nil, nextOpeningTime: nil, nextClosingTime: nil
        ))

        XCTAssertTrue(filter.matches(open))
    }

    func testMatches_営業時間が不明な店は除外しない() {
        var filter = SearchFilter()
        filter.includeOpen = true

        XCTAssertTrue(filter.matches(makePlace(openingHours: nil)))
    }

    func testMatches_営業中指定OFFなら営業終了の店も通す() {
        var filter = SearchFilter()
        filter.includeOpen = false
        let closed = makePlace(openingHours: OpeningHours(
            isOpen: false, weekday: nil, nextOpeningTime: nil, nextClosingTime: nil
        ))

        XCTAssertTrue(filter.matches(closed))
    }

    // MARK: - 営業状態・店名

    func testMatches_恒久閉店や一時休業の店は除外する() {
        let filter = SearchFilter()
        XCTAssertFalse(filter.matches(makePlace(businessStatus: "CLOSED_PERMANENTLY")))
        XCTAssertFalse(filter.matches(makePlace(businessStatus: "CLOSED_TEMPORARILY")))
        XCTAssertTrue(filter.matches(makePlace(businessStatus: "OPERATIONAL")))
        XCTAssertTrue(filter.matches(makePlace(businessStatus: nil)))
    }

    func testMatches_店名の絞り込みは部分一致で大文字小文字を区別しない() {
        var filter = SearchFilter()
        filter.name = "yamagoya"
        XCTAssertTrue(filter.matches(makePlace(name: "Cafe YAMAGOYA")))
        XCTAssertFalse(filter.matches(makePlace(name: "喫茶 山小屋")))
        filter.name = "   "
        XCTAssertTrue(filter.matches(makePlace(name: "喫茶 山小屋")), "空白だけなら絞り込まない")
    }

    // MARK: - デフォルト条件

    func testMatches_デフォルト条件では通常の店を通す() {
        let filter = SearchFilter()
        XCTAssertTrue(filter.matches(makePlace()))
    }

    func testDefault_検索半径は2kmで徹底度は標準() {
        let filter = SearchFilter()
        XCTAssertEqual(filter.maxDistance, 2.0)
        XCTAssertEqual(filter.thoroughness, .standard)
        XCTAssertEqual(filter.thoroughness.maxAPICalls, 8)
    }

    // MARK: - 旧バージョンとの互換

    func testDecode_旧バージョンのプリセットに無い項目は既定値で補う() throws {
        let legacy = """
        {"name":"","categories":["cafe"],"minPriceLevel":1,"maxPriceLevel":3,"minRating":4.0,"maxDistance":3.0,"tags":[],"includeOpen":false,"sortBy":"rating"}
        """
        let filter = try JSONDecoder().decode(SearchFilter.self, from: Data(legacy.utf8))

        XCTAssertEqual(filter.categories, [.cafe])
        XCTAssertEqual(filter.maxPriceLevel, 3)
        XCTAssertEqual(filter.maxDistance, 3.0)
        XCTAssertFalse(filter.includeOpen)
        XCTAssertEqual(filter.thoroughness, .standard)
    }

    func testCodable_往復しても値が変わらない() throws {
        var filter = SearchFilter()
        filter.name = "山小屋"
        filter.categories = [.bar]
        filter.thoroughness = .thorough
        filter.maxDistance = 1.5

        let data = try JSONEncoder().encode(filter)
        let decoded = try JSONDecoder().decode(SearchFilter.self, from: data)

        XCTAssertEqual(decoded, filter)
    }

    func testTasteProfile_旧バージョンの設定に無い項目は既定値で補う() throws {
        let legacy = """
        {"moodTags":["隠れ家"],"avoidTags":[],"hiddenGemWeight":0.5,"excludeChains":false,"maxReviewCount":100}
        """
        let profile = try JSONDecoder().decode(TasteProfile.self, from: Data(legacy.utf8))

        XCTAssertEqual(profile.moodTags, ["隠れ家"])
        XCTAssertEqual(profile.hiddenGemWeight, 0.5)
        XCTAssertFalse(profile.excludeChains)
        XCTAssertEqual(profile.maxReviewCount, 100)
        XCTAssertTrue(profile.hideKnownPlaces)
        XCTAssertTrue(profile.useWebMentions)
    }
}
