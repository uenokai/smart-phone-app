import SwiftUI
import AuthenticationServices

/// 会員登録・サインイン画面
/// 検索機能は未登録でも使えるが、お気に入り登録には会員登録（無料）が必要
struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "heart.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.pink)

            VStack(spacing: 8) {
                Text("会員登録してお気に入りを保存")
                    .font(.title3)
                    .fontWeight(.bold)
                Text("気になったお店やスポットをお気に入りに登録するには、会員登録（無料）が必要です。検索機能は登録なしでもご利用いただけます。")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                authViewModel.handleSignInResult(result)
                if authViewModel.isSignedIn {
                    dismiss()
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .padding(.horizontal, 24)

            Button("登録せずに続ける") {
                dismiss()
            }
            .font(.caption)
            .foregroundColor(.gray)

            if let error = authViewModel.error {
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

            Spacer()
        }
    }
}

#Preview {
    LoginView(authViewModel: AuthViewModel())
}
