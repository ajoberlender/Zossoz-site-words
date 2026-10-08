import SwiftUI

/// Drives a listen-along read: the mic stays open, the tracker follows the child through the text.
@MainActor
final class ReadAlongModel: ObservableObject {
    @Published private(set) var tracker: ReadAlongTracker
    @Published private(set) var stuck = false
    @Published private(set) var listening = false
    @Published private(set) var failed = false
    @Published private(set) var busy = false // a word or the whole text is being read to the child

    let words: [String]
    let started = Date()
    private let live = LiveReadingService.shared
    private let contextual: [String]
    private var lastProgress = Date()
    private var lastSegment = -1
    private var watchdog: Task<Void, Never>?

    init(words: [String]) {
        self.words = words
        let t = ReadAlongTracker(words: words)
        tracker = t
        contextual = Array(Set(t.targets.filter { $0.count > 2 })) // biasing toward one- and two-letter words does more harm than good
    }

    func start() async {
        guard await ListeningService.shared.requestPermissions() else { failed = true; return }
        await resumeListening()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                if self.listening, !self.busy, !self.tracker.isFinished,
                   Date().timeIntervalSince(self.lastProgress) > 6 { self.stuck = true }
            }
        }
    }

    func stop() {
        watchdog?.cancel()
        watchdog = nil
        live.onUpdate = nil
        live.onFailure = nil
        live.stop()
        listening = false
    }

    /// Say one word to the child (they asked, or tapped). The current word counts as helped and the cursor moves on.
    func hear(index: Int, child: Child) async {
        guard !busy, index >= 0, index < words.count else { return }
        busy = true
        defer { busy = false }
        live.stop()
        listening = false
        if tracker.help(at: index) { lastProgress = Date(); stuck = false }
        await SpeechService.shared.speak(ReadAlongTracker.normalize(words[index]), child: child, rate: 0.35)
        await resumeListening()
    }

    /// Model the whole text before the child starts. Doesn't count against them.
    func listenFirst(text: String, child: Child) async {
        guard !busy, tracker.cursor == 0 else { return }
        busy = true
        defer { busy = false }
        live.stop()
        listening = false
        await SpeechService.shared.speak(text, child: child)
        await resumeListening()
    }

    private func resumeListening() async {
        guard !tracker.isFinished else { return }
        live.onUpdate = { [weak self] tokens, segment, final in self?.handle(tokens, segment, final) }
        live.onFailure = { [weak self] in self?.listening = false; self?.failed = true }
        if await live.start(contextualStrings: contextual) {
            listening = true
            lastProgress = Date()
        } else {
            failed = true
        }
    }

    private func handle(_ tokens: [String], _ segment: Int, _ final: Bool) {
        guard !busy else { return }
        if segment != lastSegment { tracker.newSegment(); lastSegment = segment }
        if tracker.ingest(tokens: tokens, final: final) {
            lastProgress = Date()
            stuck = false
            if tracker.isFinished { stop() }
        }
    }
}

/// Picks listen-along when on-device recognition is available (and the grown-up hasn't turned it off),
/// otherwise the original tap-for-help reading.
struct ReadingActivity: View {
    var title: String?
    let text: String
    let child: Child
    var onFinish: (ReadOutcome) -> Void

    @AppStorage("preferTapMode") private var preferTap = false
    @State private var fellBack = false

    var body: some View {
        if preferTap || fellBack || !LiveReadingService.shared.isAvailable {
            TapAlongActivity(title: title, text: text, child: child) { helped, total, seconds in
                onFinish(ReadOutcome(helped: helped, total: total, seconds: seconds, details: nil))
            }
        } else {
            ReadAlongActivity(title: title, text: text, child: child, onFinish: onFinish, onFallback: { fellBack = true })
        }
    }
}

struct ReadAlongActivity: View {
    var title: String?
    let text: String
    let child: Child
    var onFinish: (ReadOutcome) -> Void
    var onFallback: () -> Void

    @StateObject private var model: ReadAlongModel
    @ObservedObject private var speech = SpeechService.shared
    @AppStorage("preferTapMode") private var preferTap = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var done = false
    @State private var pulse = false

