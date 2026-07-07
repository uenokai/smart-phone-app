import XCTest
@testable import LocalRecommend

final class RecommendationEngineTests: XCTestCase {

    // MARK: - 穴場スコア

    func testHiddenGemScore_高評価で口コミが少ない店は高評価で口コミが多い店よりスコアが高い() {
        let hiddenGem = makePlace(rating: 4.5, userRatingsTotal: 40)
        let famous = makePlace(rating: 4.5, userRatingsTotal: 450)

        XCTAssertGreaterThan(
            RecommendationEngine.hiddenGemScore(for: hiddenGem),
            RecommendationEngine.hiddenGemScore(for: famous)
        )
    }

    func testHiddenGemScore_口コミ500件以上はメジャー扱いでスコアゼロ() {
        let major = makePlace(rating: 5.0, userRatingsTotal: 500)
        XCTAssertEqual(RecommendationEngine.hiddenGemScore(for: major), 0)
    }

    func testHiddenGemScore_評価3以下はスコアゼロ() {
        let lowRated = makePlace(rating: 3.0, userRatingsTotal: 10)
        XCTAssertEqual(RecommendationEngine.hiddenGemScore(for: lowRated), 0)
    }

    func testHiddenGemScore_口コミ5件未満は信頼度が低いため割り引かれる() {
        let fewReviews = makePlace(rating: 4.5, userRatingsTotal: 4)
        let enoughReviews = makePlace(rating: 4.5, userRatingsTotal: 5)

        XCTAssertLessThan(
            RecommendationEngine.hiddenGemScore(for: fewReviews),
            RecommendationEngine.hiddenGemScore(for: enoughReviews)
        )
    }

    func testHiddenGemScore_評価なしはスコアゼロ() {
        let noRating = makePlace(rating: nil, userRatingsTotal: 10)
        XCTAssertEqual(RecommendationEngine.hiddenGemScore(for: noRating), 0)
    }

    // MARK: - チェーン店判定

    func testIsLikelyChain_チェーン店名を含む店はチェーンと判定される() {
        XCTAssertTrue(RecommendationEngine.isLikelyChain(makePlace(name: "スターバックス 渋谷店")))
        XCTAssertTrue(RecommendationEngine.isLikelyChain(makePlace(name: "マクドナルド 新宿西口店")))
    }

    func testIsLikelyChain_個人店はチェーンと判定されない() {
        XCTAssertFalse(RecommendationEngine.isLikelyChain(makePlace(name: "喫茶 山小屋")))
    }

    // MARK: - ランキング

    func testRank_チェーン除外ONならチェーン店が結果から消える() {
        var profile = TasteProfile()
        profile.excludeChains = true
        let places = [
            makePlace(name: "スターバックス 渋谷店", rating: 4.0, userRatingsTotal: 100),
            makePlace(name: "喫茶 山小屋", rating: 4.0, userRatingsTotal: 100)
        ]

        let ranked = RecommendationEngine.rank(places, profile: profile)

        XCTAssertEqual(ranked.map { $0.name }, ["喫茶 山小屋"])
    }

    func testRank_口コミ数の上限を超える店は除外される() {
        var profile = TasteProfile()
        profile.excludeChains = false
        profile.maxReviewCount = 100
        let places = [
            makePlace(name: "有名店", rating: 4.5, userRatingsTotal: 300),
            makePlace(name: "穴場店", rating: 4.5, userRatingsTotal: 50)
        ]

        let ranked = RecommendationEngine.rank(places, profile: profile)

        XCTAssertEqual(ranked.map { $0.name }, ["穴場店"])
    }

    func testRank_穴場重視なら口コミの少ない店が上位に来る() {
        var profile = TasteProfile()
        profile.excludeChains = false
        profile.hiddenGemWeight = 1.0
        let places = [
            makePlace(name: "有名店", rating: 4.6, userRatingsTotal: 400),
            makePlace(name: "穴場店", rating: 4.4, userRatingsTotal: 30)
        ]

        let ranked = RecommendationEngine.rank(places, profile: profile)

        XCTAssertEqual(ranked.first?.name, "穴場店")
    }

