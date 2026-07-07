import Foundation
import AuthenticationServices

/// 会員認証（Sign in with Apple）を管理するViewModel
/// アプリは未サインインでも利用可能。お気に入り機能のみサインインが必要。
@MainActor
class AuthViewModel: ObservableObject {
    @Published var currentUser: AppUser? = nil
    @Published var error: String? = nil

    var isSignedIn: Bool { currentUser != nil }

    private let userDefaults = UserDefaults.standard
    private let userKey = "current_user"

    init() {
        loadUser()
        verifyCredentialState()
    }

    /// Sign in with Apple の認証結果を処理
    func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                error = "認証情報を取得できませんでした"
                return
            }
            // 名前・メールは初回サインイン時のみ返されるため、再サインイン時は既存の値を保持する
            let name = [credential.fullName?.familyName, credential.fullName?.givenName]
                .compactMap { $0 }
                .joined(separator: " ")
            currentUser = AppUser(
                id: credential.user,
                name: name.isEmpty ? currentUser?.name : name,
                email: credential.email ?? currentUser?.email
            )
            error = nil
            persistUser()
        case .failure(let error):
            // ユーザーによるキャンセルはエラー表示しない
            if (error as? ASAuthorizationError)?.code != .canceled {
                self.error = "サインインに失敗しました：\(error.localizedDescription)"
            }
        }
    }

    /// サインアウト（ローカルの会員情報を削除）
    func signOut() {
        currentUser = nil
        userDefaults.removeObject(forKey: userKey)
    }

    // MARK: - Private Methods

    private func loadUser() {
        if let data = userDefaults.data(forKey: userKey),
           let decoded = try? JSONDecoder().decode(AppUser.self, from: data) {
            currentUser = decoded
        }
    }

    private func persistUser() {
        if let encoded = try? JSONEncoder().encode(currentUser) {
            userDefaults.set(encoded, forKey: userKey)
        }
    }

    /// Apple ID の認証状態を確認し、失効していれば自動サインアウト
    private func verifyCredentialState() {
        guard let userId = currentUser?.id else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userId) { [weak self] state, _ in
            Task { @MainActor in
                if state == .revoked {
                    self?.signOut()
                }
            }
        }
    }
}
