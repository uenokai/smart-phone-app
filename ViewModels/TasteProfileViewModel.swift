import Foundation

/// 好みプロファイルを管理するViewModel
@MainActor
class TasteProfileViewModel: ObservableObject {
    @Published var profile: TasteProfile = TasteProfile() {
        didSet { persist() }
    }

    private let userDefaults = UserDefaults.standard
    private let profileKey = "taste_profile"

    init() {
        load()
    }

    func toggleMoodTag(_ tag: String) {
        if profile.moodTags.contains(tag) {
            profile.moodTags.removeAll { $0 == tag }
        } else {
            profile.moodTags.append(tag)
        }
    }

    func toggleAvoidTag(_ tag: String) {
        if profile.avoidTags.contains(tag) {
            profile.avoidTags.removeAll { $0 == tag }
        } else {
            profile.avoidTags.append(tag)
        }
    }

    /// 設定内容の短い要約（検索パネルに表示する）
    var summary: String {
        var parts: [String] = []
        parts.append(profile.hiddenGemWeight >= 0.5 ? "穴場重視" : "評価重視")
        if profile.excludeChains {
            parts.append("チェーン除外")
        }
        if !profile.moodTags.isEmpty {
            parts.append(profile.moodTags.prefix(3).joined(separator: "・"))
        }
        return parts.joined(separator: " / ")
    }

    // MARK: - Private Methods

    private func load() {
        if let data = userDefaults.data(forKey: profileKey),
           let decoded = try? JSONDecoder().decode(TasteProfile.self, from: data) {
            profile = decoded
        }
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(profile) {
            userDefaults.set(encoded, forKey: profileKey)
        }
    }
}
