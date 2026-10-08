import SwiftUI

/// A set of cards to study: one per reading level, the words they keep missing, or a parent's own list.
struct FlashcardDeck: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let emoji: String
    let items: [Item]
}

/// Free-play flashcards, separate from the daily lesson. Pick any deck, any time.
struct FlashcardsView: View {
    let childID: UUID
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var deck: FlashcardDeck?

    private var levelDecks: [FlashcardDeck] {
        var decks = Curriculum.levels.enumerated().map { i, level in
            FlashcardDeck(id: "level-\(level.id)", title: level.title, subtitle: level.blurb, emoji: level.emoji,
                          items: Curriculum.testLevels[i])
        }
        decks.append(FlashcardDeck(id: "sentences", title: "Sentences", subtitle: "Read a whole line", emoji: "💬",
                                   items: Curriculum.sentences))
        return decks
    }

    private var trickyDeck: FlashcardDeck? {
        let items = store.trouble(childID: childID, limit: 30).map(\.0)
        guard !items.isEmpty else { return nil }
        return FlashcardDeck(id: "tricky", title: "Tricky words", subtitle: "The ones that need more practice",
                             emoji: "🎯", items: items)
    }

    private var listDecks: [FlashcardDeck] {
        store.flashcardLists.filter { !$0.cards.isEmpty }.map { list in
            FlashcardDeck(id: "list-\(list.id)", title: list.name, subtitle: "Made by a grown-up", emoji: "📝",
                          items: list.cards.map(Self.item(for:)))
        }
    }

    /// A built-in item if the text is one (so progress is tracked), otherwise a plain card.
    static func item(for text: String) -> Item {
        let lower = text.lowercased()
        if let it = Curriculum.byKey["sight_word:\(text)"] ?? Curriculum.byKey["sight_word:\(lower)"]
            ?? Curriculum.byKey["phonics_word:\(lower)"] ?? Curriculum.byKey["sentence:\(text)"] { return it }
        return Item(key: "list:\(lower)", kind: text.contains(" ") ? .sentence : .sightWord, stage: 0, text: text, say: text)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Flashcards").bigFont(36).foregroundStyle(Theme.ink)
                    Text("Pick a deck. Practice any time. It doesn't change today's lesson.")
                        .font(.callout).foregroundStyle(.secondary)

                    if let tricky = trickyDeck { section("For you", [tricky]) }
                    section("Levels", levelDecks)
                    let lists = listDecks
                    if !lists.isEmpty { section("My lists", lists) }
                }
                .padding(20)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .screenBackground()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } } }
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $deck) { d in FlashcardStudyView(childID: childID, deck: d) }
        }
    }

    private func section(_ title: String, _ decks: [FlashcardDeck]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(Theme.ink).padding(.top, 8)
            ForEach(decks) { d in
                Button { deck = d } label: {
                    HStack(spacing: 14) {
                        Text(d.emoji).font(.system(size: 36)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.title).font(.headline).foregroundStyle(Theme.ink)
                            Text("\(d.subtitle) · \(d.items.count) cards").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Studying a deck

@MainActor
final class FlashcardModel: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let item: Item
        var isRetry = false
    }

    @Published private(set) var queue: [Entry] = []
    @Published private(set) var index = 0
    @Published private(set) var knew = 0
    @Published private(set) var missed: [Item] = []
    @Published private(set) var busy = false
    @Published private(set) var finished = false
    private(set) var total = 0

    private let all: [Item]
    private var unused: [Item]
    private var heardFirst = false
    private let roundSize = 12
    private weak var store: AppStore?
    private var childID: UUID?

    init(items: [Item]) {
        all = items
        unused = items.shuffled()
        startRound()
    }

    func attach(store: AppStore, childID: UUID) {
        self.store = store
        self.childID = childID
    }

    var current: Entry? { index < queue.count ? queue[index] : nil }

    /// A fresh round from the cards not seen yet (reshuffling once the deck has been all the way through),
    /// or just the cards that were missed.
    func startRound(only: [Item]? = nil) {
        let picked: [Item]
        if let only {
            picked = only.shuffled()
        } else {
            if unused.isEmpty { unused = all.shuffled() }
            picked = Array(unused.prefix(roundSize))
            unused.removeFirst(picked.count)
        }
        queue = picked.map { Entry(item: $0) }
        index = 0
        knew = 0
        missed = []
        total = picked.count
        heardFirst = false
        finished = picked.isEmpty
    }

    func hear(child: Child?) async {
        guard let item = current?.item, !busy else { return }
        heardFirst = true
        busy = true
        await speak(item, child: child)
        busy = false
    }

    func know() {
        guard !busy, let e = current else { return }
        record(e.item, heardFirst ? .hinted : .good)
        if !e.isRetry { knew += 1 }
        next()
    }

    /// Not yet: say the answer, and bring the card back a few cards later.
    func notYet(child: Child?) async {
        guard !busy, let e = current else { return }
        busy = true
        record(e.item, .missed)
        if !e.isRetry {
            missed.append(e.item)
            queue.insert(Entry(item: e.item, isRetry: true), at: min(queue.count, index + 4))
        }
        await speak(e.item, child: child)
        busy = false
        next()
    }

    private func speak(_ item: Item, child: Child?) async {
        if item.isSound { await SpeechService.shared.speakSound(item, child: child) }
        else { await SpeechService.shared.speak(item.say, child: child) }
    }

    private func next() {
        heardFirst = false
        index += 1
        if index >= queue.count { finished = true }
    }

    /// Study results feed spaced repetition for built-in items, so the daily lesson knows what was practised.
    /// Cards that only exist in a parent's list are not tracked.
    private func record(_ item: Item, _ grade: Grade) {
        guard let store, let childID, let built = Curriculum.byKey[item.key] else { return }
        store.record(childID: childID, item: built, grade: grade, activity: "flashcard", responseMs: 0, heardAudio: heardFirst)
    }
}

struct FlashcardStudyView: View {
    let childID: UUID
    let deck: FlashcardDeck
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: FlashcardModel

    init(childID: UUID, deck: FlashcardDeck) {
        self.childID = childID
        self.deck = deck
        _model = StateObject(wrappedValue: FlashcardModel(items: deck.items))
    }

    private var child: Child? { store.child(childID) }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button { SpeechService.shared.stop(); dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Close")
                Text("\(deck.emoji) \(deck.title)").font(.headline).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer()
                if !model.finished { Text("\(min(model.index + 1, model.queue.count)) / \(model.queue.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary) }
            }
            .padding(.horizontal)

            if model.finished { summary } else if let e = model.current { card(e) }
        }
        .padding(.top, 8)
        .screenBackground()
        .onAppear { model.attach(store: store, childID: childID) }
        .onDisappear { SpeechService.shared.stop() }
    }

    private func card(_ e: FlashcardModel.Entry) -> some View {
        let item = e.item
        return VStack(spacing: 20) {
            Spacer(minLength: 0)
            Text(item.text)
                .bigFont(item.text.count > 14 ? 40 : (item.text.count > 5 ? 72 : 120))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.4)
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: 240)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 0, y: 5)
                .padding(.horizontal, 24)
                .accessibilityLabel(item.text)
            Text(item.isSound ? "What sound does it make?" : "Can you read it?")
                .font(.callout).foregroundStyle(.secondary)
            SpeakerButton(size: 72) { Task { await model.hear(child: child) } }
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                BigButton(title: "Not yet", systemImage: "arrow.counterclockwise", color: Theme.coral) {
                    Task { await model.notYet(child: child) }
                }
                BigButton(title: "I know it", systemImage: "checkmark", color: Theme.mint) { model.know() }
            }
            .disabled(model.busy)
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
        .id(e.id)
    }

    private var summary: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text(model.knew == model.total ? "🏆" : "🌟").font(.system(size: 90)).accessibilityHidden(true)
                Text(model.knew == model.total ? "You knew them all!" : "You knew \(model.knew) of \(model.total)")
                    .bigFont(32).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                if !model.missed.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Still tricky").font(.headline).foregroundStyle(Theme.ink)
                        FlowLayout(spacing: 8) {
                            ForEach(model.missed) { m in
                                Text(m.text).font(.title3.bold()).foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Theme.sun.opacity(0.35), in: Capsule())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    BigButton(title: "Try the tricky ones", systemImage: "arrow.counterclockwise", color: Theme.coral) {
                        model.startRound(only: model.missed)
                    }
                    .padding(.horizontal, 24)
                }
                BigButton(title: "More cards", systemImage: "rectangle.stack.fill", color: Theme.grape) { model.startRound() }
                    .padding(.horizontal, 24)
                BigButton(title: "Done", color: Theme.mint) { dismiss() }
                    .padding(.horizontal, 24)
            }
            .padding(.vertical, 20)
        }
    }
}

