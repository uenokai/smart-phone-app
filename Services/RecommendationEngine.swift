import Foundation

/// 判定理由の1項目（なぜ上位／下位なのかを利用者が検証できるようにする）
struct ScoreReason: Identifiable, Equatable {
    let id: String
    let label: String
    let detail: String
    /// 総合スコアへの寄与（正なら加点、負なら減点）
    let delta: Double
}

/// 採点済みの店
struct ScoredPlace: Identifiable, Equatable {
    var id: String { place.id }
    let place: Place
    /// 総合スコア（並べ替えに使う）
    let total: Double
    /// 品質（0〜1）：口コミ数で補正した評価
    let quality: Double
    /// 未知度（0〜1）：候補の中で口コミが少ない側にいるほど高い
    let obscurity: Double
    /// 新しさ（0〜1）：取得できた口コミの最新投稿日。口コミ未取得なら nil
    let recency: Double?
    /// ネット上の本物の口コミ（0〜1）
    let genuineMention: Double
    let reasons: [ScoreReason]
    let badge: Badge

    enum Badge: Equatable {
        /// 評価が高く、候補の中で知られておらず、口コミかネット言及の裏付けがある
        case hiddenGem
        /// 知られていないが裏付けが少ない（口コミ5件未満・ネット言及なし）
        case unverified
        case none

        var label: String? {
            switch self {
            case .hiddenGem: return "💎 穴場"
            case .unverified: return "🔍 未確認"
            case .none: return nil
            }
        }
    }

    var isHiddenGem: Bool { badge == .hiddenGem }

    /// カードに出す短い理由（寄与の大きい順に2つ）
    var headline: String {
        reasons
            .filter { $0.delta > 0 }
            .sorted { $0.delta > $1.delta }
            .prefix(2)
            .map { $0.label }
            .joined(separator: "・")
    }
}

/// 候補全体の統計。未知度・評価の補正は「その検索の候補の中での相対位置」で決める
/// （都心と地方では口コミ数の水準が違うため、固定のしきい値では比較できない）
struct PoolStatistics {
    let count: Int
    /// 評価の平均（評価のある店のみ）。評価のある店が5件未満なら既定値
    let meanRating: Double
    /// 口コミ数の昇順リスト
    private let sortedReviewCounts: [Int]
    /// 支店名を除いた店名ごとの出現数
    private let baseNameCounts: [String: Int]

    static let defaultMeanRating = 3.8

    init(places: [Place]) {
        count = places.count
        let ratings = places.compactMap { $0.rating }
        meanRating = ratings.count >= 5 ? ratings.reduce(0, +) / Double(ratings.count) : Self.defaultMeanRating
        sortedReviewCounts = places.map { $0.userRatingsTotal ?? 0 }.sorted()
        var names: [String: Int] = [:]
        for place in places {
            let base = NameNormalizer.baseName(place.name)
            let key = NameNormalizer.comparable(base)
            // 「居酒屋」のような業態だけの名前は同名扱いにしない
            if key.count >= 3 && !NameNormalizer.isGeneric(base) {
                names[key, default: 0] += 1
            }
        }
        baseNameCounts = names
    }

    /// 口コミ数 n より少ない店の割合（0 = 最も少ない、1 に近いほど多い）
    func reviewCountPercentile(_ n: Int) -> Double {
        guard !sortedReviewCounts.isEmpty else { return 0 }
        let below = sortedReviewCounts.filter { $0 < n }.count
        return Double(below) / Double(sortedReviewCounts.count)
    }

    /// 同じ店名（支店名を除く）が候補の中に何件あるか
    func sameNameCount(_ place: Place) -> Int {
        let key = NameNormalizer.comparable(NameNormalizer.baseName(place.name))
        return baseNameCounts[key] ?? 0
    }
}

/// 好みプロファイルに基づいて検索結果を採点・並べ替えるエンジン
///
/// 「評価が高いのに知られていない店」を、本物の口コミの裏付けつきで上位に出すのがこのアプリの核。
/// 総合スコア = (1−h)×品質 + h×未知度 + 0.25×新しさ + 0.3×ネットの口コミ + タグ加減点 − チェーン減点
/// （h = 穴場重視度 0〜1）
struct RecommendationEngine {

