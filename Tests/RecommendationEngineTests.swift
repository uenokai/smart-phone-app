import XCTest
@testable import LocalRecommend

final class RecommendationEngineTests: XCTestCase {

    // MARK: - ベイズ平均（口コミ数で補正した評価）

    func testBayesianRating_口コミが少ないほど周辺平均に寄る() {
        let few = RecommendationEngine.bayesianRating(rating: 5.0, count: 3, priorMean: 3.8)
        let many = RecommendationEngine.bayesianRating(rating: 4.5, count: 80, priorMean: 3.8)

        XCTAssertLessThan(few, many, "口コミ3件の5.0は口コミ80件の4.5より低く補正される")
        XCTAssertEqual(few, (10 * 3.8 + 3 * 5.0) / 13, accuracy: 0.0001)
    }

    func testRank_評価重視でも口コミ3件の5点は口コミ80件の4点5を上回らない() {
        var profile = TasteProfile()
        profile.hiddenGemWeight = 0.0
        profile.excludeChains = false
        let places = [
            makePlace(name: "口コミ3件の5.0", rating: 5.0, userRatingsTotal: 3),
            makePlace(name: "口コミ80件の4.5", rating: 4.5, userRatingsTotal: 80)
        ]

        let ranked = RecommendationEngine.rank(places, profile: profile)

        XCTAssertEqual(ranked.first?.name, "口コミ80件の4.5")
    }

    // MARK: - 未知度（候補内の相対位置）

    func testObscurityScore_候補の中で口コミが少ない店ほど高い() {
        let places = [
            makePlace(name: "A", userRatingsTotal: 10),
            makePlace(name: "B", userRatingsTotal: 50),
            makePlace(name: "C", userRatingsTotal: 200),
            makePlace(name: "D", userRatingsTotal: 800)
        ]
        let pool = PoolStatistics(places: places)

        let scores = places.map { RecommendationEngine.obscurityScore(for: $0, pool: pool) }

        XCTAssertGreaterThan(scores[0], scores[1])
        XCTAssertGreaterThan(scores[1], scores[2])
        XCTAssertGreaterThan(scores[2], scores[3])
    }

    func testObscurityScore_口コミ1000件以上は候補内の位置に関わらずゼロ() {
        let places = [
            makePlace(name: "A", userRatingsTotal: 1000),
            makePlace(name: "B", userRatingsTotal: 5000)
        ]
        let pool = PoolStatistics(places: places)

        XCTAssertEqual(RecommendationEngine.obscurityScore(for: places[0], pool: pool), 0)
    }

    func testObscurityScore_同じ口コミ数でも候補の水準で変わる() {
        let place = makePlace(name: "対象", userRatingsTotal: 100)
        let urbanPool = PoolStatistics(places: [place] + (1...9).map { makePlace(name: "都心\($0)", userRatingsTotal: 500 * $0) })
        let ruralPool = PoolStatistics(places: [place] + (1...9).map { makePlace(name: "地方\($0)", userRatingsTotal: 5 * $0) })

        XCTAssertGreaterThan(
            RecommendationEngine.obscurityScore(for: place, pool: urbanPool),
            RecommendationEngine.obscurityScore(for: place, pool: ruralPool),
            "都心（周りの口コミが多い）では同じ100件でも未知度が高い"
        )
    }

    // MARK: - 新しさ

    func testRecencyScore_最新口コミが新しいほど高く_未取得ならnil() {
        let now = Date()
        XCTAssertEqual(RecommendationEngine.recencyScore(latestReview: now.addingTimeInterval(-30 * 86_400), hasReviewData: true, now: now), 1.0)
        XCTAssertEqual(RecommendationEngine.recencyScore(latestReview: now.addingTimeInterval(-400 * 86_400), hasReviewData: true, now: now), 0.4)
        XCTAssertEqual(RecommendationEngine.recencyScore(latestReview: now.addingTimeInterval(-1000 * 86_400), hasReviewData: true, now: now), 0.15)
        XCTAssertEqual(RecommendationEngine.recencyScore(latestReview: nil, hasReviewData: true, now: now), 0.3)
        XCTAssertNil(RecommendationEngine.recencyScore(latestReview: nil, hasReviewData: false, now: now))
    }

