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

    /// 現在のフィルター条件で検索実行
    func performSearch(with mapViewModel: MapViewModel) {
        Task {
            await mapViewModel.searchPlaces(filter: currentFilter)
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
