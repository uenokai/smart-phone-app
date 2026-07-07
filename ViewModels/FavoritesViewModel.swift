import Foundation

/// お気に入り（会員限定機能）を管理するViewModel
/// お気に入りは会員IDごとに分けてローカル保存する
@MainActor
class FavoritesViewModel: ObservableObject {
    @Published var favorites: [Place] = []

    private let userDefaults = UserDefaults.standard
    private var userId: String? = nil

    /// サインイン中の会員に切り替え（nil はサインアウト状態）
    func setUser(_ userId: String?) {
        self.userId = userId
        loadFavorites()
    }

    func isFavorite(_ place: Place) -> Bool {
        favorites.contains { $0.id == place.id }
    }

    func toggleFavorite(_ place: Place) {
        if isFavorite(place) {
            favorites.removeAll { $0.id == place.id }
        } else {
            favorites.append(place)
        }
        persistFavorites()
    }

    func removeFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        persistFavorites()
    }

    /// お気に入りの傾向から自動学習した雰囲気タグ
    /// 2件以上のお気に入りの店名・口コミに共通して現れるタグを「好みの傾向」と見なす
    var learnedMoodTags: [String] {
        guard favorites.count >= 2 else { return [] }

        var counts: [String: Int] = [:]
        for place in favorites {
            let text = ([place.name] + (place.reviews ?? [])).joined(separator: " ")
            for tag in TasteProfile.moodTagOptions where text.contains(tag) {
                counts[tag, default: 0] += 1
            }
        }

        return counts
            .filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }

    // MARK: - Private Methods

    private var storageKey: String? {
        userId.map { "favorites_\($0)" }
    }

    private func loadFavorites() {
        guard let key = storageKey,
              let data = userDefaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Place].self, from: data) else {
            favorites = []
            return
        }
        favorites = decoded
    }

    private func persistFavorites() {
        guard let key = storageKey else { return }
        if let encoded = try? JSONEncoder().encode(favorites) {
            userDefaults.set(encoded, forKey: key)
        }
    }
}
