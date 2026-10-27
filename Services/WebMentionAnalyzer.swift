import Foundation

/// ネット検索の結果1件（検索エンジンに依存しない形）
struct WebSearchResult: Equatable {
    let title: String
    let url: String
    let description: String
}

/// ネット検索の結果を「本物の口コミ」「掲載サイト」「メディア」「PR・広告」「公式」に分類し、集計する
///
/// 判定の方針：
/// - 本物の口コミ＝第三者が自分の意思で書いたブログ・SNS・投稿サイト
/// - PR・広告＝プレスリリース配信サイト、または本文に「PR」「タイアップ」「提供」「案件」「モニター」「招待」などの表記があるもの
/// - メディア＝テレビ局・新聞・ニュース・グルメ系キュレーションサイト（露出は「すでに有名」の根拠として扱い、口コミには数えない）
/// - 掲載サイト＝食べログ・ぐるなび等（存在の確認にはなるが口コミには数えない）
enum WebMentionAnalyzer {

    // MARK: - ドメイン表

    /// 第三者の投稿（ブログ・SNS・口コミ投稿サイト）
    static let genuineDomains: [String] = [
        "ameblo.jp", "hatenablog.com", "hatenablog.jp", "hateblo.jp", "hatenadiary.jp", "hatenadiary.com",
        "note.com", "livedoor.jp", "livedoor.blog", "fc2.com", "blogspot.com", "exblog.jp", "seesaa.net",
        "goo.ne.jp", "jugem.jp", "wordpress.com", "muragon.com", "blogmura.com",
        "x.com", "twitter.com", "instagram.com", "threads.net", "tiktok.com", "youtube.com", "bsky.app",
        "4travel.jp", "lemon8-app.com", "chiebukuro.yahoo.co.jp", "supleks.jp", "sarah30.com", "mixi.jp",
        "pixiv.net", "lit.link", "stand.fm", "voicy.jp", "pinterest.jp", "pinterest.com"
    ]

    /// 掲載サイト（店舗情報・予約・地図）
    static let listingDomains: [String] = [
        "tabelog.com", "retty.me", "hotpepper.jp", "gnavi.co.jp", "hitosara.com", "ikyu.com", "ozmall.co.jp",
        "tripadvisor.jp", "tripadvisor.com", "yelp.com", "yelp.co.jp", "google.com", "google.co.jp", "goo.gl",
        "jalan.net", "navitime.co.jp", "mapion.co.jp", "ekiten.jp", "loco.yahoo.co.jp", "foursquare.com",
        "bing.com", "apple.com", "line.me", "ubereats.com", "demae-can.com", "menu.jp", "tablecheck.com",
        "epark.jp", "autoreserve.com", "savorjapan.com", "byfood.com", "mapfan.com", "its-mo.com",
        "rurubu.jp", "rakuten.co.jp", "toreta.in", "omakase.in", "pocket-concierge.jp", "wolt.com",
        "zenkoku-ramen.jp", "yahoo.co.jp"
    ]

    /// テレビ・新聞・ニュース・グルメ系キュレーション
    static let mediaDomains: [String] = [
        "nhk.or.jp", "tv-asahi.co.jp", "tbs.co.jp", "ntv.co.jp", "fujitv.co.jp", "tv-tokyo.co.jp", "mbs.jp", "ytv.co.jp",
        "asahi.com", "yomiuri.co.jp", "mainichi.jp", "nikkei.com", "sankei.com", "news.yahoo.co.jp", "jiji.com", "kyodo.co.jp",
        "walkerplus.com", "tokyo-calendar.jp", "hanako.tokyo", "dot.asahi.com", "toyokeizai.net", "diamond.jp", "president.jp",
        "macaro-ni.jp", "icotto.jp", "tabi-labo.com", "rtrp.jp", "aumo.jp", "favy.jp", "gourmet.oricon.co.jp", "oricon.co.jp",
        "dailyportalz.jp", "rocketnews24.com", "nlab.itmedia.co.jp", "itmedia.co.jp", "grapee.jp", "sirabee.com",
        "mag2.com", "magazine.tabelog.com", "news.mynavi.jp", "tabizine.jp", "jalan.net/news", "trip.jp", "lets.enjoytokyo.jp",
        "tokyolucci.jp", "timeout.jp", "elle.com", "vogue.co.jp", "brutus.jp", "casabrutus.com", "ozmall.co.jp/gourmet/news",
        "tokyoweekender.com", "tv-osaka.co.jp", "ktv.jp", "abc.co.jp", "nbs-tv.co.jp", "hbc.co.jp", "stv.jp"
    ]

