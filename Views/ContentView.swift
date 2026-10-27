import SwiftUI
import CoreLocation

/// アプリのメイン画面ビュー
struct ContentView: View {
    @StateObject private var mapViewModel = MapViewModel()
    @StateObject private var searchViewModel = SearchViewModel()
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var favoritesViewModel = FavoritesViewModel()
    @StateObject private var tasteProfileViewModel = TasteProfileViewModel()
    @StateObject private var knownPlacesViewModel = KnownPlacesViewModel()
    @State private var showAccountView = false
    @State private var showFavoritesView = false
    @State private var isPanelExpanded = true

    var body: some View {
        ZStack {
            // マップビュー
            MapView(viewModel: mapViewModel, results: mapViewModel.results)
                .ignoresSafeArea()
                .onAppear {
                    mapViewModel.startUpdatingLocation()
                }

            // 下部エリア（結果カード + 開閉式フィルターパネル）
            VStack(spacing: 0) {
                Spacer()

                // 結果カードの横スクロール（パネル収納時のみ表示し、地図と両立させる）
                if !mapViewModel.results.isEmpty && !isPanelExpanded {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(mapViewModel.results) { scored in
                                PlaceCardView(
                                    scored: scored,
                                    distanceText: distanceText(to: scored.place)
                                )
                                .onTapGesture {
                                    mapViewModel.selectedResult = scored
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }

                FilterPanelView(
                    searchViewModel: searchViewModel,
                    mapViewModel: mapViewModel,
                    tasteProfileViewModel: tasteProfileViewModel,
                    favoritesViewModel: favoritesViewModel,
                    knownPlacesViewModel: knownPlacesViewModel,
                    isExpanded: $isPanelExpanded
                )
                .frame(maxHeight: isPanelExpanded ? 440 : nil)
                .background(Color(.systemBackground))
                .cornerRadius(16, corners: [.topLeft, .topRight])
                .shadow(radius: 10)
            }
            .ignoresSafeArea(.keyboard)

            // 上部バー（検索の要約 + アカウント / お気に入りボタン）
            VStack {
                HStack(alignment: .top) {
                    if let summary = mapViewModel.searchSummary, !mapViewModel.results.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("表示 \(summary.shownCount)件")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(summary.text)
                                .font(.caption2)
                        }
                        .padding(8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }

                    Spacer()

                    VStack(spacing: 10) {
                        // アカウントボタン
                        Button(action: { showAccountView = true }) {
                            Image(systemName: authViewModel.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                                .font(.title2)
                                .foregroundColor(.blue)
                                .padding(10)
                                .background(Color(.systemBackground))
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }

                        // お気に入りボタン
                        Button(action: { showFavoritesView = true }) {
                            Image(systemName: "heart.fill")
                                .font(.title2)
                                .foregroundColor(.pink)
                                .padding(10)
                                .background(Color(.systemBackground))
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                    }
                }
                .padding()

                Spacer()
            }
        }
        // ピンタップ・カードタップの両方からここで詳細を開く
        .sheet(item: $mapViewModel.selectedResult) { scored in
            DetailView(place: scored.place, scored: scored, placesService: mapViewModel.placesService)
                .environmentObject(authViewModel)
                .environmentObject(favoritesViewModel)
                .environmentObject(knownPlacesViewModel)
        }
        .sheet(isPresented: $showAccountView) {
            AccountView(
                authViewModel: authViewModel,
                favoritesViewModel: favoritesViewModel,
                knownPlacesViewModel: knownPlacesViewModel
            )
        }
        .sheet(isPresented: $showFavoritesView) {
            FavoritesListView(
                favoritesViewModel: favoritesViewModel,
                authViewModel: authViewModel
            )
            .environmentObject(knownPlacesViewModel)
        }
        .onAppear {
            favoritesViewModel.setUser(authViewModel.currentUser?.id)
        }
        .onChange(of: authViewModel.currentUser) { user in
            favoritesViewModel.setUser(user?.id)
        }
        // 検索が完了して結果があればパネルを収納し、地図と結果カードを見せる
        .onChange(of: mapViewModel.isLoading) { isLoading in
            if !isLoading && !mapViewModel.results.isEmpty {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isPanelExpanded = false
                }
            }
        }
    }

    /// 現在地からの距離の表示用テキスト（現在地が不明なら nil）
    private func distanceText(to place: Place) -> String? {
        guard let user = mapViewModel.userLocation else { return nil }
        let from = CLLocation(latitude: user.latitude, longitude: user.longitude)
        let to = CLLocation(latitude: place.latitude, longitude: place.longitude)
        let meters = from.distance(from: to)
        return meters < 1000
            ? String(format: "%.0fm", meters)
            : String(format: "%.1fkm", meters / 1000)
    }
}

/// 検索結果のカード表示
struct PlaceCardView: View {
    let scored: ScoredPlace
    var distanceText: String? = nil

    private var place: Place { scored.place }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // 穴場・未確認バッジ（このアプリの核となる価値の可視化）
                if let label = scored.badge.label {
                    Text(label)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(badgeColor.opacity(0.15))
                        .foregroundColor(badgeColor)
                        .cornerRadius(8)
                }
                Spacer(minLength: 0)
                if let mentions = place.webMentions, mentions.genuineCount > 0 {
                    Label("\(mentions.genuineCount)", systemImage: "text.bubble")
                        .font(.caption2)
                        .foregroundColor(.teal)
                }
            }

            Text(place.name)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let rating = place.rating {
                    Label("\(String(format: "%.1f", rating))", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                if let reviews = place.userRatingsTotal {
                    Text("(\(reviews)件)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                if let priceLevel = place.priceLevel {
                    Text(String(repeating: "¥", count: priceLevel))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            // 上位に来た理由（詳細画面で内訳を見られる）
            if !scored.headline.isEmpty {
                Text(scored.headline)
                    .font(.caption2)
                    .foregroundColor(.purple)
                    .lineLimit(1)
            }

            Spacer()

            HStack {
                if let distanceText = distanceText {
                    Label(distanceText, systemImage: "figure.walk")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
                Spacer()
                Text(String(format: "%.2f", scored.total))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .frame(width: 170, height: 160)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 4)
    }

    private var badgeColor: Color {
        switch scored.badge {
        case .hiddenGem: return .purple
        case .unverified: return .teal
        case .none: return .gray
        }
    }
}

// MARK: - RoundedCorner Modifier

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

#Preview {
    ContentView()
}
