import SwiftUI

/// A grown-up sits with the child, who reads each card aloud. Tap "Got it" for a card read without help.
/// The test climbs while they succeed and drops back when they struggle, then reports a reading level.
struct PlacementTestView: View {
    let childID: UUID
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case intro, asking, done }
    @State private var phase = Phase.intro
    @State private var engine = PlacementEngine()
    @State private var result: Placement?
    @State private var moveStage = true

    private var child: Child? { store.child(childID) }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .intro: intro
                case .asking: asking
                case .done: done
                }
            }
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .done ? "Close" : "Cancel") { dismiss() }
                }
                if phase == .asking {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Finish now") { engine.stopEarly(); finishTest() }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(phase == .asking)
    }

    // MARK: Phases

    private var intro: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("🎯").font(.system(size: 80)).accessibilityHidden(true)
            Text("Reading level check").bigFont(34).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                Label("Sit with \(child?.name ?? "your reader"). Take about five minutes.", systemImage: "person.2.fill")
                Label("Cards get harder while they succeed and easier when they struggle.", systemImage: "arrow.up.arrow.down")
                Label("Tap Got it only for cards they read on their own, with no hints.", systemImage: "checkmark.circle")
                Label("The result decides which words stories use and where practice starts.", systemImage: "book.fill")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 28)
            Spacer()
            BigButton(title: "Start", systemImage: "play.fill", color: Theme.grape) { phase = .asking }
                .padding(.horizontal, 32).padding(.bottom, 12)
        }
    }

    private var asking: some View {
        Group {
            if let item = engine.current {
                PlacementCard(item: item) { ok in
                    engine.answer(correct: ok)
                    if engine.finished { finishTest() }
                }
                .id("\(engine.asked)-\(item.key)")
            } else {
                ProgressView()
            }
        }
    }

    private var done: some View {
        let placement = result ?? Placement(level: 0)
        let level = placement.level
        let current = child?.currentStage ?? 1
        let suggested = Placement.stage(afterPassing: level)
        let stageTitle = Curriculum.stages[min(suggested, Curriculum.stages.count) - 1].title
        return ScrollView {
            VStack(spacing: 18) {
                Text(level == 0 ? "🌱" : Curriculum.levels[level - 1].emoji).font(.system(size: 80)).accessibilityHidden(true)
                Text(level == 0 ? "Just getting started" : Curriculum.levels[level - 1].title)
                    .bigFont(34).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                Text(level == 0
                     ? "\(child?.name ?? "They") will begin with the letter sounds."
                     : "\(child?.name ?? "They") can read \(Curriculum.levels[level - 1].title.lowercased()) and everything before it.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("\(placement.correct.count) of \(engine.asked) cards read correctly.")
                    .font(.footnote).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Stories will use all the words at this level.", systemImage: "book.fill")
                    Label("Words they already know won't be taught again.", systemImage: "checkmark.seal.fill")
                    if suggested != current {
                        Toggle("Move practice to Stage \(suggested): \(stageTitle)", isOn: $moveStage)
                            .tint(Theme.grape)
                    } else {
                        Label("Practice is already at the right stage.", systemImage: "arrow.right.circle")
                    }
                }
                .font(.callout)
                .padding()
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                BigButton(title: "Save result", systemImage: "checkmark", color: Theme.mint) {
                    store.applyPlacement(childID: childID, placement: placement, moveStage: suggested != current && moveStage)
                    dismiss()
                }
                Button("Don't save") { dismiss() }.font(.callout)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .onAppear { moveStage = suggested > current }
    }

    private func finishTest() {
        result = engine.result
        phase = .done
    }
}

/// One card of the test. No speaker button: hearing the word would be a hint.
private struct PlacementCard: View {
    let item: Item
    var onAnswer: (Bool) -> Void

    @ObservedObject private var listener = ListeningService.shared
    @State private var heard: String?
    @State private var micDenied = false

    private var micUsable: Bool { !item.isSound && listener.isAvailable && !micDenied }

    var body: some View {
        VStack(spacing: 24) {
            Text(item.isSound ? "Say the sound" : "Read it out loud").font(.title2.bold()).foregroundStyle(Theme.ink)
            Spacer()
            Text(item.text)
                .bigFont(item.text.count > 5 ? 72 : 120)
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.4)
            if let heard, !heard.isEmpty {
                Text("I heard “\(heard)”").font(.title3).foregroundStyle(.secondary)
            }
            Spacer()
            if micUsable {
                Button { Task { await listen() } } label: {
                    Image(systemName: listener.isListening ? "waveform" : "mic.fill")
                        .font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 80, height: 80)
                        .background(listener.isListening ? Theme.coral : Theme.mint, in: Circle())
                }
                .accessibilityLabel(listener.isListening ? "Listening" : "Listen to them read")
            }
            HStack(spacing: 14) {
                BigButton(title: "Not yet", systemImage: "arrow.counterclockwise", color: Theme.coral) { onAnswer(false) }
                BigButton(title: "Got it", systemImage: "checkmark", color: Theme.mint) { onAnswer(true) }
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
    }

    private func listen() async {
        if !(await listener.requestPermissions()) { micDenied = true; return }
        let said = await listener.listen(expecting: [item.text])
        heard = said
        if ListeningService.matchFraction(expected: item.text, heard: said) >= 0.99 { onAnswer(true) }
        // Otherwise leave "I heard…" up so the grown-up can decide.
    }
}
