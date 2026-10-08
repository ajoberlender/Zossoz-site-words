import SwiftUI

typealias ActivityDone = (_ grade: Grade, _ heardAudio: Bool, _ ms: Int, _ heardText: String?) -> Void

@MainActor
final class SessionModel: ObservableObject {
    let childID: UUID
    let store: AppStore
    @Published private(set) var queue: [Card] = []
    @Published private(set) var index = 0
    @Published private(set) var stars = 0
    @Published private(set) var feedback: Grade?
    @Published private(set) var finished = false
    private var retries: [String: Int] = [:]
    private var answered = 0

    init(childID: UUID, store: AppStore) {
        self.childID = childID
        self.store = store
        if let child = store.child(childID) { queue = SessionPlanner.plan(child: child, store: store) }
        if queue.isEmpty { finished = true }
    }

    var current: Card? { index < queue.count ? queue[index] : nil }
    var progress: Double { queue.isEmpty ? 1 : Double(index) / Double(queue.count) }
    var child: Child? { store.child(childID) }
    var pool: [Item] { store.pool(for: childID) }

    /// Intro cards teach; they aren't graded.
    func continueFromIntro() { advance() }

    func answer(_ card: Card, grade: Grade, heardAudio: Bool, ms: Int, heardText: String?) {
        store.record(childID: childID, item: card.item, grade: grade, activity: card.activity.rawValue,
                     responseMs: ms, heardAudio: heardAudio, aiFeedback: heardText)
        answered += 1
        if grade.rawValue >= Grade.good.rawValue { stars += 1 }
        if grade == .missed, (retries[card.item.key] ?? 0) < 1 {
            retries[card.item.key] = 1
            // Show it again soon, as an easy listen-and-pick so the child ends on a win.
            let retryActivity: Activity = (card.item.kind == .sentence || card.item.kind == .passage) ? .tapAlong : .listenPick
            let at = min(queue.count, index + 4)
            queue.insert(Card(item: card.item, activity: retryActivity, isRetry: true), at: at)
        }
        feedback = grade
        Task {
            try? await Task.sleep(nanoseconds: grade == .missed ? 1_100_000_000 : 750_000_000)
            feedback = nil
            advance()
        }
    }

    private func advance() {
        index += 1
        if index >= queue.count {
            finished = true
            store.finishSession(childID: childID, starsEarned: stars)
        }
    }
}

struct SessionView: View {
    let childID: UUID
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SessionBody(model: SessionModel(childID: childID, store: store), onClose: { dismiss() })
    }
}

private struct SessionBody: View {
    @StateObject var model: SessionModel
    var onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: @autoclosure @escaping () -> SessionModel, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: model())
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                HStack {
                    Button { SpeechService.shared.stop(); onClose() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Close")
                    ProgressView(value: model.progress).tint(Theme.mint).scaleEffect(y: 2.2)
                        .accessibilityLabel("Progress")
                    Text("⭐ \(model.stars)").font(.title3.bold())
                        .accessibilityLabel("\(model.stars) stars")
                }
                .padding(.horizontal)

                if model.finished {
                    SessionSummary(childID: model.childID, stars: model.stars, empty: model.queue.isEmpty, onClose: onClose)
                } else if let card = model.current, let child = model.child {
                    activity(for: card, child: child).id(card.id)
                }
            }
            .padding(.top, 8)

            if let fb = model.feedback { FeedbackBanner(grade: fb).transition(.scale.combined(with: .opacity)) }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: model.feedback != nil)
        .onChange(of: model.feedback) { _, fb in
            // The banner is only on screen for about a second; make sure VoiceOver users hear it.
            if let fb { UIAccessibility.post(notification: .announcement, argument: FeedbackBanner.message(for: fb)) }
        }
        .screenBackground()
    }

    @ViewBuilder
    private func activity(for card: Card, child: Child) -> some View {
        let done: ActivityDone = { grade, heard, ms, text in
            model.answer(card, grade: grade, heardAudio: heard, ms: ms, heardText: text)
        }
        switch card.activity {
        case .intro:
            IntroActivity(item: card.item, child: child, onContinue: { model.continueFromIntro() })
        case .listenPick:
            ListenPickActivity(item: card.item, child: child, pool: model.pool, done: done)
        case .soundOut, .build:
            BuildActivity(item: card.item, child: child, done: done)
        case .readAloud:
            ReadAloudActivity(item: card.item, child: child, done: done)
        case .tapAlong:
            ReadingActivity(title: card.item.title, text: card.item.text, child: child) { outcome in
                let helped = outcome.helped
                let frac = outcome.total == 0 ? 0 : Double(helped.count) / Double(outcome.total)
                if let details = outcome.details {
                    model.store.recordAttempt(PassageAttempt(
                        childID: model.childID, passageKey: card.item.key, wordsTotal: outcome.total,
                        wordsCorrect: max(0, outcome.total - helped.count), durationSec: outcome.seconds,
                        missedWords: helped, words: details))
                    model.store.recordWordOutcomes(childID: model.childID, details: details)
                }
                done(frac == 0 ? .good : (frac <= 0.25 ? .hinted : .missed), !helped.isEmpty, outcome.seconds * 1000, helped.joined(separator: ","))
            }
        }
    }
}

private struct FeedbackBanner: View {
    let grade: Grade
    var body: some View {
        VStack(spacing: 8) {
            Text(grade == .missed ? "🌱" : (grade == .easy ? "🌟" : "🎉")).font(.system(size: 90)).accessibilityHidden(true)
            Text(Self.message(for: grade)).bigFont(28).foregroundStyle(Theme.ink)
        }
        .padding(32)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(radius: 20)
    }

    static func message(for grade: Grade) -> String {
        grade == .missed ? "Let's try again soon!" : (grade == .hinted ? "Nice work!" : "Great reading!")
    }
}

private struct SessionSummary: View {
    let childID: UUID
    let stars: Int
    let empty: Bool
    var onClose: () -> Void
    @EnvironmentObject var store: AppStore
    @State private var showGate = false
    @State private var gatePassed = false
    @State private var showChoice = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(empty ? "🎈" : "🏆").font(.system(size: 110))
            Text(empty ? "All caught up!" : "You did it!").bigFont(40).foregroundStyle(Theme.ink)
            if !empty { Text("You earned ⭐ \(stars)").font(.title.bold()) }
            else { Text("Come back later — your words need a little rest.").multilineTextAlignment(.center).foregroundStyle(.secondary) }
            Spacer()
            BigButton(title: "Done", color: Theme.mint, action: onClose).padding(.horizontal, 32)
            if !empty, let name = store.child(childID)?.name, store.children.count > 1 {
                Button("Wasn't \(name)? Move this practice…") { showGate = true }
                    .font(.callout)
            }
        }
        .padding()
        .sheet(isPresented: $showGate, onDismiss: {
            if gatePassed { gatePassed = false; showChoice = true }
        }) { GrownUpGate { gatePassed = true } }
        .confirmationDialog("Who was actually reading?", isPresented: $showChoice, titleVisibility: .visible) {
            ForEach(store.children.filter { $0.id != childID }) { other in
                Button("\(other.avatar) \(other.name)") {
                    if let latest = store.practiceSessions(for: childID, limit: 1).first {
                        store.reassign([latest], from: childID, to: other.id)
                    }
                    onClose()
                }
            }
        } message: { Text("This session's progress and stars move to them.") }
    }
}
