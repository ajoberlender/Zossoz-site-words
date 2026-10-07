import Foundation

/// NoCodeBackend (NCB) endpoints.
///
/// There is deliberately NO secret key in this app. NCB's data API accepts the signed-in
/// parent's session token as a Bearer token and enforces row-level security by `user_id`
/// server-side, so each parent can only ever read and write their own rows.
enum NCBConfig {
    static let instance = "53722_zossoz_sight_words"
    static let authBase = URL(string: "https://app.nocodebackend.com/api/user-auth")!
    static let dataBase = URL(string: "https://app.nocodebackend.com/api/data")!
    static let origin = "https://app.nocodebackend.com"
}