    /// 全国チェーンと見なす店名キーワード（候補内の同名支店検出で拾えない場合の補助）
    static let chainKeywords: [String] = [
        "マクドナルド", "スターバックス", "ドトール", "タリーズ", "サイゼリヤ",
        "ガスト", "すき家", "吉野家", "松屋", "CoCo壱番屋", "ココイチ",
        "ケンタッキー", "モスバーガー", "丸亀製麺", "はなまるうどん",
        "くら寿司", "スシロー", "はま寿司", "かっぱ寿司", "コメダ珈琲",
        "デニーズ", "ジョナサン", "バーミヤン", "ロイヤルホスト", "大戸屋",
        "餃子の王将", "日高屋", "幸楽苑", "リンガーハット", "ミスタードーナツ",
        "サンマルクカフェ", "エクセルシオール", "プロント", "びっくりドンキー",
        "ジョイフル", "やよい軒", "てんや", "なか卯", "ロッテリア", "バーガーキング", "フレッシュネス",
        "鳥貴族", "ワタミ", "和民", "甘太郎", "土間土間", "魚民", "白木屋", "笑笑", "はなの舞", "庄や",
        "ビッグエコー", "星乃珈琲", "むさしの森", "ココス", "ステーキガスト", "いきなりステーキ", "かつや",
        "松のや", "天丼てんや", "一蘭", "一風堂", "天下一品", "山岡家", "ラーメン花月", "珈琲館", "ベローチェ"
    ]

    /// 口コミ数がこれ以上の店は、候補内の相対位置に関わらず「知られている」と見なす
    static let majorReviewThreshold = 1000
    /// ベイズ平均の事前重み（口コミがこの件数あると、店の評価と周辺平均が半々で効く）
    static let priorWeight = 10.0
    /// 穴場バッジの裏付けに必要な口コミ数
    static let minReviewsForEvidence = 5

    /// 口コミに含まれると「知られていない店」の裏付けになる語
    static let hiddenGemWords: [String] = [
        "穴場", "隠れ家", "知る人ぞ知る", "常連", "地元", "ひっそり", "路地裏", "看板がない", "看板のない", "教えたくない"
    ]
    /// 口コミに含まれると「すでに知られている店」の根拠になる語
    static let famousWords: [String] = [
        "行列", "有名", "人気店", "テレビ", "インスタ", "話題", "バズ", "観光客", "予約困難", "メディア", "雑誌で"
    ]

    // MARK: - 個別の判定

    /// お店が全国チェーンらしいか
    /// キーワード表に加え、候補の中に同じ店名（支店名を除く）が複数あれば支店展開していると判断する
    static func isLikelyChain(_ place: Place, pool: PoolStatistics? = nil) -> Bool {
        if chainKeywords.contains(where: { place.name.contains($0) }) {
            return true
        }
        if let pool = pool, pool.sameNameCount(place) >= 2 {
            return true
        }
        return false
    }

    /// 口コミ数で補正した評価（ベイズ平均）
    /// 口コミが少ない店の評価を周辺平均に寄せることで、口コミ3件の5.0が口コミ80件の4.5より上に来ないようにする
    static func bayesianRating(rating: Double, count: Int, priorMean: Double, priorWeight: Double = priorWeight) -> Double {
        let n = Double(max(count, 0))
        return (priorWeight * priorMean + n * rating) / (priorWeight + n)
    }

    /// 品質（0〜1）。補正後評価3.0で0、5.0で1
    static func qualityScore(for place: Place, pool: PoolStatistics) -> Double {
        guard let rating = place.rating else { return 0 }
        let adjusted = bayesianRating(rating: rating, count: place.userRatingsTotal ?? 0, priorMean: pool.meanRating)
        return min(1, max(0, (adjusted - 3.0) / 2.0))
    }

    /// 未知度（0〜1）。候補内の相対位置（7割）と絶対的な口コミ数（3割）の組み合わせ
    static func obscurityScore(for place: Place, pool: PoolStatistics) -> Double {
        let n = place.userRatingsTotal ?? 0
        if n >= majorReviewThreshold { return 0 }
        let relative = 1.0 - pool.reviewCountPercentile(n)
        let absolute = max(0, 1.0 - Double(n) / Double(majorReviewThreshold))
        return min(1, max(0, 0.7 * relative + 0.3 * absolute))
    }

    /// 新しさ（0〜1）。最新の口コミからの経過日数で決める。口コミ未取得なら nil
    static func recencyScore(latestReview: Date?, hasReviewData: Bool, now: Date) -> Double? {
        guard hasReviewData else { return nil }
        guard let latest = latestReview else { return 0.3 }
        let days = now.timeIntervalSince(latest) / 86_400
        switch days {
        case ..<90: return 1.0
        case ..<365: return 0.7
        case ..<730: return 0.4
        default: return 0.15
        }
    }

    /// ネット上の本物の口コミ（0〜1）。件数の対数で、1件0.32・2件0.5・4件0.73・8件以上1.0
    static func genuineMentionScore(_ summary: WebMentionSummary?) -> Double {
        guard let summary = summary else { return 0 }
        let count = Double(summary.genuineCount)
        guard count > 0 else { return 0 }
        return min(1, log2(1 + count) / log2(9))
    }

    // MARK: - 採点

