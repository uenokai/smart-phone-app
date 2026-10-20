import XCTest
@testable import LocalRecommend

/// ネット検索結果の分類（本物の口コミ／掲載サイト／メディア／PR・広告／公式）の確認
final class WebMentionAnalyzerTests: XCTestCase {

    private func result(_ url: String, title: String = "喫茶 山小屋に行ってきた", description: String = "渋谷の喫茶 山小屋の感想") -> WebSearchResult {
        WebSearchResult(title: title, url: url, description: description)
    }

    // MARK: - 分類

    func testClassify_ブログやSNSは本物の口コミ() {
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://ameblo.jp/user/entry-1.html"), officialHost: nil), .genuine)
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://note.com/user/n/abc"), officialHost: nil), .genuine)
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://x.com/user/status/1"), officialHost: nil), .genuine)
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://www.instagram.com/p/abc/"), officialHost: nil), .genuine)
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://user.hatenablog.com/entry/2026/01/01"), officialHost: nil), .genuine)
    }

    func testClassify_表に無いドメインでもブログらしいURLは本物の口コミ() {
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://example.org/blog/2026/cafe"), officialHost: nil), .genuine)
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://example.org/products/123"), officialHost: nil), .other)
    }

    func testClassify_掲載サイトは口コミに数えない() {
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://tabelog.com/tokyo/A1303/A130301/13000001/"), officialHost: nil), .listing)
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://retty.me/area/PRE13/ARE1/SUB101/100000001/"), officialHost: nil), .listing)
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://www.hotpepper.jp/strJ000000001/"), officialHost: nil), .listing)
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://maps.google.com/?cid=1"), officialHost: nil), .listing)
    }

    func testClassify_プレスリリース配信サイトはPR() {
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://prtimes.jp/main/html/rd/p/000000001.000000001.html"), officialHost: nil), .promotional)
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://www.atpress.ne.jp/news/1"), officialHost: nil), .promotional)
    }

    func testClassify_PRやタイアップの表記がある個人投稿はPR() {
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://ameblo.jp/user/entry-2.html", title: "【PR】喫茶 山小屋の新メニュー"), officialHost: nil), .promotional)
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://note.com/user/n/xyz", description: "喫茶 山小屋様とのタイアップ記事です"), officialHost: nil), .promotional)
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://www.instagram.com/p/xyz/", description: "喫茶 山小屋 #pr #ad"), officialHost: nil), .promotional)
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://ameblo.jp/user/entry-3.html", description: "喫茶 山小屋のモニター募集に当選"), officialHost: nil), .promotional)
    }

    func testClassify_PRの誤検知をしない() {
        // PRESS や PRODUCT の一部、「料理の提供が早い」「モニターでスポーツ観戦」は PR ではない
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://ameblo.jp/user/entry-4.html", title: "喫茶 山小屋 PRESS CAFE の雰囲気"), officialHost: nil), .genuine)
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://ameblo.jp/user/entry-5.html", description: "喫茶 山小屋は料理の提供が早い"), officialHost: nil), .genuine)
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://ameblo.jp/user/entry-6.html", description: "喫茶 山小屋はモニターでスポーツ観戦ができる"), officialHost: nil), .genuine)
    }

    func testClassify_テレビや新聞はメディア() {
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://www.nhk.or.jp/program/1"), officialHost: nil), .media)
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://www.walkerplus.com/article/1/"), officialHost: nil), .media)
        XCTAssertEqual(WebMentionAnalyzer.classify(result("https://news.yahoo.co.jp/articles/abc"), officialHost: nil), .media)
    }

    func testClassify_公式サイトは公式() {
        XCTAssertEqual(
            WebMentionAnalyzer.classify(result("https://www.yamagoya-cafe.jp/menu"), officialHost: "yamagoya-cafe.jp"),
            .official
        )
    }

    // MARK: - 店名の照合

    func testMentionsPlace_店名が含まれない結果は除外する() {
        XCTAssertTrue(WebMentionAnalyzer.mentionsPlace(result("https://ameblo.jp/a", title: "喫茶山小屋のモーニング"), placeName: "喫茶 山小屋"))
        XCTAssertFalse(WebMentionAnalyzer.mentionsPlace(result("https://ameblo.jp/b", title: "渋谷のカフェ巡り", description: "いろいろ"), placeName: "喫茶 山小屋"))
    }

