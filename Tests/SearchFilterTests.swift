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

    // MARK: - デフォルト条件

    func testMatches_デフォルト条件では通常の店を通す() {
        let filter = SearchFilter()
        XCTAssertTrue(filter.matches(makePlace()))
    }
}
