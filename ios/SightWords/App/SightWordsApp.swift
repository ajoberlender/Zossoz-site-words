import SwiftUI

@main
struct SightWordsApp: App {
    @StateObject private var auth = AuthService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(AIService.shared)
                .environmentObject(SpeechService.shared)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        switch auth.state {
        case .signedOut:
            AuthView()
        case .signedIn(let user):
            SignedInRoot(user: user).id(user.id) // fresh store per account
        }
    }
}

private struct SignedInRoot: View {
    let user: AuthUser
    @StateObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    init(user: AuthUser) {
        self.user = user
        _store = StateObject(wrappedValue: AppStore(userID: user.id))
    }

    var body: some View {
        ChildPickerView()
            .environmentObject(store)
            .task { await store.sync() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.sync() } }
            }
    }
}
