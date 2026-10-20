import SwiftUI

/// 検索条件指定パネルビュー
struct FilterPanelView: View {
    @ObservedObject var searchViewModel: SearchViewModel
    @ObservedObject var mapViewModel: MapViewModel
    @ObservedObject var tasteProfileViewModel: TasteProfileViewModel
    @ObservedObject var favoritesViewModel: FavoritesViewModel
    @ObservedObject var knownPlacesViewModel: KnownPlacesViewModel
    @Binding var isExpanded: Bool
    @State private var showPresetSheet = false
    @State private var showSavePresetAlert = false
    @State private var showTasteProfileSheet = false
    @State private var presetName = ""

    var body: some View {
        VStack(spacing: 12) {
            // ヘッダー（タップで開閉して地図を広く見られる）
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() }
            }) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.blue)
                    Text("検索条件")
                        .font(.headline)
                        .foregroundColor(.primary)
                    if !isExpanded {
                        Text(collapsedSummary)
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    Spacer()
                    if isExpanded {
                        Button(action: { searchViewModel.resetFilter() }) {
                            Text("リセット")
                                .font(.caption)
                        }
                    }
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, isExpanded ? 0 : 12)

            if isExpanded {
            ScrollView {
                VStack(spacing: 12) {
                    // 店名での絞り込み（取得した候補に対してクライアント側で適用）
                    VStack(alignment: .leading, spacing: 6) {
                        Text("店名で絞り込み（任意）")
                            .font(.caption)
                            .foregroundColor(.gray)
                        TextField("店名の一部", text: $searchViewModel.currentFilter.name)
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
                                Text(category.label).tag(category)
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

                    // 候補集めの徹底度（API呼び出し回数）
                    VStack(alignment: .leading, spacing: 6) {
                        Text("候補の集め方：検索\(searchViewModel.currentFilter.thoroughness.maxAPICalls)回まで")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Picker("候補の集め方", selection: $searchViewModel.currentFilter.thoroughness) {
                            ForEach(SearchFilter.Thoroughness.allCases, id: \.self) { level in
                                Text(level.label).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("範囲を小さな円に分けて距離順に取るため、回数が多いほど人気順では出てこない店まで拾えます")
                            .font(.caption2)
                            .foregroundColor(.gray)
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

                    // 好みの設定（このアプリの核となる「穴場発見」設定への入口）
                    Button(action: { showTasteProfileSheet = true }) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("好みの設定")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Text(tasteProfileViewModel.summary)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(12)
                        .background(Color.purple.opacity(0.08))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

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
                        searchViewModel.performSearch(
                            with: mapViewModel,
                            profile: tasteProfileViewModel.profile,
                            learnedTags: favoritesViewModel.learnedMoodTags,
                            knownIds: excludedIds
                        )
                    }) {
                        HStack {
                            if mapViewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(mapViewModel.isLoading ? (mapViewModel.progress ?? "検索中...") : "知らない店を探す")
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
            } // if isExpanded
        }
        .sheet(isPresented: $showPresetSheet) {
            PresetsListView(
                searchViewModel: searchViewModel,
                isPresented: $showPresetSheet
            )
        }
        .sheet(isPresented: $showTasteProfileSheet) {
            TasteProfileView(
                tasteProfileViewModel: tasteProfileViewModel,
                learnedTags: favoritesViewModel.learnedMoodTags,
                isWebMentionAvailable: mapViewModel.isWebMentionAvailable
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

    /// 結果から外す店：既知リストに加え、お気に入り（すでに知っている店）も外す
    private var excludedIds: Set<String> {
        knownPlacesViewModel.knownIds.union(favoritesViewModel.favorites.map { $0.id })
    }

    /// 収納時にヘッダーへ表示する現在の検索条件の要約
    private var collapsedSummary: String {
        let filter = searchViewModel.currentFilter
        var parts: [String] = []
        parts.append((filter.categories.first ?? .restaurant).label)
        parts.append("\(String(format: "%.1f", filter.maxDistance))km")
        if filter.minRating > 0 {
            parts.append("★\(String(format: "%.1f", filter.minRating))+")
        }
        parts.append(tasteProfileViewModel.summary)
        return parts.joined(separator: "・")
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
                                    Text("\(searchViewModel.savedPresets[key]?.categories.first?.label ?? "")")
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
        mapViewModel: MapViewModel(),
        tasteProfileViewModel: TasteProfileViewModel(),
        favoritesViewModel: FavoritesViewModel(),
        knownPlacesViewModel: KnownPlacesViewModel(),
        isExpanded: .constant(true)
    )
}
