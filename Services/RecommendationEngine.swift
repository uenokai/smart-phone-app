import Foundation

/// 好みプロファイルに基づいて検索結果を採点・並べ替えるエンジン
/// 「評価は高いのに口コミが少ない＝まだ知られていない良いお店」を上位に出すのがこのアプリの核
struct RecommendationEngine {

    /// 全国チェーンと見なす店名キーワード（穴場優先時の減点・除外対象）
    static let chainKeywords: [String] = [
        "マクドナルド", "スターバックス", "ドトール", "タリーズ", "サイゼリヤ",
        "ガスト", "すき家", "吉野家", "松屋", "CoCo壱番屋", "ココイチ",
        "ケンタッキー", "モスバーガー", "丸亀製麺", "はなまるうどん",
        "くら寿司", "スシロー", "はま寿司", "かっぱ寿司", "コメダ珈琲",
        "デニーズ", "ジョナサン", "バーミヤン", "ロイヤルホスト", "大戸屋",
        "餃子の王将", "日高屋", "幸楽苑", "リンガーハット", "ミスタードーナツ",
        "サンマルクカフェ", "エクセルシオール", "プロント", "びっくりドンキー"
    ]

    /// 口コミがこの件数以上なら「メジャーな場所」と見なす基準値
    static let majorReviewThreshold = 500

    /// お店が全国チェーンらしいか判定
    static func isLikelyChain(_ place: Place) -> Bool {
        chainKeywords.contains { place.name.contains($0) }
    }

    /// 穴場度（0.0〜1.0）：評価が高いのに口コミが少ないほど高くなる
    static func hiddenGemScore(for place: Place) -> Double {
        guard let rating = place.rating else { return 0 }
        let quality = max(0, (rating - 3.0) / 2.0) // 評価3.0で0、5.0で1
        let reviews = place.userRatingsTotal ?? 0
        let obscurity = max(0, 1 - Double(reviews) / Double(majorReviewThreshold))
        // 口コミが極端に少ない店は評価の信頼度が低いため割り引く
        let confidence = reviews >= 5 ? 1.0 : 0.5
        return quality * obscurity * confidence
    }

    /// 穴場バッジを表示するかどうか
    static func isHiddenGem(_ place: Place) -> Bool {
        hiddenGemScore(for: place) >= 0.5
    }

    /// 好みプロファイルとの一致度で総合スコアを計算
    /// learnedTags はお気に入りの傾向から自動学習したタグ（明示指定より弱めに加点）
    static func score(_ place: Place, profile: TasteProfile, learnedTags: [String] = []) -> Double {
        var score = 0.0

        // 基本評価と穴場度を、穴場重視度に応じてブレンド
        if let rating = place.rating {
            score += (rating / 5.0) * (1.0 - profile.hiddenGemWeight)
        }
        score += hiddenGemScore(for: place) * profile.hiddenGemWeight

        // 店名・口コミテキストと好みタグの一致で加点、避けたいタグで減点
        let text = ([place.name] + (place.reviews ?? [])).joined(separator: " ")
        for tag in profile.moodTags where text.contains(tag) {
            score += 0.15
        }
        // 自動学習タグ（ユーザーが明示的に選んだタグと重複するものは除く）
        for tag in learnedTags where !profile.moodTags.contains(tag) && text.contains(tag) {
            score += 0.1
        }
        for tag in profile.avoidTags where text.contains(tag) {
            score -= 0.3
        }

        // チェーン店は穴場志向と相反するため減点
        if isLikelyChain(place) {
            score -= 0.5
        }

        return score
    }

    /// プロファイルに基づいて検索結果を絞り込み＆並べ替え
    static func rank(_ places: [Place], profile: TasteProfile, learnedTags: [String] = []) -> [Place] {
        places
            .filter { place in
                if profile.excludeChains && isLikelyChain(place) {
                    return false
                }
                if let maxReviews = profile.maxReviewCount,
                   let reviews = place.userRatingsTotal,
                   reviews > maxReviews {
                    return false
                }
                return true
            }
            .sorted {
                score($0, profile: profile, learnedTags: learnedTags) >
                score($1, profile: profile, learnedTags: learnedTags)
            }
    }
}