    /// 1店を採点する
    static func score(
        _ place: Place,
        pool: PoolStatistics,
        profile: TasteProfile,
        learnedTags: [String] = [],
        now: Date = Date()
    ) -> ScoredPlace {
        var reasons: [ScoreReason] = []
        let h = min(1, max(0, profile.hiddenGemWeight))
        let reviewCount = place.userRatingsTotal ?? 0
        let hasReviewData = place.reviewDetails != nil

        // 品質
        var quality = qualityScore(for: place, pool: pool)
        if let rating = place.rating {
            let adjusted = bayesianRating(rating: rating, count: reviewCount, priorMean: pool.meanRating)
            reasons.append(ScoreReason(
                id: "quality",
                label: "評価",
                detail: String(format: "%.1f（口コミ%ld件）→ 口コミ数で補正すると %.2f", rating, reviewCount, adjusted),
                delta: (1 - h) * quality
            ))
        } else {
            reasons.append(ScoreReason(id: "quality", label: "評価なし", detail: "Googleの評価がまだありません", delta: 0))
        }

        // 食べログの点数が読み取れていれば、Google とは別の評価源として品質に混ぜる
        // 食べログは 3.5 で上位1割程度の厳しい尺度なので、3.0→0、3.5→0.5、4.0→1 に換算する
        if let tabelog = place.webMentions?.tabelogRating {
            let tabelogQuality = min(1, max(0, (tabelog.score - 3.0) / 1.0))
            let before = quality
            quality = place.rating == nil
                ? tabelogQuality * 0.8
                : 0.65 * quality + 0.35 * tabelogQuality
            let countText = tabelog.reviewCount.map { "（口コミ\($0)件）" } ?? ""
            reasons.append(ScoreReason(
                id: "tabelog",
                label: "食べログ",
                detail: String(format: "%.2f点", tabelog.score) + countText,
                delta: (1 - h) * (quality - before)
            ))
        }

        // 口コミの信頼性（招待・PR・身内の口コミは本物と見なさない）
        let suspected = place.reviewDetails?.filter { $0.isSuspected }.count ?? 0
        if suspected > 0 {
            let before = quality
            quality *= max(0.5, 1.0 - 0.15 * Double(suspected))
            reasons.append(ScoreReason(
                id: "authenticity",
                label: "口コミの信頼性",
                detail: "招待・PR・身内と読める口コミが\(suspected)件",
                delta: -(1 - h) * (before - quality)
            ))
        }

        // 未知度
        var obscurity = obscurityScore(for: place, pool: pool)
        let percentile = pool.reviewCountPercentile(reviewCount)
        reasons.append(ScoreReason(
            id: "obscurity",
            label: "未知度",
            detail: "口コミ数は候補\(pool.count)件の中で少ない方から\(Int((percentile * 100).rounded()))%",
            delta: h * obscurity
        ))

        // メディア露出・有名語は「すでに知られている」根拠として未知度を下げる
        if let media = place.webMentions?.mediaCount, media > 0 {
            let before = obscurity
            obscurity *= 0.6
            reasons.append(ScoreReason(
                id: "media",
                label: "メディア掲載",
                detail: "テレビ・ニュース・グルメ記事で\(media)件",
                delta: -h * (before - obscurity)
            ))
        }
        let authenticReviewTexts = (place.reviewDetails?.filter { !$0.isSuspected }.map { $0.text }) ?? (place.reviews ?? [])
        let text = ([place.name] + authenticReviewTexts).joined(separator: " ")
        let famousHits = famousWords.filter { text.contains($0) }
        if !famousHits.isEmpty {
            let before = obscurity
            obscurity *= pow(0.85, Double(min(famousHits.count, 2)))
            reasons.append(ScoreReason(
                id: "famous",
                label: "有名を示す語",
                detail: "口コミに「\(famousHits.prefix(3).joined(separator: "」「"))」",
                delta: -h * (before - obscurity)
            ))
        }

        // 新しさ
        let recency = recencyScore(latestReview: place.latestReviewDate, hasReviewData: hasReviewData, now: now)
        if let recency = recency {
            let detail: String
            if let latest = place.latestReviewDate {
                let months = Int(now.timeIntervalSince(latest) / (30 * 86_400))
                detail = months < 1 ? "最新の口コミは今月" : "最新の口コミは\(months)か月前"
            } else {
                detail = "口コミ本文がありません"
            }
            reasons.append(ScoreReason(id: "recency", label: "新しさ", detail: detail, delta: 0.25 * recency))
        }

        // ネット上の本物の口コミ
        let genuine = genuineMentionScore(place.webMentions)
        if let mentions = place.webMentions {
            let excluded = mentions.promotionalCount
            let detail = mentions.genuineCount > 0
                ? "ブログ・SNSで\(mentions.genuineCount)件" + (excluded > 0 ? "（PR・広告\(excluded)件は除外）" : "")
                : "ブログ・SNSでの言及なし" + (excluded > 0 ? "（PR・広告\(excluded)件は除外）" : "")
            reasons.append(ScoreReason(id: "genuine", label: "ネットの口コミ", detail: detail, delta: 0.3 * genuine))
        }

        var total = (1 - h) * quality + h * obscurity + 0.25 * (recency ?? 0.6) + 0.3 * genuine

        // 好みタグ・学習タグ・避けたいタグ・穴場語
        let moodHits = profile.moodTags.filter { text.contains($0) }
        if !moodHits.isEmpty {
            let delta = min(0.45, 0.15 * Double(moodHits.count))
            total += delta
            reasons.append(ScoreReason(id: "mood", label: "好みの雰囲気", detail: "「\(moodHits.joined(separator: "」「"))」", delta: delta))
        }
        let learnedHits = learnedTags.filter { !profile.moodTags.contains($0) && text.contains($0) }
        if !learnedHits.isEmpty {
            let delta = min(0.3, 0.1 * Double(learnedHits.count))
            total += delta
            reasons.append(ScoreReason(id: "learned", label: "あなたの傾向", detail: "「\(learnedHits.joined(separator: "」「"))」", delta: delta))
        }
        let avoidHits = profile.avoidTags.filter { text.contains($0) }
        if !avoidHits.isEmpty {
            let delta = -0.3 * Double(avoidHits.count)
            total += delta
            reasons.append(ScoreReason(id: "avoid", label: "避けたいもの", detail: "「\(avoidHits.joined(separator: "」「"))」", delta: delta))
        }
        let hiddenHits = hiddenGemWords.filter { text.contains($0) }
        if !hiddenHits.isEmpty {
            let delta = min(0.24, 0.08 * Double(hiddenHits.count))
            total += delta
            reasons.append(ScoreReason(id: "hiddenWords", label: "穴場を示す語", detail: "「\(hiddenHits.prefix(3).joined(separator: "」「"))」", delta: delta))
        }

        // チェーン店は穴場志向と相反するため減点
        let chain = isLikelyChain(place, pool: pool)
        if chain {
            total -= 0.5
            let detail = pool.sameNameCount(place) >= 2 ? "候補の中に同名の店が\(pool.sameNameCount(place))件" : "全国チェーンの店名"
            reasons.append(ScoreReason(id: "chain", label: "チェーン", detail: detail, delta: -0.5))
        }

        // 裏付けの少なさ
        let genuineCount = place.webMentions?.genuineCount ?? 0
        let lowEvidence = reviewCount < minReviewsForEvidence && genuineCount == 0
        if lowEvidence {
            let before = total
            total *= 0.8
            reasons.append(ScoreReason(
                id: "lowEvidence",
                label: "情報が少ない",
                detail: "口コミ\(reviewCount)件・ネット上の言及なし",
                delta: total - before
            ))
        }

        let badge: ScoredPlace.Badge
        if chain {
            badge = .none
        } else if obscurity >= 0.6 && quality >= 0.5 && !lowEvidence {
            badge = .hiddenGem
        } else if obscurity >= 0.6 && lowEvidence {
            badge = .unverified
        } else {
            badge = .none
        }

        return ScoredPlace(
            place: place,
            total: total,
            quality: quality,
            obscurity: obscurity,
            recency: recency,
            genuineMention: genuine,
            reasons: reasons,
            badge: badge
        )
    }

