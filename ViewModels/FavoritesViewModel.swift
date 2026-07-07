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
