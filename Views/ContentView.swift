import SwiftUI
import CoreLocation

/// アプリのメイン画面ビュー
struct ContentView: View {
    @StateObject private var mapViewModel = MapViewModel()
    @StateObject private var searchViewModel = SearchViewModel()
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var favoritesViewModel = FavoritesViewModel()
    @StateObject private var tasteProfileViewModel = TasteProfileViewModel()
    @State private var showAccountView = false
    @State private var showFavoritesView = false
    @State private var isPanelExpanded = true

    var body: some View {
        ZStack {
            // マップビュー
            MapView(viewModel: mapViewModel, places: mapViewModel.places)
                .ignoresSafeArea()
                .onAppear {
                    mapViewModel.startUpdatingLocation()
                }

            // 下部エリア（結果カード + 開閉式フィルターパネル）
            VStack(spacing: 0) {
                Spacer()

                // 結果カードの横スクロール（パネル収納時のみ表示し、地図と両立させる）
                if !mapViewModel.places.isEmpty && !isPanelExpanded {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(mapViewModel.places) { place in
                                PlaceCardView(
                                    place: place,
                                    distanceText: distanceText(to: place)
                                )
                                .onTapGesture {
                                    mapViewModel.selectedPlace = place
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
                    isExpanded: $isPanelExpanded
                )
                .frame(maxHeight: isPanelExpanded ? 400 : nil)
                .background(Color(.systemBackground))
                .cornerRadius(16, corners: [.topLeft, .topRight])
                .shadow(radius: 10)
            }
            .ignoresSafeArea(.keyboard)

            // 上部バー（検索結果件数 + アカウント / お気に入りボタン）
            VStack {
                HStack(alignment: .top) {
                    if !mapViewModel.places.isEmpty {
                        Text("検索結果：\(mapViewModel.places.count)件")
                            .font(.caption)
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
        .sheet(item: $mapViewModel.selectedPlace) { place in
            DetailView(place: place)
                .environmentObject(authViewModel)
                .environmentObject(favoritesViewModel)
        }
        .sheet(isPresented: $showAccountView) {
            AccountView(
                authViewModel: authViewModel,
                favoritesViewModel: favoritesViewModel
            )
        }
        .sheet(isPresented: $showFavoritesView) {
            FavoritesListView(
                favoritesViewModel: favoritesViewModel,
                authViewModel: authViewModel
            )
        }
        .onAppear {
            favoritesViewModel.setUser(authViewModel.currentUser?.id)
        }
        .onChange(of: authViewModel.currentUser) { user in
            favoritesViewModel.setUser(user?.id)
        }
        // 検索が完了して結果があればパネルを収納し、地図と結果カードを見せる
        .onChange(of: mapViewModel.isLoading) { isLoading in
            if !isLoading && !mapViewModel.places.isEmpty {
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
    let place: Place
    var distanceText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 穴場バッジ（このアプリの核となる価値の可視化）
            if RecommendationEngine.isHiddenGem(place) {
                Text("💎 穴場")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.15))
                    .foregroundColor(.purple)
                    .cornerRadius(8)
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

            Text(place.address)
                .font(.caption2)
                .foregroundColor(.gray)
                .lineLimit(2)

            Spacer()

            if let distanceText = distanceText {
                Label(distanceText, systemImage: "figure.walk")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
        }
        .padding(12)
        .frame(width: 160, height: 150)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 4)
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