    /// プレスリリース・広告配信
    static let promotionalDomains: [String] = [
        "prtimes.jp", "atpress.ne.jp", "dreamnews.jp", "valuepress.jp", "kyodonewsprwire.jp", "news2u.net",
        "prw.kyodonews.jp", "digitalpr.jp", "pr-today.net", "pressrelease-zero.jp", "newscast.jp", "release.nikkei.co.jp"
    ]

    /// 本文・タイトルにあればPR・広告と見なす表記
    static let promotionalPatterns: [String] = [
        "(?<![A-Za-z])PR(?![A-Za-z])", "(?<![A-Za-z])ＰＲ(?![A-Za-z])",
        "【AD】", "\\[AD\\]", "#AD\\b", "#ad\\b",
        "タイアップ", "提供[:：]", "提供で", "商品提供", "提供品", "ご提供いただ", "広告", "案件", "プロモーション",
        "(?i)sponsored", "スポンサー", "プレスリリース", "モニター(募集|当選|として|キャンペーン|体験)",
        "(ご招待|招待され|招待いただ|招待で|招待券)", "インフルエンサー", "アフィリエイト", "アンバサダー", "レビュー依頼", "リリース配信"
    ]

    // MARK: - 分類

    /// ホスト名（www. を除く）
    static func host(of urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else {
            return urlString.lowercased()
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// ホスト名が表のドメイン（またはそのサブドメイン）に一致するか
    static func matches(host: String, path: String, domains: [String]) -> Bool {
        for domain in domains {
            if domain.contains("/") {
                // "jalan.net/news" のようにパスまで含む指定
                let parts = domain.split(separator: "/", maxSplits: 1).map(String.init)
                if parts.count == 2, hostMatches(host, parts[0]), path.hasPrefix("/" + parts[1]) {
                    return true
                }
            } else if hostMatches(host, domain) {
                return true
            }
        }
        return false
    }

    private static func hostMatches(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    /// PR・広告・タイアップの表記があるか
    static func containsPromotionalMarker(_ text: String) -> Bool {
        for pattern in promotionalPatterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    /// 検索結果1件を分類する
    /// - officialHost: 店の公式サイトのホスト名（あれば）。公式サイトとそのサブページは「公式」扱い
    static func classify(_ result: WebSearchResult, officialHost: String?) -> WebMention.Kind {
        let host = self.host(of: result.url)
        let path = URL(string: result.url)?.path ?? ""
        let text = result.title + " " + result.description

        if let official = officialHost, !official.isEmpty, hostMatches(host, official) {
            return .official
        }
        if matches(host: host, path: path, domains: promotionalDomains) {
            return .promotional
        }
        // メディアとキュレーションは、タイアップ表記の有無に関わらず「露出」として扱う
        if matches(host: host, path: path, domains: mediaDomains) {
            return containsPromotionalMarker(text) ? .promotional : .media
        }
        if matches(host: host, path: path, domains: listingDomains) {
            return .listing
        }
        // 個人の投稿でもPR表記があれば本物の口コミとは見なさない
        if containsPromotionalMarker(text) {
            return .promotional
        }
        if matches(host: host, path: path, domains: genuineDomains) {
            return .genuine
        }
        // 表に無いドメインでも、ブログ・日記らしいURLは個人の投稿と見なす
        let lowered = result.url.lowercased()
        if lowered.contains("blog") || lowered.contains("diary") || host.hasPrefix("note.") {
            return .genuine
        }
        if host.contains("news") || host.contains("press") || host.contains("tv") {
            return .media
        }
        return .other
    }

    /// 店名がタイトルか本文に含まれていない結果は、無関係なページとして除外する
    /// 支店名を除いた店名（「スターバックス 渋谷店」→「スターバックス」）でも照合する
    static func mentionsPlace(_ result: WebSearchResult, placeName: String) -> Bool {
        let full = NameNormalizer.comparable(placeName)
        let baseName = NameNormalizer.baseName(placeName)
        let base = NameNormalizer.comparable(baseName)
        guard !full.isEmpty else { return true }
        let text = NameNormalizer.comparable(result.title + " " + result.description)
        if text.contains(full) { return true }
        // 「大衆酒場」のような業態だけの名前は無関係なページにも一致するので使わない
        guard base != full, !NameNormalizer.isGeneric(baseName) else { return false }
        return text.contains(base)
    }

    // MARK: - 掲載サイトの点数

    /// 食べログのページの検索スニペットから点数と口コミ件数を読み取る
    /// 例：「〇〇 (渋谷/ラーメン) - 食べログ」「… 3.58 … 口コミ 42件 …」
    /// 点数は小数2桁（食べログの表記）に限定し、価格などの数字を誤って拾わないようにする
    static func parseListingRating(_ result: WebSearchResult) -> ListingRating? {
        let host = self.host(of: result.url)
        guard host == "tabelog.com" || host.hasSuffix(".tabelog.com") else { return nil }
        let text = result.title + " " + result.description
        guard let scoreRange = text.range(of: "(?<![\\d.])[1-4]\\.\\d{2}(?![\\d])", options: .regularExpression),
              let score = Double(text[scoreRange]) else {
            return nil
        }
        var reviewCount: Int? = nil
        let countPatterns = ["口コミ\\s*(\\d+)\\s*件", "(\\d+)\\s*件の口コミ", "レビュー\\s*(\\d+)\\s*件", "口コミ数\\s*(\\d+)"]
        for pattern in countPatterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let digits = text[range].filter { $0.isNumber }
                if let value = Int(digits) {
                    reviewCount = value
                    break
                }
            }
        }
        return ListingRating(site: ListingRating.tabelogSite, score: score, reviewCount: reviewCount, url: result.url)
    }

    // MARK: - 集計

    /// 検索結果を集計する
    static func summarize(
        results: [WebSearchResult],
        query: String,
        placeName: String,
        officialWebsite: String?,
        now: Date = Date()
    ) -> WebMentionSummary {
        let officialHost = officialWebsite.map { host(of: $0) }
        var seenHosts: Set<String> = []
        var counts: [WebMention.Kind: Int] = [:]
        var mentions: [WebMention] = []
        var listingRatings: [ListingRating] = []

        for result in results {
            let host = self.host(of: result.url)
            // 同じサイト内の複数ページは1件として数える
            guard !seenHosts.contains(host) else { continue }
            guard mentionsPlace(result, placeName: placeName) else { continue }
            seenHosts.insert(host)
            let kind = classify(result, officialHost: officialHost)
            counts[kind, default: 0] += 1
            mentions.append(WebMention(
                title: result.title,
                url: result.url,
                domain: host,
                snippet: result.description,
                kind: kind
            ))
            if let rating = parseListingRating(result) {
                listingRatings.append(rating)
            }
        }

        // 表示は本物の口コミを先頭に、種類ごとにまとめる
        let order: [WebMention.Kind] = [.genuine, .media, .listing, .promotional, .official, .other]
        let sorted = mentions.sorted { a, b in
            (order.firstIndex(of: a.kind) ?? 99) < (order.firstIndex(of: b.kind) ?? 99)
        }
        return WebMentionSummary(
            fetchedAt: now,
            query: query,
            counts: counts,
            mentions: Array(sorted.prefix(10)),
            listingRatings: listingRatings
        )
    }

    // MARK: - クエリ

    /// 店名と市区町村で検索クエリを作る（例：「"喫茶 山小屋" 渋谷区」）
    static func buildQuery(placeName: String, address: String) -> String {
        let name = placeName.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
        if let locality = AddressParser.locality(from: address) {
            return "\"\(name)\" \(locality)"
        }
        return "\"\(name)\""
    }
}

/// 住所から市区町村を取り出す
///
/// 「市川市」「町田市」「武蔵村山市」のように地名そのものに市・町・村を含む例が多いため、
/// 正規表現ではなく「都道府県の直後から、2文字目以降で最初に現れる 市→区→郡→町→村 まで」を取る。
/// 「四日市市」は「四日市」になるが、検索語としては問題ない
enum AddressParser {
    private static let specialPrefectures = ["東京都", "北海道", "京都府", "大阪府"]
    private static let terminals: [Character] = ["市", "区", "郡", "町", "村"]

    /// 「日本、〒150-0043 東京都渋谷区道玄坂２丁目…」→「渋谷区」、「神奈川県横浜市西区…」→「横浜市」
    static func locality(from address: String) -> String? {
        if let rest = remainderAfterPrefecture(address), let found = scan(rest) {
            return found
        }
        // 都道府県が無い短い住所（「道玄坂２丁目, 渋谷区」など）は区切りごとに探す
        let tokens = address.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "、" || $0.isWhitespace })
        for token in tokens where !token.contains(where: { $0.isNumber }) {
            if let found = scan(String(token)) {
                return found
            }
        }
        return nil
    }