    // MARK: - ネット上の本物の口コミ

    func testGenuineMentionScore_件数の対数で増え8件で満点() {
        XCTAssertEqual(RecommendationEngine.genuineMentionScore(nil), 0)
        XCTAssertEqual(RecommendationEngine.genuineMentionScore(makeMentions(genuine: 0)), 0)
        XCTAssertEqual(RecommendationEngine.genuineMentionScore(makeMentions(genuine: 1)), log2(2) / log2(9), accuracy: 0.0001)
        XCTAssertEqual(RecommendationEngine.genuineMentionScore(makeMentions(genuine: 8)), 1.0, accuracy: 0.0001)
        XCTAssertEqual(RecommendationEngine.genuineMentionScore(makeMentions(genuine: 20)), 1.0, accuracy: 0.0001)
    }

    func testScore_PR広告の言及は加点されない() {
        let profile = TasteProfile()
        var promoted = makePlace(name: "PRだけの店", rating: 4.3, userRatingsTotal: 30)
        promoted.webMentions = makeMentions(genuine: 0, promotional: 5)
        var genuine = makePlace(name: "ブログに書かれた店", rating: 4.3, userRatingsTotal: 30)
        genuine.webMentions = makeMentions(genuine: 2)
        var none = makePlace(name: "言及なしの店", rating: 4.3, userRatingsTotal: 30)
        none.webMentions = makeMentions(genuine: 0)
        let pool = PoolStatistics(places: [promoted, genuine, none])

        let promotedScore = RecommendationEngine.score(promoted, pool: pool, profile: profile)
        let genuineScore = RecommendationEngine.score(genuine, pool: pool, profile: profile)
        let noneScore = RecommendationEngine.score(none, pool: pool, profile: profile)

        XCTAssertEqual(promotedScore.genuineMention, 0)
        XCTAssertEqual(promotedScore.total, noneScore.total, accuracy: 0.0001)
        XCTAssertGreaterThan(genuineScore.total, promotedScore.total)
    }

    func testScore_メディア露出は未知度を下げる() {
        var profile = TasteProfile()
        profile.hiddenGemWeight = 1.0
        var exposed = makePlace(name: "テレビに出た店", rating: 4.3, userRatingsTotal: 30)
        exposed.webMentions = makeMentions(genuine: 0, media: 2)
        var quiet = makePlace(name: "静かな店", rating: 4.3, userRatingsTotal: 30)
        quiet.webMentions = makeMentions(genuine: 0)
        let pool = PoolStatistics(places: [exposed, quiet])

        let exposedScore = RecommendationEngine.score(exposed, pool: pool, profile: profile)
        let quietScore = RecommendationEngine.score(quiet, pool: pool, profile: profile)

        XCTAssertLessThan(exposedScore.obscurity, quietScore.obscurity)
        XCTAssertTrue(exposedScore.reasons.contains { $0.id == "media" && $0.delta < 0 })
    }

    func testScore_食べログの点数は品質に反映される() {
        var profile = TasteProfile()
        profile.hiddenGemWeight = 0.0
        var high = makePlace(name: "食べログ高評価", rating: 4.0, userRatingsTotal: 30)
        high.webMentions = makeMentions(genuine: 0, tabelogScore: 3.80, tabelogReviews: 40)
        var low = makePlace(name: "食べログ低評価", rating: 4.0, userRatingsTotal: 30)
        low.webMentions = makeMentions(genuine: 0, tabelogScore: 3.05, tabelogReviews: 40)
        let pool = PoolStatistics(places: [high, low])

        let highScore = RecommendationEngine.score(high, pool: pool, profile: profile)
        let lowScore = RecommendationEngine.score(low, pool: pool, profile: profile)

        XCTAssertGreaterThan(highScore.quality, lowScore.quality)
        XCTAssertTrue(highScore.reasons.contains { $0.id == "tabelog" && $0.detail.contains("3.80点") })
    }

