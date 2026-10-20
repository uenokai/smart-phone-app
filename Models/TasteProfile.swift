import Foundation

/// ユーザーの好みプロファイル
/// 「メジャーなお店・スポット以外を知れる」というこのアプリの価値の中心となる設定
struct TasteProfile: Codable, Equatable {
    /// 好みの雰囲気タグ（店名・口コミテキストとのマッチングに使用）
    var moodTags: [String] = []
    /// 避けたい要素タグ
    var avoidTags: [String] = []
    /// 穴場重視度（0.0=評価の高さ重視 〜 1.0=穴場度重視）
    var hiddenGemWeight: Double = 0.7
    /// 全国チェーン店を検索結果から除外する
    var excludeChains: Bool = true
    /// 口コミ数がこの値を超える「メジャーな場所」を除外する（nil で無効）
    var maxReviewCount: Int? = nil
    /// 「行った」「知ってた」「興味なし」と記録した店とお気に入りを結果から外す
    var hideKnownPlaces: Bool = true
    /// ネット上の口コミ（ブログ・SNS）を検索して判定に使う（Brave Search API キーが必要）
    var useWebMentions: Bool = true

    /// 選択肢として提示する雰囲気タグ
    static let moodTagOptions: [String] = [
        "隠れ家", "静か", "落ち着く", "レトロ", "老舗", "地元",
        "個人経営", "アットホーム", "おしゃれ", "こだわり", "穴場", "路地裏"
    ]

    /// 選択肢として提示する避けたいタグ
    static let avoidTagOptions: [String] = [
        "行列", "混雑", "観光客", "騒がしい", "うるさい"
    ]

    /// メジャー除外の上限として提示する口コミ数の選択肢
    static let maxReviewCountOptions: [Int?] = [nil, 300, 100, 50]

    init() {}

    // 旧バージョンで保存した設定に無い項目は既定値で補う
    enum CodingKeys: String, CodingKey {
        case moodTags, avoidTags, hiddenGemWeight, excludeChains, maxReviewCount, hideKnownPlaces, useWebMentions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        moodTags = try c.decodeIfPresent([String].self, forKey: .moodTags) ?? []
        avoidTags = try c.decodeIfPresent([String].self, forKey: .avoidTags) ?? []
        hiddenGemWeight = try c.decodeIfPresent(Double.self, forKey: .hiddenGemWeight) ?? 0.7
        excludeChains = try c.decodeIfPresent(Bool.self, forKey: .excludeChains) ?? true
        maxReviewCount = try c.decodeIfPresent(Int.self, forKey: .maxReviewCount)
        hideKnownPlaces = try c.decodeIfPresent(Bool.self, forKey: .hideKnownPlaces) ?? true
        useWebMentions = try c.decodeIfPresent(Bool.self, forKey: .useWebMentions) ?? true
    }
}