    /// プロファイルに基づいて検索結果を絞り込み＆採点＆並べ替え
    /// - knownIds: 「行った」「知ってた」「興味なし」と記録した店（結果から外す）
    static func evaluate(
        _ places: [Place],
        profile: TasteProfile,
        learnedTags: [String] = [],
        knownIds: Set<String> = [],
        now: Date = Date()
    ) -> [ScoredPlace] {
        let pool = PoolStatistics(places: places)
        return places
            .filter { place in
                if knownIds.contains(place.id) {
                    return false
                }
                if profile.excludeChains && isLikelyChain(place, pool: pool) {
                    return false
                }
                if let maxReviews = profile.maxReviewCount,
                   let reviews = place.userRatingsTotal,
                   reviews > maxReviews {
                    return false
                }
                return true
            }
            .map { score($0, pool: pool, profile: profile, learnedTags: learnedTags, now: now) }
            .sorted { $0.total > $1.total }
    }

    /// 並べ替えだけが必要な場合（採点結果は捨てる）
    static func rank(
        _ places: [Place],
        profile: TasteProfile,
        learnedTags: [String] = [],
        knownIds: Set<String> = [],
        now: Date = Date()
    ) -> [Place] {
        evaluate(places, profile: profile, learnedTags: learnedTags, knownIds: knownIds, now: now).map { $0.place }
    }
}