    // MARK: - 口コミの信頼性

    func testScore_招待やPRと読める口コミがあると品質が下がる() {
        let profile = TasteProfile()
        let honest = makePlace(name: "普通の店", rating: 4.5, userRatingsTotal: 20, reviewDetails: [
            makeReview("落ち着いた雰囲気で料理の提供が早い"),
            makeReview("常連になりました")
        ])
        let invited = makePlace(name: "招待の店", rating: 4.5, userRatingsTotal: 20, reviewDetails: [
            makeReview("オープン前にご招待いただきました"),
            makeReview("PRで伺いました")
        ])
        let pool = PoolStatistics(places: [honest, invited])

        let honestScore = RecommendationEngine.score(honest, pool: pool, profile: profile)
        let invitedScore = RecommendationEngine.score(invited, pool: pool, profile: profile)

        XCTAssertGreaterThan(honestScore.quality, invitedScore.quality)
        XCTAssertTrue(invitedScore.reasons.contains { $0.id == "authenticity" })
        XCTAssertFalse(honestScore.reasons.contains { $0.id == "authenticity" }, "「提供が早い」は招待・PRとは見なさない")
    }

    // MARK: - チェーン店判定

    func testIsLikelyChain_チェーン店名を含む店はチェーンと判定される() {
        XCTAssertTrue(RecommendationEngine.isLikelyChain(makePlace(name: "スターバックス 渋谷店")))
        XCTAssertTrue(RecommendationEngine.isLikelyChain(makePlace(name: "マクドナルド 新宿西口店")))
    }

    func testIsLikelyChain_個人店はチェーンと判定されない() {
        XCTAssertFalse(RecommendationEngine.isLikelyChain(makePlace(name: "喫茶 山小屋")))
    }

    func testIsLikelyChain_候補の中に同名の支店が複数あればキーワード表になくてもチェーンと判定する() {
        let places = [
            makePlace(name: "焼肉きんぐ 渋谷店"),
            makePlace(name: "焼肉きんぐ 道玄坂店"),
            makePlace(name: "焼肉 ひとり")
        ]
        let pool = PoolStatistics(places: places)

        XCTAssertTrue(RecommendationEngine.isLikelyChain(places[0], pool: pool))
        XCTAssertTrue(RecommendationEngine.isLikelyChain(places[1], pool: pool))
        XCTAssertFalse(RecommendationEngine.isLikelyChain(places[2], pool: pool))
    }

    // MARK: - ランキングと除外

    func testEvaluate_チェーン除外ONならチェーン店が結果から消える() {
        var profile = TasteProfile()
        profile.excludeChains = true
        let places = [
            makePlace(name: "スターバックス 渋谷店", rating: 4.0, userRatingsTotal: 100),
            makePlace(name: "喫茶 山小屋", rating: 4.0, userRatingsTotal: 100)
        ]

        let ranked = RecommendationEngine.rank(places, profile: profile)

        XCTAssertEqual(ranked.map { $0.name }, ["喫茶 山小屋"])
    }

    func testEvaluate_既知の店は結果から消える() {
        let profile = TasteProfile()
        let known = makePlace(id: "known", name: "行った店")
        let unknown = makePlace(id: "unknown", name: "知らない店")

        let ranked = RecommendationEngine.rank([known, unknown], profile: profile, knownIds: ["known"])

        XCTAssertEqual(ranked.map { $0.name }, ["知らない店"])
    }

