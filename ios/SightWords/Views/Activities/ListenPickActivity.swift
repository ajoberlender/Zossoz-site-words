import SwiftUI

/// "Listen and tap what you hear" — no reading comprehension needed, so it works from day one.
struct ListenPickActivity: View {
    let item: Item
    let child: Child
    let pool: [Item]
    let done: ActivityDone

    @State private var choices: [Item] = []
    @State private var wrong: Set<String> = []
    @State private var replays = 0
    @State private var started = Date()
    @State private var finished = false
    @State private var feedback: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 28) {
            Text(item.isSound ? "Which letter makes this sound?" : "Tap the word you hear").font(.title2.bold()).foregroundStyle(Theme.ink)
            SpeakerButton(size: 110) { replays += 1; Task { await play() } }
            Spacer(minLength: 0)
            VStack(spacing: 16) {
                ForEach(choices) { c in
                    Button { tap(c) } label: {
                        Text(c.text)
                            .bigFont(c.text.count > 4 ? 48 : 64).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 100)
                            .background(background(for: c), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .shadow(color: .black.opacity(0.1), radius: 0, y: 5)
                    }
                    .buttonStyle(.plain)
                    .disabled(wrong.contains(c.key) || finished)
                }
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 24)
        .onAppear {
            started = Date()
            choices = ([item] + SessionPlanner.distractors(for: item, in: pool)).shuffled()
        }
        .task { try? await Task.sleep(nanoseconds: 350_000_000); await play() }
    }

    private func background(for c: Item) -> Color {
        if wrong.contains(c.key) { return Theme.coral.opacity(0.35) }
        return Theme.card
    }

    private func play() async {
        if item.isSound { await SpeechService.shared.speakSound(item, child: child) }
        else { await SpeechService.shared.speak(item.say, child: child) }
    }

    private func tap(_ c: Item) {
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        if c.key == item.key {
            finished = true
            feedback?.cancel()
            let grade: Grade = !wrong.isEmpty ? .missed : ((replays == 0 && ms < 4000) ? .easy : .good)
            done(grade, replays > 0, ms, nil)
        } else {
            wrong.insert(c.key)
            feedback?.cancel()
            feedback = Task { await SpeechService.shared.speakWrongAnswer(tapped: c, child: child) }
        }
    }
}
