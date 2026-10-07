import SwiftUI

/// Hear a word, then build it from letter tiles — the bridge from sounds to reading/spelling.
struct BuildActivity: View {
    let item: Item
    let child: Child
    let done: ActivityDone

    private struct Tile: Identifiable, Hashable { let id = UUID(); let letter: String }
    @State private var bank: [Tile] = []
    @State private var placed: [Tile] = []
    @State private var mistakes = 0
    @State private var heard = false
    @State private var started = Date()

    private var letters: [String] { item.text.lowercased().map(String.init) }

    var body: some View {
        VStack(spacing: 28) {
            Text("Build the word you hear").font(.title2.bold()).foregroundStyle(Theme.ink)
            HStack(spacing: 20) {
                SpeakerButton(size: 96) { heard = true; Task { await SpeechService.shared.speak(item.say, child: child) } }
                Button {
                    heard = true
                    Task { await SpeechService.shared.speakSoundedOut(item.text, child: child) }
                } label: {
                    Image(systemName: "tortoise.fill").font(.title).frame(width: 96, height: 96)
                        .background(Theme.sun, in: Circle()).foregroundStyle(Theme.ink)
                }
                .accessibilityLabel("Sound it out")
            }
            HStack(spacing: 10) {
                ForEach(0..<letters.count, id: \.self) { i in
                    Text(i < placed.count ? placed[i].letter : "")
                        .font(Theme.big(52)).foregroundStyle(Theme.ink)
                        .frame(width: 64, height: 80)
                        .background(i < placed.count ? Theme.mint.opacity(0.35) : Color.white,
                                    in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.grape.opacity(0.4), style: StrokeStyle(lineWidth: 3, dash: [6])))
                }
            }
            Spacer()
            FlowLayout(spacing: 12) {
                ForEach(bank) { t in
                    Button { tap(t) } label: {
                        Text(t.letter).font(Theme.big(48)).foregroundStyle(Theme.ink)
                            .frame(width: 76, height: 76)
                            .background(.white, in: RoundedRectangle(cornerRadius: 20))
                            .shadow(color: .black.opacity(0.12), radius: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 420)
            .padding(.bottom, 24)
        }
        .padding(.horizontal)
        .onAppear {
            started = Date()
            bank = letters.map { Tile(letter: $0) }.shuffled()
        }
        .task { try? await Task.sleep(nanoseconds: 350_000_000); await SpeechService.shared.speak(item.say, child: child) }
    }

    private func tap(_ t: Tile) {
        guard placed.count < letters.count else { return }
        if t.letter == letters[placed.count] {
            placed.append(t)
            bank.removeAll { $0.id == t.id }
            if placed.count == letters.count {
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                let grade: Grade = mistakes == 0 ? (heard ? .good : .easy) : (mistakes <= 2 ? .hinted : .missed)
                Task {
                    await SpeechService.shared.speak(item.say, child: child)
                    done(grade, heard, ms, nil)
                }
            }
        } else {
            mistakes += 1
        }
    }
}
