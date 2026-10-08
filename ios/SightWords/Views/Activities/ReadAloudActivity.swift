import SwiftUI

/// The child reads the item aloud. The phone listens on-device when it can; otherwise a grown-up
/// (or the child) taps ✓ / ✗. The speaker button is always there for help — using it caps the grade.
struct ReadAloudActivity: View {
    let item: Item
    let child: Child
    let done: ActivityDone

    @ObservedObject private var listener = ListeningService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var helped = false
    @State private var started = Date()
    @State private var heardText: String?
    @State private var micDenied = false

    private var micUsable: Bool { !item.isSound && listener.isAvailable && !micDenied }

    var body: some View {
        VStack(spacing: 24) {
            Text(item.isSound ? "Say the sound" : "Read it out loud").font(.title2.bold()).foregroundStyle(Theme.ink)
            Spacer()
            if let e = item.emoji, helped { Text(e).font(.system(size: 60)).accessibilityHidden(true) }
            Text(item.text).bigFont(item.text.count > 5 ? 72 : 120).foregroundStyle(Theme.ink).minimumScaleFactor(0.4)

            if let heardText, !heardText.isEmpty {
                Text("I heard “\(heardText)”").font(.title3).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 24) {
                SpeakerButton(size: 80) {
                    helped = true
                    Task {
                        if item.isSound { await SpeechService.shared.speakSound(item, child: child) }
                        else { await SpeechService.shared.speak(item.say, child: child) }
                    }
                }
                if micUsable {
                    Button { Task { await listen() } } label: {
                        Image(systemName: listener.isListening ? "waveform" : "mic.fill")
                            .font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 80, height: 80)
                            .background(listener.isListening ? Theme.coral : Theme.mint, in: Circle())
                            .symbolEffect(.pulse, isActive: listener.isListening && !reduceMotion)
                    }
                    .accessibilityLabel(listener.isListening ? "Listening" : "Read to me")
                }
            }
            HStack(spacing: 14) {
                BigButton(title: "Not yet", systemImage: "arrow.counterclockwise", color: Theme.coral) { finish(.missed) }
                BigButton(title: "I got it!", systemImage: "checkmark", color: Theme.mint) {
                    finish(helped ? .hinted : (Date().timeIntervalSince(started) < 3 ? .easy : .good))
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
        .onAppear { started = Date() }
    }

    private func finish(_ grade: Grade) {
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        done(grade, helped, ms, heardText)
    }

    private func listen() async {
        if !(await listener.requestPermissions()) { micDenied = true; return }
        let said = await listener.listen(expecting: [item.text])
        heardText = said
        if ListeningService.matchFraction(expected: item.text, heard: said) >= 0.99 {
            finish(helped ? .hinted : (Date().timeIntervalSince(started) < 4 ? .easy : .good))
        }
        // Otherwise leave the "I heard…" note so the child can try the mic again or tap ✗/✓.
    }
}
