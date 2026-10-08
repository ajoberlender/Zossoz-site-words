import SwiftUI

struct StoriesView: View {
    let childID: UUID
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var ai: AIService
    @Environment(\.dismiss) private var dismiss
    @State private var reading: ReadingTarget?
    @State private var theme = AIService.themes[0]
    @State private var making = false

    struct ReadingTarget: Identifiable {
        let id = UUID()
        let key: String      // passage key or "story:<uuid>"
        let title: String
        let text: String
        let isBuiltIn: Bool
    }

    private var child: Child? { store.child(childID) }

    var body: some View {
        NavigationStack {
            List {
                Section("Story library") {
                    ForEach(Curriculum.passages) { p in
                        Button { reading = ReadingTarget(key: p.key, title: p.title ?? "", text: p.text, isBuiltIn: true) } label: {
                            HStack {
                                Text("📖").font(.title)
                                VStack(alignment: .leading) {
                                    Text(p.title ?? "").font(.headline)
                                    if let r = store.progress(for: childID)[p.key] {
                                        Text(r.mastered ? "Mastered ⭐" : "Read \(r.repetitions)×").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Picker("Story about…", selection: $theme) {
                        ForEach(AIService.themes, id: \.self) { Text($0) }
                    }
                    Button {
                        Task { await makeStory() }
                    } label: {
                        HStack {
                            Label(making ? "Writing…" : "Make me a new story", systemImage: "wand.and.stars")
                            if making { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(making)
                } header: {
                    Text("Story maker")
                } footer: {
                    Text(footer)
                }

                let saved = store.stories(for: childID)
                if !saved.isEmpty {
                    Section("My stories") {
                        ForEach(saved) { s in
                            Button { reading = ReadingTarget(key: "story:\(s.id)", title: s.title, text: s.body, isBuiltIn: false) } label: {
                                Label(s.title, systemImage: "sparkles")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stories")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } } }
            .fullScreenCover(item: $reading) { target in
                StoryReader(childID: childID, target: target)
            }
            .onAppear { ai.refresh() }
        }
    }

    private var footer: String {
        switch ai.availability {
        case .available: "Written on this device by Apple Intelligence, using words they know. Nothing is sent to the internet."
        case .appleIntelligenceOff: "Turn on Apple Intelligence in Settings to get brand-new stories. For now we’ll pick the best match from the library."
        case .modelDownloading: "Apple Intelligence is still getting ready. For now we’ll pick the best match from the library."
        case .unsupported: "New AI-written stories need a device with Apple Intelligence. We’ll pick the best match from the library."
        }
    }

    private func makeStory() async {
        guard let child else { return }
        making = true
        defer { making = false }
        var lastRead: [String: Date] = [:]
        for a in store.readingAttempts(for: childID) where lastRead[a.passageKey] == nil { lastRead[a.passageKey] = a.date } // newest first
        let draft = await ai.makeStory(childName: child.name, known: store.knownWords(childID: childID), theme: theme,
                                       recentlyRead: lastRead)
        if draft.usedAI {
            let s = GeneratedStory(childID: childID, title: draft.title, body: draft.body)
            store.saveStory(s)
            reading = ReadingTarget(key: "story:\(s.id)", title: s.title, text: s.body, isBuiltIn: false)
        } else {
            reading = ReadingTarget(key: "passage:\(draft.title)", title: draft.title, text: draft.body, isBuiltIn: true)
        }
    }
}

private struct StoryReader: View {
    let childID: UUID
    let target: StoriesView.ReadingTarget
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var summary: (helped: Int, total: Int)?

    var body: some View {
        Group {
            if let child = store.child(childID) {
                if let summary {
                    VStack(spacing: 20) {
                        Spacer()
                        Text(summary.helped == 0 ? "🏆" : "🌟").font(.system(size: 100))
                        Text(summary.helped == 0 ? "You read it all by yourself!" : "You read \(summary.total - summary.helped) of \(summary.total) words on your own!")
                            .bigFont(30).multilineTextAlignment(.center)
                        Spacer()
                        BigButton(title: "Done", color: Theme.mint) { dismiss() }.padding(.horizontal, 32)
                        WrongReaderButton(childID: childID, onMoved: { dismiss() })
                    }
                    .padding()
                } else {
                    VStack {
                        HStack {
                            Button { SpeechService.shared.stop(); dismiss() } label: {
                                Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44).accessibilityLabel("Close")
                            }
                            Spacer()
                        }
                        .padding(.horizontal).padding(.top, 8)
                        ReadingActivity(title: target.title, text: target.text, child: child) { outcome in
                            finish(child: child, outcome: outcome)
                        }
                    }
                }
            }
        }
        .screenBackground()
    }

    private func finish(child: Child, outcome: ReadOutcome) {
        let missed = outcome.helped
        let total = outcome.total
        let seconds = outcome.seconds
        store.recordAttempt(PassageAttempt(childID: childID, passageKey: target.key, wordsTotal: total,
                                           wordsCorrect: max(0, total - missed.count), durationSec: seconds,
                                           missedWords: missed, words: outcome.details))
        // Built-in passages are scheduled by spaced repetition like everything else.
        if target.isBuiltIn, let item = Curriculum.byKey[target.key] {
            let frac = total == 0 ? 0 : Double(missed.count) / Double(total)
            store.record(childID: childID, item: item, grade: frac == 0 ? .good : (frac <= 0.25 ? .hinted : .missed),
                         activity: "story", responseMs: seconds * 1000, heardAudio: !missed.isEmpty, aiFeedback: nil)
        }
        if let details = outcome.details {
            // Listened along: every word they read (cleanly or not) updates the words they're learning.
            store.recordWordOutcomes(childID: childID, details: details)
        } else {
            // Words they needed help with get scheduled sooner — but only ones already being tracked.
            let progress = store.progress(for: childID)
            for w in missed {
                for key in ["sight_word:\(w)", "phonics_word:\(w)"] where progress[key] != nil {
                    if let item = Curriculum.byKey[key] {
                        store.record(childID: childID, item: item, grade: .hinted, activity: "story_help", responseMs: 0, heardAudio: true)
                    }
                }
            }
        }
        summary = (missed.count, total)
        Task { await store.sync() }
    }
}