    private let ranges: [NSRange]

    init(title: String?, text: String, child: Child, onFinish: @escaping (ReadOutcome) -> Void, onFallback: @escaping () -> Void) {
        self.title = title
        self.text = text
        self.child = child
        self.onFinish = onFinish
        self.onFallback = onFallback
        let ns = text as NSString
        let re = try! NSRegularExpression(pattern: "\\S+")
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        ranges = matches.map(\.range)
        _model = StateObject(wrappedValue: ReadAlongModel(words: matches.map { ns.substring(with: $0.range) }))
    }

    var body: some View {
        VStack(spacing: 16) {
            if let title { Text(title).bigFont(30).foregroundStyle(Theme.ink) }
            else { Text("Read the sentence").font(.title2.bold()).foregroundStyle(Theme.ink) }
            status

            ScrollView {
                FlowLayout(spacing: 6) {
                    ForEach(Array(model.words.enumerated()), id: \.offset) { i, w in chip(i, w) }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal)

            HStack(spacing: 14) {
                if model.tracker.cursor == 0 && !model.busy {
                    SpeakerButton(size: 72) { Task { await model.listenFirst(text: text, child: child) } }
                        .accessibilityHint("Hear the whole story first")
                }
                BigButton(title: "I'm done", systemImage: "checkmark", color: Theme.mint) { finish() }
            }
            .padding(.horizontal)

            Button("Use tap mode instead") { preferTap = true }
                .font(.footnote)
                .padding(.bottom, 8)
        }
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.tracker.isFinished) { _, finished in if finished { finish() } }
        .onChange(of: model.failed) { _, failed in if failed { model.stop(); onFallback() } }
        .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true } } }
    }

    // MARK: Pieces

    private var status: some View {
        Group {
            if model.stuck {
                Label("Stuck? Tap the glowing word and I'll say it.", systemImage: "hand.tap.fill")
                    .foregroundStyle(Theme.ink)
            } else if model.listening {
                Label("I'm listening. Read the glowing word.", systemImage: "mic.fill")
                    .foregroundStyle(.secondary)
            } else if model.busy {
                Label("Listen…", systemImage: "speaker.wave.2.fill").foregroundStyle(.secondary)
            } else {
                Label("Getting ready…", systemImage: "mic.slash").foregroundStyle(.secondary)
            }
        }
        .font(.callout.weight(.semibold))
        .multilineTextAlignment(.center)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }

    private func chip(_ i: Int, _ w: String) -> some View {
        let t = model.tracker
        let isCurrent = i == t.cursor && !t.isFinished
        let r = t.results[i]
        let demo = speech.currentRange.map { NSIntersectionRange($0, ranges[i]).length > 0 } ?? false
        let highlighted = isCurrent || demo
        let background: Color = {
            if demo { return Theme.sun }
            if isCurrent { return Theme.sun }
            guard r.read else { return .clear }
            if r.helped { return Theme.grape.opacity(0.25) }
            if r.tries >= 2 { return Theme.sun.opacity(0.3) }
            return Theme.mint.opacity(0.3)
        }()
        let stuckRing = isCurrent && model.stuck
        return Text(w)
            .bigFont(36, weight: .bold)
            .foregroundStyle(highlighted ? Theme.onSun : Theme.ink)
            .underline(r.read && r.helped, pattern: .dot)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(stuckRing ? Theme.coral : (isCurrent ? Theme.grape : .clear), lineWidth: 3)
                    .opacity(stuckRing && pulse ? 0.35 : 1)
            )
            .accessibilityElement()
            .accessibilityLabel(w)
            .accessibilityValue(isCurrent ? "current word" : (r.read ? (r.helped ? "needed help" : "read") : ""))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Hears this word")
            .onTapGesture { Task { await model.hear(index: i, child: child) } }
    }

    private func finish() {
        guard !done else { return }
        done = true
        model.stop()
        SpeechService.shared.stop()
        onFinish(model.tracker.outcome(seconds: Int(Date().timeIntervalSince(model.started))))
    }
}
