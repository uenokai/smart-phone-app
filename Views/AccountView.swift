import SwiftUI

/// アカウント画面
/// サインイン済みならプロフィールとサインアウト、未サインインなら会員登録画面を表示
/// 既知の店（行った・知ってた・興味なし）の一覧もここから開く
struct AccountView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @ObservedObject var favoritesViewModel: FavoritesViewModel
    @ObservedObject var knownPlacesViewModel: KnownPlacesViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                if let user = authViewModel.currentUser {
                    Section("アカウント") {
                        HStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(displayName(user))
                                    .font(.headline)
                                if let email = user.email {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section {
                        HStack {
                            Label("お気に入り", systemImage: "heart.fill")
                                .foregroundColor(.pink)
                            Spacer()
                            Text("\(favoritesViewModel.favorites.count)件")
                                .foregroundColor(.gray)
                        }
                    }
                } else {
                    Section {
                        LoginView(authViewModel: authViewModel)
                            .frame(minHeight: 320)
                    }
                }

                Section {
                    NavigationLink(destination: KnownPlacesListView(knownPlacesViewModel: knownPlacesViewModel)) {
                        HStack {
                            Label("既知の店", systemImage: "eye")
                            Spacer()
                            Text("\(knownPlacesViewModel.knownPlaces.count)件")
                                .foregroundColor(.gray)
                        }
                    }
                } footer: {
                    Text("「行った」「知ってた」「興味なし」と記録した店は検索結果から外れます。会員登録なしで端末内に保存されます。")
                }

                if authViewModel.isSignedIn {
                    Section {
                        Button("サインアウト", role: .destructive) {
                            authViewModel.signOut()
                        }
                    }
                }
            }
            .navigationTitle("アカウント")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func displayName(_ user: AppUser) -> String {
        if let name = user.name, !name.isEmpty {
            return name
        }
        return "会員"
    }
}

/// 既知の店の一覧（スワイプで記録を取り消せる）
struct KnownPlacesListView: View {
    @ObservedObject var knownPlacesViewModel: KnownPlacesViewModel

    var body: some View {
        List {
            if knownPlacesViewModel.knownPlaces.isEmpty {
                Text("記録はまだありません。店の詳細画面で「行った」「知ってた」「興味なし」を押すと追加されます。")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                ForEach(knownPlacesViewModel.knownPlaces) { known in
                    HStack(spacing: 12) {
                        Image(systemName: known.status.systemImage)
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(known.name)
                                .font(.headline)
                            HStack(spacing: 8) {
                                Text(known.status.label)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Text(known.address)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    knownPlacesViewModel.remove(at: offsets)
                }
            }
        }
        .navigationTitle("既知の店")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    AccountView(
        authViewModel: AuthViewModel(),
        favoritesViewModel: FavoritesViewModel(),
        knownPlacesViewModel: KnownPlacesViewModel()
    )
}
