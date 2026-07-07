import SwiftUI

/// 検索条件指定パネルビュー
struct FilterPanelView: View {
    @ObservedObject var searchViewModel: SearchViewModel
    @ObservedObject var mapViewModel: MapViewModel
    @State private var showPresetSheet = false
    @State private var showSavePresetAlert = false
    @State private var presetName = ""

    var body: some View {
        VStack(spacing: 12) {
            // ヘッダー
            HStack {
                Text("検索条件")
                    .font(.headline)
                Spacer()
                Button(action: { searchViewModel.resetFilter() }) {
                    Text("リセット")
                        .font(.caption)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)

            ScrollView {
                VStack(spacing: 12) {
                    // キーワード検索
                    VStack(alignment: .leading, spacing: 6) {
                        Text("キーワード")
                            .font(.caption)
                            .foregroundColor(.gray)
                        TextField("お店の名前など", text: $searchViewModel.currentFilter.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // カテゴリ選択
                    VStack(alignment: .leading, spacing: 6) {
                        Text("カテゴリ")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Picker("カテゴリ", selection: Binding(
                            get: { searchViewModel.currentFilter.categories.first ?? .restaurant },
                            set: { searchViewModel.currentFilter.categories = [$0] }
                        )) {
                            ForEach(Place.PlaceCategory.allCases, id: \.self) { category in
                                Text(categoryLabel(category)).tag(category)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // 価格帯
                    VStack(alignment: .leading, spacing: 6) {
                        Text("価格帯：\(searchViewModel.priceText(searchViewModel.currentFilter.minPriceLevel)) 〜 \(searchViewModel.priceText(searchViewModel.currentFilter.maxPriceLevel))")
                            .font(.caption)
                            .foregroundColor(.gray)
                        HStack(spacing: 12) {
                            Picker("最低価格", selection: $searchViewModel.currentFilter.minPriceLevel) {
                                ForEach(1...4, id: \.self) { level in
                                    Text(searchViewModel.priceText(level)).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)

                            Picker("最高価格", selection: $searchViewModel.currentFilter.maxPriceLevel) {
                                ForEach(1...4, id: \.self) { level in
                                    Text(searchViewModel.priceText(level)).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    // 距離
                    VStack(alignment: .leading, spacing: 6) {
                        Text("距離：\(String(format: "%.1f", searchViewModel.currentFilter.maxDistance))km以内")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Slider(
                            value: $searchViewModel.currentFilter.maxDistance,
                            in: 0.5...10.0,
                            step: 0.5
                        )
                    }

                    // 営業状況
                    Toggle("営業中のみ", isOn: $searchViewModel.currentFilter.includeOpen)

                    // 評価
                    VStack(alignment: .leading, spacing: 6) {
                        Text("最低評価：\(String(format: "%.1f", searchViewModel.currentFilter.minRating))⭐")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Slider(
                            value: $searchViewModel.currentFilter.minRating,
                            in: 0.0...5.0,
                            step: 0.5
                        )
                    }

                    Divider()

                    // アクションボタン
                    HStack(spacing: 12) {
                        Button(action: { showPresetSheet = true }) {
                            Label("プリセット", systemImage: "bookmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(action: { showSavePresetAlert = true }) {
                            Label("保存", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(action: {
                        searchViewModel.performSearch(with: mapViewModel)
                    }) {
                        HStack {
                            if mapViewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(mapViewModel.isLoading ? "検索中..." : "検索")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(mapViewModel.isLoading)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            if let error = mapViewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
                .padding(.horizontal)
            }
        }
        .sheet(isPresented: $showPresetSheet) {
            PresetsListView(
                searchViewModel: searchViewModel,
                isPresented: $showPresetSheet
            )
        }
        .alert("プリセットを保存", isPresented: $showSavePresetAlert) {
            TextField("プリセット名", text: $presetName)
            Button("保存") {
                if !presetName.isEmpty {
                    searchViewModel.savePreset(name: presetName)
                    presetName = ""
                }
            }
            Button("キャンセル", role: .cancel) { }
        }
    }

    private func categoryLabel(_ category: Place.PlaceCategory) -> String {
        switch category {
        case .restaurant: return "レストラン"
        case .cafe: return "カフェ"
        case .bar: return "バー"
        case .touristAttraction: return "観光地"
        case .museum: return "博物館"
        case .park: return "公園"
        }
    }
}

/// 保存済みプリセット一覧
struct PresetsListView: View {
    @ObservedObject var searchViewModel: SearchViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            List {
                if searchViewModel.savedPresets.isEmpty {
                    Text("保存済みプリセットはありません")
                        .foregroundColor(.gray)
                } else {
                    ForEach(searchViewModel.savedPresets.keys.sorted(), id: \.self) { key in
                        HStack {
                            Button(action: {
                                searchViewModel.loadPreset(name: key)
                                isPresented = false
                            }) {
                                VStack(alignment: .leading) {
                                    Text(key)
                                        .font(.headline)
                                    Text("\(searchViewModel.savedPresets[key]?.categories.first?.rawValue ?? "")")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            Spacer()
                            Button(role: .destructive, action: {
                                searchViewModel.deletePreset(name: key)
                            }) {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("プリセット")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { isPresented = false }
                }
            }
        }
    }
}

#Preview {
    FilterPanelView(
        searchViewModel: SearchViewModel(),
        mapViewModel: MapViewModel()
    )
}
