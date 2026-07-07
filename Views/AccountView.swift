import SwiftUI

/// アカウント画面
/// サインイン済みならプロフィールとサインアウト、未サインインなら会員登録画面を表示
struct AccountView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @ObservedObject var favoritesViewModel: FavoritesViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Group {
                if let user = authViewModel.currentUser {
                    List {
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

                        Section {
                            Button("サインアウト", role: .destructive) {
                                authViewModel.signOut()
                            }
                        }
                    }
                } else {
                    LoginView(authViewModel: authViewModel)
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

#Preview {
    AccountView(
        authViewModel: AuthViewModel(),
        favoritesViewModel: FavoritesViewModel()
    )
}