    func testMentionsPlace_支店名を除いた店名でも照合する() {
        XCTAssertTrue(WebMentionAnalyzer.mentionsPlace(
            result("https://ameblo.jp/c", title: "焼肉きんぐに行った", description: ""),
            placeName: "焼肉きんぐ 渋谷店"
        ))
    }

    // MARK: - 集計

    func testSummarize_ドメイン単位で数えPRは本物の口コミに含めない() {
        let results = [
            result("https://ameblo.jp/user1/entry-1.html"),
            result("https://ameblo.jp/user2/entry-2.html"), // 同じドメインは1件
            result("https://note.com/user/n/abc"),
            result("https://prtimes.jp/main/html/rd/p/1.html"),
            result("https://tabelog.com/tokyo/A1303/A130301/13000001/"),
            result("https://www.nhk.or.jp/program/1"),
            result("https://example.org/blog/1", title: "渋谷のカフェ巡り", description: "店名なし") // 店名が無いので除外
        ]

        let summary = WebMentionAnalyzer.summarize(results: results, query: "q", placeName: "喫茶 山小屋", officialWebsite: nil)

        XCTAssertEqual(summary.genuineCount, 2)
        XCTAssertEqual(summary.promotionalCount, 1)
        XCTAssertEqual(summary.listingCount, 1)
        XCTAssertEqual(summary.mediaCount, 1)
        XCTAssertEqual(summary.mentions.count, 5)
        XCTAssertEqual(summary.mentions.first?.kind, .genuine, "本物の口コミを先頭に並べる")
    }

    func testSummarize_食べログの点数と口コミ件数を読み取る() {
        let tabelog = result(
            "https://tabelog.com/tokyo/A1303/A130301/13000001/",
            title: "喫茶 山小屋 (渋谷/喫茶店) - 食べログ",
            description: "喫茶 山小屋（渋谷/喫茶店）の口コミ・評価。3.58 口コミ 42件。渋谷駅から徒歩5分。"
        )

        let summary = WebMentionAnalyzer.summarize(results: [tabelog], query: "q", placeName: "喫茶 山小屋", officialWebsite: nil)

        let rating = summary.tabelogRating
        XCTAssertEqual(rating?.score, 3.58)
        XCTAssertEqual(rating?.reviewCount, 42)
    }

    func testParseListingRating_小数2桁以外や食べログ以外は読み取らない() {
        XCTAssertNil(WebMentionAnalyzer.parseListingRating(result("https://tabelog.com/tokyo/x", title: "喫茶 山小屋 - 食べログ", description: "評価 4.5 のお店")), "小数1桁は価格などと区別できないので使わない")
        XCTAssertNil(WebMentionAnalyzer.parseListingRating(result("https://retty.me/x", title: "喫茶 山小屋", description: "3.58")))
        XCTAssertNil(WebMentionAnalyzer.parseListingRating(result("https://tabelog.com/tokyo/x", title: "喫茶 山小屋 - 食べログ", description: "ランチ 1200円")))
    }