// MARK: - Parent: custom lists

struct FlashcardListsView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: FlashcardList?
    @State private var creating = false

    var body: some View {
        List {
            Section {
                ForEach(store.flashcardLists) { list in
                    Button { editing = list } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(list.name).font(.headline)
                            Text("\(list.cards.count) card\(list.cards.count == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { offsets in
                    let lists = store.flashcardLists
                    for i in offsets { store.deleteFlashcardList(lists[i].id) }
                }
                Button { creating = true } label: { Label("New list", systemImage: "plus.circle.fill") }
            } footer: {
                Text("Lists show up under “My lists” in every reader's Flashcards. They're kept on this device.")
            }
        }
        .navigationTitle("Flashcard lists")
        .sheet(item: $editing) { FlashcardListEditor(existing: $0) }
        .sheet(isPresented: $creating) { FlashcardListEditor(existing: nil) }
    }
}

private struct FlashcardListEditor: View {
    let existing: FlashcardList?
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var text: String

    init(existing: FlashcardList?) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _text = State(initialValue: existing?.cards.joined(separator: "\n") ?? "")
    }

    private var cards: [String] { FlashcardList.parse(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("e.g. Spelling words, Week 12", text: $name) }
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 200)
                        .textInputAutocapitalization(.never)
                } header: { Text("Cards") } footer: {
                    Text("One word or sentence per line. With no line breaks, commas separate the cards. \(cards.count) card\(cards.count == 1 ? "" : "s").")
                }
            }
            .navigationTitle(existing == nil ? "New list" : "Edit list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var list = existing ?? FlashcardList(name: "", cards: [])
                        list.name = name.trimmingCharacters(in: .whitespaces)
                        list.cards = cards
                        store.saveFlashcardList(list)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || cards.isEmpty)
                }
            }
        }
    }
}