    /// 都道府県名の直後からの文字列
    private static func remainderAfterPrefecture(_ address: String) -> String? {
        for prefecture in specialPrefectures {
            if let range = address.range(of: prefecture) {
                return String(address[range.upperBound...])
            }
        }
        // 「〇〇県」：県の直前2〜3文字が県名
        let chars = Array(address)
        for (index, char) in chars.enumerated() where char == "県" && index >= 2 {
            return String(chars[(index + 1)...])
        }
        return nil
    }

    /// 先頭6文字以内で、2文字目以降に最初に現れる区切り文字（市→区→郡→町→村の順に優先）までを返す
    private static func scan(_ text: String) -> String? {
        let chars = Array(text.prefix(6))
        guard chars.count >= 2 else { return nil }
        for terminal in terminals {
            for index in 1..<chars.count where chars[index] == terminal {
                return String(chars[0...index])
            }
        }
        return nil
    }
}

/// Google の口コミが「本物の口コミ」と見なせるかの判定
enum ReviewAuthenticity {
    /// 招待・モニター・PR・提供・身内など、第三者の自発的な口コミとは言えない表記
    /// 「料理の提供が早い」「モニターでスポーツ観戦」のような通常の口コミを誤判定しないよう、語の組み合わせで判定する
    static let suspectedPatterns: [String] = [
        "(ご招待|招待され|招待いただ|招待で|招待券)", "モニター(募集|当選|として|キャンペーン|体験)", "インフルエンサー",
        "(?<![A-Za-z])PR(?![A-Za-z])", "(提供して(もらっ|いただ|頂)|商品提供|提供品|ご提供いただ)", "試食会", "レセプション", "内覧会",
        "タイアップ", "(PR案件|案件で)", "無料で(いただ|頂|食べ|飲)", "友人の店", "知人の店", "友達の店", "身内の店", "親戚の店",
        "オーナーは私", "私の店", "うちの店", "自分の店"
    ]

    static func isSuspectedPromotional(_ text: String) -> Bool {
        for pattern in suspectedPatterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }
}