    func testSummarize_キャッシュ用にエンコードとデコードができる() throws {
        let summary = WebMentionAnalyzer.summarize(
            results: [
                result("https://ameblo.jp/user1/entry-1.html"),
                result("https://tabelog.com/tokyo/x", title: "喫茶 山小屋 - 食べログ", description: "3.21 口コミ 5件")
            ],
            query: "\"喫茶 山小屋\" 渋谷区",
            placeName: "喫茶 山小屋",
            officialWebsite: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(["id": summary])
        let decoded = try decoder.decode([String: WebMentionSummary].self, from: data)

        XCTAssertEqual(decoded["id"]?.genuineCount, 1)
        XCTAssertEqual(decoded["id"]?.listingCount, 1)
        XCTAssertEqual(decoded["id"]?.tabelogRating?.score, 3.21)
        XCTAssertEqual(decoded["id"]?.query, "\"喫茶 山小屋\" 渋谷区")
    }

    // MARK: - クエリと住所

    func testBuildQuery_店名を引用符で囲み市区町村を付ける() {
        XCTAssertEqual(
            WebMentionAnalyzer.buildQuery(placeName: "喫茶 山小屋", address: "日本、〒150-0043 東京都渋谷区道玄坂２丁目１２−３"),
            "\"喫茶 山小屋\" 渋谷区"
        )
        XCTAssertEqual(WebMentionAnalyzer.buildQuery(placeName: "喫茶 山小屋", address: ""), "\"喫茶 山小屋\"")
    }

    func testAddressParser_都道府県の後の市区町村を取り出す() {
        XCTAssertEqual(AddressParser.locality(from: "日本、〒150-0043 東京都渋谷区道玄坂２丁目１２−３"), "渋谷区")
        XCTAssertEqual(AddressParser.locality(from: "東京都町田市原町田１丁目"), "町田市")
        XCTAssertEqual(AddressParser.locality(from: "東京都武蔵野市吉祥寺本町"), "武蔵野市")
        XCTAssertEqual(AddressParser.locality(from: "神奈川県横浜市西区みなとみらい"), "横浜市")
        XCTAssertEqual(AddressParser.locality(from: "北海道札幌市中央区北一条"), "札幌市")
        XCTAssertEqual(AddressParser.locality(from: "大阪府大阪市北区梅田"), "大阪市")
        XCTAssertEqual(AddressParser.locality(from: "千葉県市川市八幡"), "市川市")
    }

    func testAddressParser_短い住所からも市区町村を取り出す() {
        XCTAssertEqual(AddressParser.locality(from: "道玄坂２丁目１２−３, 渋谷区"), "渋谷区")
        XCTAssertNil(AddressParser.locality(from: ""))
    }

    // MARK: - Google口コミの信頼性

    func testReviewAuthenticity_招待やPRの表記を検出する() {
        XCTAssertTrue(ReviewAuthenticity.isSuspectedPromotional("オープン前にご招待いただきました"))
        XCTAssertTrue(ReviewAuthenticity.isSuspectedPromotional("PRとして伺いました"))
        XCTAssertTrue(ReviewAuthenticity.isSuspectedPromotional("商品提供を受けています"))
        XCTAssertTrue(ReviewAuthenticity.isSuspectedPromotional("友人の店なので贔屓目です"))
        XCTAssertTrue(ReviewAuthenticity.isSuspectedPromotional("モニターとして参加しました"))
    }

    func testReviewAuthenticity_通常の口コミを誤検知しない() {
        XCTAssertFalse(ReviewAuthenticity.isSuspectedPromotional("料理の提供が早くて助かる"))
        XCTAssertFalse(ReviewAuthenticity.isSuspectedPromotional("大型モニターでサッカー観戦ができる"))
        XCTAssertFalse(ReviewAuthenticity.isSuspectedPromotional("PRESSという雑誌が置いてある"))
        XCTAssertFalse(ReviewAuthenticity.isSuspectedPromotional("常連さんが多い落ち着いた店"))
    }

    // MARK: - 店名の正規化

    func testNameNormalizer_支店名を取り除く() {
        XCTAssertEqual(NameNormalizer.baseName("スターバックス 渋谷店"), "スターバックス")
        XCTAssertEqual(NameNormalizer.baseName("丸亀製麺 渋谷道玄坂店"), "丸亀製麺")
        XCTAssertEqual(NameNormalizer.baseName("日高屋 本店"), "日高屋")
        XCTAssertEqual(NameNormalizer.baseName("餃子の王将本店"), "餃子の王将")
        XCTAssertEqual(NameNormalizer.baseName("麺屋 一燈"), "麺屋 一燈")
        XCTAssertEqual(NameNormalizer.baseName("マクドナルド新宿西口店"), "マクドナルド新宿西口店", "空白が無いと地名の区切りが判別できないので変えない")
        XCTAssertEqual(NameNormalizer.baseName("喫茶店"), "喫茶店", "短くなりすぎる場合は元の名前を返す")
    }

    func testMentionsPlace_業態だけの名前では照合しない() {
        XCTAssertFalse(WebMentionAnalyzer.mentionsPlace(
            result("https://ameblo.jp/d", title: "近所の大衆酒場に行った", description: ""),
            placeName: "大衆酒場 みんなの店"
        ))
    }
}
