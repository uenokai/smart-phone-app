import Foundation
import Combine

/// 検索条件を管理するViewModel
@MainActor
class SearchViewModel: ObservableObject {
    @Published var currentFilter: SearchFilter = SearchFilter()
    @Published var savedPresets: [String: SearchFilter] = [:]
    @Published var showSavePresetAlert: Bool = false
    @Published var presetName: String = ""

    private let userDefaults = UserDefaults.standard
    private let presetsKey = "search_presets"

    init() {
        loadPresets()
    }

    /// 現在のフィルター条件と好みプロファイルで検索実行
    /// learnedTags はお気に入りの傾向から自動学習したタグ、knownIds は結果から外す既知の店
    func performSearch(
        with mapViewModel: MapViewModel,
        profile: TasteProfile = TasteProfile(),
        learnedTags: [String] = [],
        knownIds: Set<String> = []
    ) {
        Task {
            await mapViewModel.searchPlaces(
                filter: currentFilter,
                profile: profile,
                learnedTags: learnedTags,
                knownIds: knownIds
            )
        }
    }

    /// プリセットを保存
    func savePreset(name: String) {
        savedPresets[name] = currentFilter
        persistPresets()
    }

    /// プリセットを読み込み
    func loadPreset(name: String) {
        if let preset = savedPresets[name] {
            currentFilter = preset
        }
    }

    /// プリセットを削除
    func deletePreset(name: String) {
        savedPresets.removeValue(forKey: name)
        persistPresets()
    }

    // MARK: - Private Methods

    private func loadPresets() {
        if let data = userDefaults.data(forKey: presetsKey),
           let decoded = try? JSONDecoder().decode([String: SearchFilter].self, from: data) {
            self.savedPresets = decoded
        }
    }

    private func persistPresets() {
        if let encoded = try? JSONEncoder().encode(savedPresets) {
            userDefaults.set(encoded, forKey: presetsKey)
        }
    }

    /// フィルター条件をリセット
    func resetFilter() {
        currentFilter = SearchFilter()
    }

    /// 価格レベルの表示用テキスト
    func priceText(_ level: Int) -> String {
        String(repeating: "¥", count: level)
    }
}
