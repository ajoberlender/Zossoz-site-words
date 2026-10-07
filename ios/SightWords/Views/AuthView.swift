import SwiftUI

struct AuthView: View {
    @EnvironmentObject var auth: AuthService
    @State private var signUp = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("📚").font(.system(size: 80))
                Text("Sight Words").font(Theme.big(40))
                Text("A grown-up signs in once. Your readers keep their progress across devices.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    if signUp { TextField("Your name", text: $name).textContentType(.name) }
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password).textContentType(signUp ? .newPassword : .password)
                }
                .textFieldStyle(.roundedBorder)
                .font(.title3)

                if let error { Text(error).foregroundStyle(.red).font(.callout).multilineTextAlignment(.center) }

                BigButton(title: busy ? "One moment…" : (signUp ? "Create account" : "Sign in"), color: Theme.grape) {
                    Task { await submit() }
                }
                .disabled(busy || email.isEmpty || password.count < 8 || (signUp && name.isEmpty))
                .opacity(busy ? 0.6 : 1)

                Button(signUp ? "I already have an account" : "Create an account") { signUp.toggle(); error = nil }
                    .font(.callout.bold())
            }
            .padding(28)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
    }

    private func submit() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            if signUp { try await auth.signUp(name: name, email: email.trimmingCharacters(in: .whitespaces), password: password) }
            else { try await auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password) }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
