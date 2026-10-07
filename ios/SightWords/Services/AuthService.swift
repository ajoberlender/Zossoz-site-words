import Foundation

struct AuthUser: Codable, Equatable {
    var id: String
    var email: String
    var name: String?
}

@MainActor
final class AuthService: ObservableObject {
    enum State: Equatable { case signedOut, signedIn(AuthUser) }

    @Published private(set) var state: State = .signedOut
    private let userKey = "ncb.session.user"
    private let client = NCBClient.shared

    init() {
        if client.token != nil, let json = Keychain.get(userKey),
           let user = try? JSONDecoder().decode(AuthUser.self, from: Data(json.utf8)) {
            state = .signedIn(user) // optimistic: stay usable offline; a 401 on sync signs us out
        }
        client.onUnauthorized = { [weak self] in Task { @MainActor in self?.localSignOut() } }
    }

    func signIn(email: String, password: String) async throws {
        let json = try await client.request(NCBConfig.authBase, "sign-in/email", method: "POST",
                                            body: ["email": email, "password": password], authenticated: false)
        try finish(json)
    }

    func signUp(name: String, email: String, password: String) async throws {
        let json = try await client.request(NCBConfig.authBase, "sign-up/email", method: "POST",
                                            body: ["email": email, "password": password, "name": name], authenticated: false)
        try finish(json)
    }

    func signOut() async {
        _ = try? await client.request(NCBConfig.authBase, "sign-out", method: "POST", body: [String: String]())
        localSignOut()
    }

    private func localSignOut() {
        client.token = nil
        Keychain.set(nil, for: userKey)
        state = .signedOut
    }

    private func finish(_ json: Any) throws {
        guard let dict = json as? [String: Any], let token = dict["token"] as? String,
              let u = dict["user"] as? [String: Any], let id = u["id"] as? String, let email = u["email"] as? String
        else { throw NCBError(status: 0, message: "Unexpected response from server") }
        client.token = token
        let user = AuthUser(id: id, email: email, name: u["name"] as? String)
        if let data = try? JSONEncoder().encode(user) { Keychain.set(String(data: data, encoding: .utf8), for: userKey) }
        state = .signedIn(user)
    }
}
