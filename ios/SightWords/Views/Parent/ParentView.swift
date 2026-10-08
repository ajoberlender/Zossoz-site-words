import SwiftUI
import AVFoundation

struct ParentView: View {
    let childID: UUID
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var ai: AIService
    @Environment(\.dismiss) private var dismiss

    @State private var newWord = ""
    @State private var newSentence = ""
    @State private var coach: CoachNotes?
    @State private var coaching = false
    @State private var confirmDelete = false
    private let voices = SpeechService.availableVoices()

    var body: some View {
        NavigationStack {
            if let child = store.child(childID) {
                Form {
                    profileSection(child)
                    UsageSection(childID: childID)
                    progressSection(child)
                    troubleSection()
                    learnerSection(child)
                    wordsSection(child)
                    aiSection(child)
                    Section {
                        Button("Delete \(child.name)…", role: .destructive) { confirmDelete = true }
                    } footer: { Text("Removes this reader and all of their progress, here and in the cloud.") }
                }
                .navigationTitle(child.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { trimName(childID); dismiss() } } }
                .confirmationDialog("Delete \(child.name) and all progress?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { store.deleteChild(childID); dismiss() }
                }
            }
        }
    }

    // MARK: Sections

    private func profileSection(_ c: Child) -> some View {
        Section("Reader") {
            TextField("Name", text: Binding(
                get: { store.child(c.id)?.name ?? c.name },
                set: { v in if var n = store.child(c.id) { n.name = v; store.updateChild(n) } }))
                .onSubmit { trimName(c.id) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Theme.avatars, id: \.self) { a in
                        let selected = a == (store.child(c.id)?.avatar ?? c.avatar)
                        Button { if var n = store.child(c.id) { n.avatar = a; store.updateChild(n) } } label: {
                            Text(a).font(.system(size: 34)).padding(6)
                                .background(selected ? Theme.sun.opacity(0.5) : .clear, in: Circle())
                                .overlay(Circle().stroke(selected ? Theme.grape : .clear, lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Buddy \(a)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func trimName(_ id: UUID) {
        guard var n = store.child(id) else { return }
        let t = n.name.trimmingCharacters(in: .whitespaces)
        n.name = t.isEmpty ? "Reader" : t
        store.updateChild(n)
    }

    private func progressSection(_ c: Child) -> some View {
        Section("Progress") {
            ForEach(Curriculum.stages) { stage in
                let s = store.masteredCount(childID: c.id, stage: stage.id)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(stage.emoji) \(stage.title)")
                        Spacer()
                        Text("\(s.mastered) mastered · \(s.seen)/\(s.total) seen").font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(s.seen), total: Double(max(s.total, 1)))
                }
            }
            LabeledContent("Streak", value: "\(c.streakDays) day\(c.streakDays == 1 ? "" : "s")")
            LabeledContent("Stars", value: "\(c.stars)")
        }
    }

    @ViewBuilder
    private func troubleSection() -> some View {
        let trouble = store.trouble(childID: childID)
        if !trouble.isEmpty {
            Section("Needs a little more practice") {
                ForEach(Array(trouble.enumerated()), id: \.offset) { _, pair in
                    let (item, rec) = pair
                    HStack {
                        Text(item.kind == .passage ? (item.title ?? item.text) : item.text).font(.title3.bold())
                        Spacer()
                        Text("missed \(rec.lapses)×").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func learnerSection(_ c: Child) -> some View {
        Section("Reader settings") {
            Stepper("Stage \(c.currentStage): \(Curriculum.stages[c.currentStage - 1].title)", value: binding(c, \.currentStage), in: 1...Curriculum.stages.count)
            Stepper("Daily goal: \(c.dailyGoal) cards", value: binding(c, \.dailyGoal), in: 5...30, step: 5)
            Picker("Voice", selection: Binding(
                get: { c.voiceID ?? "" },
                set: { v in var n = c; n.voiceID = v.isEmpty ? nil : v; store.updateChild(n) })) {
                Text("Automatic").tag("")
                ForEach(voices, id: \.identifier) { v in Text("\(v.name)\(v.quality == .premium ? " ★★" : (v.quality == .enhanced ? " ★" : ""))").tag(v.identifier) }
            }
            VStack(alignment: .leading) {
                Text("Speaking speed")
                Slider(value: binding(c, \.speechRate), in: 0.25...0.55)
            }
            Button("Test voice") { Task { await SpeechService.shared.speak("Hi \(c.name)! Let's read together.", child: store.child(childID)) } }
            Text("Tip: download an Enhanced or Premium voice in Settings → Accessibility → Spoken Content → Voices for friendlier speech.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func wordsSection(_ c: Child) -> some View {
        Section {
            ForEach(store.customWords(for: c.id)) { w in
                VStack(alignment: .leading) {
                    Text(w.word).font(.headline)
                    if let s = w.sentence, !s.isEmpty { Text(s).font(.caption).foregroundStyle(.secondary) }
                }
                .swipeActions { Button("Delete", role: .destructive) { store.deleteCustomWord(w.id) } }
            }
            TextField("Add a word (e.g. their name)", text: $newWord).textInputAutocapitalization(.never)
            TextField("Example sentence (optional)", text: $newSentence)
            Button("Add word") {
                store.addCustomWord(childID: c.id, word: newWord, sentence: newSentence.isEmpty ? nil : newSentence, note: nil)
                newWord = ""; newSentence = ""
            }
            .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: { Text("Custom words") } footer: { Text("These join the practice queue alongside the built-in curriculum.") }
    }

    private func aiSection(_ c: Child) -> some View {
        Section {
            switch ai.availability {
            case .available: Label("Apple Intelligence is ready (on-device)", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.mint)
            case .appleIntelligenceOff: Label("Turn on Apple Intelligence in Settings for AI coaching & stories", systemImage: "exclamationmark.triangle")
            case .modelDownloading: Label("Apple Intelligence is getting ready…", systemImage: "arrow.down.circle")
            case .unsupported: Label("This device doesn’t support Apple Intelligence — using built-in tips", systemImage: "info.circle")
            }
            Button {
                Task { await loadCoach(c) }
            } label: {
                HStack { Text(coaching ? "Thinking…" : "Coach me"); if coaching { Spacer(); ProgressView() } }
            }
            .disabled(coaching)
            if let coach {
                Text(coach.summary).font(.body)
                ForEach(coach.tips, id: \.self) { Label($0, systemImage: "lightbulb") }
                if coach.usedAI { Text("Written on-device by Apple Intelligence").font(.caption).foregroundStyle(.secondary) }
            }
        } header: { Text("AI coach") }
        .onAppear { ai.refresh() }
    }

    // MARK: Helpers

    private func binding<T>(_ c: Child, _ kp: WritableKeyPath<Child, T>) -> Binding<T> {
        Binding(get: { store.child(c.id)?[keyPath: kp] ?? c[keyPath: kp] },
                set: { v in if var n = store.child(c.id) { n[keyPath: kp] = v; store.updateChild(n) } })
    }

    private func loadCoach(_ c: Child) async {
        coaching = true
        defer { coaching = false }
        let mastered = Curriculum.stages.reduce(0) { $0 + store.masteredCount(childID: c.id, stage: $1.id).mastered }
        let trouble = store.trouble(childID: c.id, limit: 5).map { (word: $0.0.text, misses: $0.1.lapses) }
        coach = await ai.coachNotes(childName: c.name, stageTitle: Curriculum.stages[c.currentStage - 1].title,
                                    masteredCount: mastered, streak: c.streakDays, trouble: trouble)
    }
}
