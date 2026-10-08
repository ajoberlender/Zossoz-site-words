import SwiftUI

/// First exposure: see it, hear it, try it. Not graded.
struct IntroActivity: View {
    let item: Item
    let child: Child
    var onContinue: () -> Void
    @State private var sounding = false

    var body: some View {
        VStack(spacing: 24) {
            Text("New!").font(.title2.bold()).foregroundStyle(Theme.grape)
            Spacer()
            if let e = item.emoji { Text(e).font(.system(size: 80)).accessibilityHidden(true) }
            Text(item.isSound ? "\(item.text.uppercased())\(item.text)" : item.text)
                .bigFont(item.text.count > 5 ? 72 : 110)
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.4)
            if let hint = item.hint {
                Text(hint).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            }
            Spacer()
            HStack(spacing: 20) {
                SpeakerButton(size: 84) { Task { await hear() } }
                if item.kind == .phonicsWord {
                    Button {
                        Task { sounding = true; await SpeechService.shared.speakSoundedOut(item.text, child: child); sounding = false }
                    } label: {
                        Label("Sound it out", systemImage: "tortoise.fill").font(.title3.bold())
                            .padding(.horizontal, 20).frame(height: 84)
                            .background(Theme.sun, in: Capsule()).foregroundStyle(Theme.onSun)
                    }
                }
            }
            BigButton(title: "Got it!", systemImage: "arrow.right", color: Theme.mint) {
                SpeechService.shared.stop(); onContinue()
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
        .task { try? await Task.sleep(nanoseconds: 400_000_000); await hear() }
    }

    private func hear() async {
        if item.isSound { await SpeechService.shared.speakSound(item, child: child) }
        else { await SpeechService.shared.speak(item.say, child: child) }
    }
}
