import SwiftUI

/// お気に入り一覧画面（会員限定）
/// 未サインインの場合は会員登録画面を表示する
struct FavoritesListView: View {
    @ObservedObject var favoritesViewModel: FavoritesViewModel
    @ObservedObject var authViewModel: AuthViewModel
    @EnvironmentObject var knownPlacesViewModel: KnownPlacesViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedPlace: Place? = nil

    var body: some View {
        NavigationView {
            Group {
                if !authViewModel.isSignedIn {
                    LoginView(authViewModel: authViewModel)
                } else if favoritesViewModel.favorites.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "heart.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("お気に入りはまだありません")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Text("お店の詳細画面で♡をタップすると追加できます")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                } else {
                    List {
                        ForEach(favoritesViewModel.favorites) { place in
                            Button(action: { selectedPlace = place }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "heart.fill")
                                        .foregroundColor(.pink)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(place.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        HStack(spacing: 8) {
                                            if let rating = place.rating {
                                                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.orange)
                                            }
                                            Text(place.address)
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            favoritesViewModel.removeFavorites(at: offsets)
                        }
                    }
                }
            }
            .navigationTitle("お気に入り")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(item: $selectedPlace) { place in
                DetailView(place: place)
                    .environmentObject(authViewModel)
                    .environmentObject(favoritesViewModel)
                    .environmentObject(knownPlacesViewModel)
            }
        }
    }
}

#Preview {
    FavoritesListView(
        favoritesViewModel: FavoritesViewModel(),
        authViewModel: AuthViewModel()
    )
    .environmentObject(KnownPlacesViewModel())
}