    func testEvaluate_口コミ数の上限を超える店は除外される() {
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

    func testEvaluate_穴場重視なら口コミの少ない店が上位に来る() {
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

    func testEvaluate_評価重視なら評価の高い店が上位に来る() {
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

    func testEvaluate_総合スコアの降順に並ぶ() {
        let profile = TasteProfile()
        let places = (1...6).map { makePlace(name: "店\($0)", rating: 3.5 + 0.2 * Double($0), userRatingsTotal: 20 * $0) }

        let scored = RecommendationEngine.evaluate(places, profile: profile)

        let totals = scored.map { $0.total }
        XCTAssertEqual(totals, totals.sorted(by: >))
    }

    // MARK: - バッジ

    func testBadge_評価が高く候補内で知られておらず口コミ5件以上なら穴場() {
        var profile = TasteProfile()
        profile.excludeChains = false
        let gem = makePlace(name: "穴場", rating: 4.6, userRatingsTotal: 12)
        let others = (1...8).map { makePlace(name: "有名\($0)", rating: 4.2, userRatingsTotal: 300 * $0) }

        let scored = RecommendationEngine.evaluate([gem] + others, profile: profile)

        XCTAssertEqual(scored.first { $0.place.name == "穴場" }?.badge, .hiddenGem)
    }

    func testBadge_口コミ5件未満でネット言及も無ければ未確認() {
        var profile = TasteProfile()
        profile.excludeChains = false
        var unverified = makePlace(name: "未確認", rating: 5.0, userRatingsTotal: 2)
        unverified.webMentions = makeMentions(genuine: 0)
        let others = (1...8).map { makePlace(name: "有名\($0)", rating: 4.2, userRatingsTotal: 300 * $0) }

        let scored = RecommendationEngine.evaluate([unverified] + others, profile: profile)

        let target = scored.first { $0.place.name == "未確認" }
        XCTAssertEqual(target?.badge, .unverified)
        XCTAssertTrue(target?.reasons.contains { $0.id == "lowEvidence" } ?? false)
    }

    func testBadge_口コミ5件未満でもネットに本物の言及があれば穴場になり得る() {
        var profile = TasteProfile()
        profile.excludeChains = false
        var gem = makePlace(name: "ブログの穴場", rating: 4.6, userRatingsTotal: 4)
        gem.webMentions = makeMentions(genuine: 3)
        let others = (1...8).map { makePlace(name: "有名\($0)", rating: 4.2, userRatingsTotal: 300 * $0) }

        let scored = RecommendationEngine.evaluate([gem] + others, profile: profile)

        XCTAssertEqual(scored.first { $0.place.name == "ブログの穴場" }?.badge, .hiddenGem)
    }

    func testBadge_チェーン店は穴場にならない() {
        var profile = TasteProfile()
        profile.excludeChains = false
        let chain = makePlace(name: "スターバックス 奥地店", rating: 4.6, userRatingsTotal: 12)
        let others = (1...8).map { makePlace(name: "有名\($0)", rating: 4.2, userRatingsTotal: 300 * $0) }

        let scored = RecommendationEngine.evaluate([chain] + others, profile: profile)

        XCTAssertEqual(scored.first { $0.place.name == "スターバックス 奥地店" }?.badge, ScoredPlace.Badge.none)
    }

    // MARK: - 判定理由

    func testScore_判定理由に評価と未知度が必ず含まれる() {
        let place = makePlace()
        let pool = PoolStatistics(places: [place])

        let scored = RecommendationEngine.score(place, pool: pool, profile: TasteProfile())

        XCTAssertTrue(scored.reasons.contains { $0.id == "quality" })
        XCTAssertTrue(scored.reasons.contains { $0.id == "obscurity" })
        XCTAssertFalse(scored.headline.isEmpty)
    }

    // MARK: - 好みタグのスコアリング

    func testScore_好みタグが口コミに含まれる店は加点される() {
        var profile = TasteProfile()
        profile.excludeChains = false
        profile.moodTags = ["隠れ家"]
        let tagged = makePlace(reviews: ["路地裏の隠れ家的なお店です"])
        let untagged = makePlace(reviews: ["普通のお店です"])
        let pool = PoolStatistics(places: [tagged, untagged])

        XCTAssertGreaterThan(
            RecommendationEngine.score(tagged, pool: pool, profile: profile).total,
            RecommendationEngine.score(untagged, pool: pool, profile: profile).total
        )
    }

    func testScore_避けたいタグが含まれる店は減点される() {
        var profile = TasteProfile()
        profile.excludeChains = false
        profile.avoidTags = ["行列"]
        let avoided = makePlace(reviews: ["いつも行列ができています"])
        let normal = makePlace(reviews: ["落ち着いた雰囲気です"])
        let pool = PoolStatistics(places: [avoided, normal])

        XCTAssertLessThan(
            RecommendationEngine.score(avoided, pool: pool, profile: profile).total,
            RecommendationEngine.score(normal, pool: pool, profile: profile).total
        )
    }

    func testScore_学習タグは明示タグより加点が小さい() {
        var explicitProfile = TasteProfile()
        explicitProfile.moodTags = ["隠れ家"]
        let learnedProfile = TasteProfile()
        let place = makePlace(reviews: ["隠れ家的なお店"])
        let base = makePlace(reviews: ["普通のお店"])
        let pool = PoolStatistics(places: [place, base])

        let explicitBoost = RecommendationEngine.score(place, pool: pool, profile: explicitProfile).total
            - RecommendationEngine.score(base, pool: pool, profile: explicitProfile).total
        let learnedBoost = RecommendationEngine.score(place, pool: pool, profile: learnedProfile, learnedTags: ["隠れ家"]).total
            - RecommendationEngine.score(base, pool: pool, profile: learnedProfile, learnedTags: ["隠れ家"]).total

        XCTAssertGreaterThan(explicitBoost, learnedBoost)
        XCTAssertGreaterThan(learnedBoost, 0)
    }

    func testScore_明示タグと学習タグが重複しても二重加点されない() {
        var profile = TasteProfile()
        profile.moodTags = ["隠れ家"]
        let place = makePlace(reviews: ["隠れ家的なお店"])
        let pool = PoolStatistics(places: [place])

        let withDuplicate = RecommendationEngine.score(place, pool: pool, profile: profile, learnedTags: ["隠れ家"]).total
        let withoutDuplicate = RecommendationEngine.score(place, pool: pool, profile: profile).total

        XCTAssertEqual(withDuplicate, withoutDuplicate, accuracy: 0.0001)
    }

    func testScore_招待の口コミに含まれる好みタグは加点に使わない() {
        var profile = TasteProfile()
        profile.moodTags = ["隠れ家"]
        let suspectedOnly = makePlace(name: "A", reviewDetails: [makeReview("ご招待いただいた隠れ家です")])
        let plain = makePlace(name: "B", reviewDetails: [makeReview("普通のお店")])
        let pool = PoolStatistics(places: [suspectedOnly, plain])

        let scored = RecommendationEngine.score(suspectedOnly, pool: pool, profile: profile)

        XCTAssertFalse(scored.reasons.contains { $0.id == "mood" })
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
    reviews: [String]? = nil,
    reviewDetails: [PlaceReview]? = nil,
    businessStatus: String? = nil
) -> Place {
    var place = Place(
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
    place.reviewDetails = reviewDetails
    place.businessStatus = businessStatus
    return place
}

func makeReview(_ text: String, rating: Int = 5, daysAgo: Double = 10) -> PlaceReview {
    PlaceReview(
        rating: rating,
        text: text,
        publishedAt: Date().addingTimeInterval(-daysAgo * 86_400),
        authorName: "テスト"
    )
}

func makeMentions(
    genuine: Int,
    media: Int = 0,
    promotional: Int = 0,
    listing: Int = 0,
    tabelogScore: Double? = nil,
    tabelogReviews: Int? = nil
) -> WebMentionSummary {
    var counts: [WebMention.Kind: Int] = [:]
    if genuine > 0 { counts[.genuine] = genuine }
    if media > 0 { counts[.media] = media }
    if promotional > 0 { counts[.promotional] = promotional }
    if listing > 0 { counts[.listing] = listing }
    var ratings: [ListingRating] = []
    if let score = tabelogScore {
        ratings.append(ListingRating(site: ListingRating.tabelogSite, score: score, reviewCount: tabelogReviews, url: "https://tabelog.com/tokyo/x"))
    }
    return WebMentionSummary(fetchedAt: Date(), query: "test", counts: counts, mentions: [], listingRatings: ratings)
}
