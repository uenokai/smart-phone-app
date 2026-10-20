import Foundation

/// 店名の正規化（支店名の除去・比較用の整形）
enum NameNormalizer {
    /// 業態を表すだけの語。これだけが残った店名は照合に使えない（無関係なページに一致してしまう）
    static let genericWords: Set<String> = [
        "大衆酒場", "居酒屋", "喫茶", "喫茶店", "純喫茶", "ラーメン", "らーめん", "カフェ", "食堂", "焼肉", "焼き肉", "寿司", "すし",
        "バー", "珈琲", "コーヒー", "レストラン", "定食", "そば", "蕎麦", "うどん", "中華", "中華料理", "イタリアン", "フレンチ",
        "ビストロ", "ダイニング", "酒場", "立ち飲み", "串焼き", "もつ焼き", "焼鳥", "焼き鳥", "天ぷら", "とんかつ", "餃子",
        "bar", "cafe", "coffee", "restaurant", "kitchen", "dining", "本店", "支店"
    ]

    /// 支店らしい末尾（「渋谷店」「本店」「2号店」など）を取り除いた店名
    /// 例：「スターバックス 渋谷店」→「スターバックス」、「日高屋 本店」→「日高屋」
    /// Google の店名は支店名の前に空白が入ることがほとんどなので、空白で区切ったトークン単位で判定する。
    /// 空白が無い名前（「マクドナルド新宿西口店」）は地名の区切りが判別できないため、「本店」「支店」「N号店」だけを落とす。
    /// 取り除いた結果が短すぎる場合（「喫茶店」など）は元の名前を返す
    static func baseName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace || $0 == "　" }).map(String.init)

        if tokens.count >= 2 {
            var kept = tokens
            while kept.count >= 2, let last = kept.last, isBranchToken(last) {
                kept.removeLast()
            }
            let joined = kept.joined(separator: " ")
            return joined.count >= 2 ? joined : trimmed
        }

        let pattern = "(本店|支店|[0-9０-９]{1,3}号店)$"
        if let range = trimmed.range(of: pattern, options: .regularExpression) {
            let base = String(trimmed[..<range.lowerBound])
            return base.count >= 2 ? base : trimmed
        }
        return trimmed
    }

    /// 支店名らしいトークンか
    static func isBranchToken(_ token: String) -> Bool {
        if token.hasSuffix("店") { return true }
        let pattern = "^(本店|支店|[0-9０-９]{1,3}号店|.{1,6}(駅前|駅|口|本館|別館|新館))$"
        return token.range(of: pattern, options: .regularExpression) != nil
    }

    /// 業態を表すだけの語か、短すぎて照合に使えない語か
    static func isGeneric(_ name: String) -> Bool {
        let key = comparable(name)
        return key.count <= 2 || genericWords.contains(key)
    }

    /// 比較用に空白・記号を取り除き小文字にした文字列
    static func comparable(_ text: String) -> String {
        var view = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar) {
                continue
            }
            view.append(scalar)
        }
        return String(view).lowercased()
    }
}
