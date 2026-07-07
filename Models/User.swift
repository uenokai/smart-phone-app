import Foundation

/// 会員（サインイン済みユーザー）を表すデータモデル
struct AppUser: Codable, Equatable {
    let id: String // Sign in with Apple のユーザー識別子
    var name: String?
    var email: String?
}
