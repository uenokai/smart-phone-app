import Foundation

/// 「すでに知っている店」の記録
/// 目的は知らない店を知ることなので、行った店・知っていた店・興味のない店は以後の検索結果から外す
struct KnownPlace: Codable, Equatable, Identifiable {
    var id: String { placeId }
    let placeId: String
    let name: String
    let address: String
    let status: Status
    let recordedAt: Date

    enum Status: String, Codable, CaseIterable {
        case visited
        case known
        case notInterested

        var label: String {
            switch self {
            case .visited: return "行った"
            case .known: return "知ってた"
            case .notInterested: return "興味なし"
            }
        }

        var systemImage: String {
            switch self {
            case .visited: return "checkmark.circle"
            case .known: return "eye"
            case .notInterested: return "hand.thumbsdown"
            }
        }
    }
}

/// 既知の店を管理する ViewModel（端末内に保存。会員登録は不要）
@MainActor
class KnownPlacesViewModel: ObservableObject {
    @Published private(set) var knownPlaces: [KnownPlace] = []

    private let userDefaults: UserDefaults
    private let storageKey: String

    init(userDefaults: UserDefaults = .standard, storageKey: String = "known_places") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        load()
    }

    /// 検索結果から除外する店のID
    var knownIds: Set<String> {
        Set(knownPlaces.map { $0.placeId })
    }

    func status(of placeId: String) -> KnownPlace.Status? {
        knownPlaces.first { $0.placeId == placeId }?.status
    }

    /// 状態を記録する。同じ状態をもう一度選ぶと記録を取り消す
    func toggle(_ place: Place, status: KnownPlace.Status) {
        if self.status(of: place.id) == status {
            remove(placeId: place.id)
            return
        }
        knownPlaces.removeAll { $0.placeId == place.id }
        knownPlaces.insert(KnownPlace(
            placeId: place.id,
            name: place.name,
            address: place.address,
            status: status,
            recordedAt: Date()
        ), at: 0)
        persist()
    }

    func remove(placeId: String) {
        knownPlaces.removeAll { $0.placeId == placeId }
        persist()
    }

    func remove(at offsets: IndexSet) {
        knownPlaces.remove(atOffsets: offsets)
        persist()
    }

    func count(of status: KnownPlace.Status) -> Int {
        knownPlaces.filter { $0.status == status }.count
    }

    // MARK: - Private

    private func load() {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([KnownPlace].self, from: data) else {
            knownPlaces = []
            return
        }
        knownPlaces = decoded
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(knownPlaces) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }
}