    func testRank_評価重視なら評価の高い店が上位に来る() {
        var profile = TasteProfile()
        profile.excludeChains = false
        profile.hiddenGemWeight = 0.0
        let places = [
            makePlace(name: "評価4.2の店", rating: 4.2, userRatingsTotal: 30),
            makePlace(name: "評価4.8の店", rating: 4.8, userRatingsTotal: 400)
        ]

        let ranked = RecommendationEngine.rank(places, profile: profile)

        XCTAssertEqual(ranked.first?.name, "評価4.8の店")
    }

    // MARK: - 好みタグのスコアリング

    func testScore_好みタグが口コミに含まれる店は加点される() {
        var profile = TasteProfile()
        profile.excludeChains = false
        profile.moodTags = ["隠れ家"]
        let tagged = makePlace(reviews: ["路地裏の隠れ家的なお店です"])
        let untagged = makePlace(reviews: ["普通のお店です"])

        XCTAssertGreaterThan(
            RecommendationEngine.score(tagged, profile: profile),
            RecommendationEngine.score(untagged, profile: profile)
        )
    }

    func testScore_避けたいタグが含まれる店は減点される() {
        var profile = TasteProfile()
        profile.excludeChains = false
        profile.avoidTags = ["行列"]
        let avoided = makePlace(reviews: ["いつも行列ができています"])
        let normal = makePlace(reviews: ["落ち着いた雰囲気です"])

        XCTAssertLessThan(
            RecommendationEngine.score(avoided, profile: profile),
            RecommendationEngine.score(normal, profile: profile)
        )
    }

    func testScore_学習タグは明示タグより加点が小さい() {
        var explicitProfile = TasteProfile()
        explicitProfile.moodTags = ["隠れ家"]
        let learnedProfile = TasteProfile()
        let place = makePlace(reviews: ["隠れ家的なお店"])
        let base = makePlace(reviews: ["普通のお店"])

        let explicitBoost = RecommendationEngine.score(place, profile: explicitProfile)
            - RecommendationEngine.score(base, profile: explicitProfile)
        let learnedBoost = RecommendationEngine.score(place, profile: learnedProfile, learnedTags: ["隠れ家"])
            - RecommendationEngine.score(base, profile: learnedProfile, learnedTags: ["隠れ家"])

        XCTAssertGreaterThan(explicitBoost, learnedBoost)
        XCTAssertGreaterThan(learnedBoost, 0)
    }

    func testScore_明示タグと学習タグが重複しても二重加点されない() {
        var profile = TasteProfile()
        profile.moodTags = ["隠れ家"]
        let place = makePlace(reviews: ["隠れ家的なお店"])

        let withDuplicate = RecommendationEngine.score(place, profile: profile, learnedTags: ["隠れ家"])
        let withoutDuplicate = RecommendationEngine.score(place, profile: profile)

        XCTAssertEqual(withDuplicate, withoutDuplicate, accuracy: 0.0001)
    }
}

// MARK: - テストヘルパー

func makePlace(
    id: String = UUID().uuidString,
    name: String = "テスト店",
    rating: Double? = 4.0,
    userRatingsTotal: Int? = 50,
    priceLevel: Int? = 2,
    openingHours: OpeningHours? = nil,
    reviews: [String]? = nil
) -> Place {
    Place(
        id: id,
        name: name,
        category: .restaurant,
        latitude: 35.6762,
        longitude: 139.7674,
        address: "東京都渋谷区",
        priceLevel: priceLevel,
        rating: rating,
        userRatingsTotal: userRatingsTotal,
        openingHours: openingHours,
        website: nil,
        phoneNumber: nil,
        reviews: reviews
    )
}
