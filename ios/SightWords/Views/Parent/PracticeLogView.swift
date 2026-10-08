import SwiftUI

/// "Wasn't Maya?" — behind the grown-up gate, moves the reader's most recent practice to someone else.
/// Used on the finish screens after flashcards and after a story.
struct WrongReaderButton: View {
    let childID: UUID
    var onMoved: () -> Void
    @EnvironmentObject var store: AppStore
    @State private var showGate = false
    @State private var gatePassed = false
    @State private var showChoice = false

    var body: some View {
        if let name = store.child(childID)?.name, store.children.count > 1 {
            Button("Wasn't \(name)? Move this practice…") { showGate = true }
                .font(.callout)
                .sheet(isPresented: $showGate, onDismiss: {
                    if gatePassed { gatePassed = false; showChoice = true }
                }) { GrownUpGate { gatePassed = true } }
                .confirmationDialog("Who was actually reading?", isPresented: $showChoice, titleVisibility: .visible) {
                    ForEach(store.children.filter { $0.id != childID }) { other in
                        Button("\(other.avatar) \(other.name)") {
                            if let latest = store.practiceSessions(for: childID, limit: 1).first {
                                store.reassign([latest], from: childID, to: other.id)
                            }
                            onMoved()
                        }
                    }
                } message: { Text("This practice, its progress and stars move to them.") }
        }
    }
}

/// Lists a reader's recent practice sessions so a grown-up can move one that was filed under the
/// wrong reader to the right one (or delete it).
struct PracticeLogView: View {
    let childID: UUID
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<Date>()
    @State private var moveTo: Child?
    @State private var confirmDelete = false

    private var sessions: [AppStore.PracticeSession] { store.practiceSessions(for: childID) }
    private var chosen: [AppStore.PracticeSession] { sessions.filter { selected.contains($0.id) } }
    private var others: [Child] { store.children.filter { $0.id != childID } }
    private var name: String { store.child(childID)?.name ?? "this reader" }

    var body: some View {
        List {
            if sessions.isEmpty {
                Text("No practice recorded yet.").foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(sessions) { session in row(session) }
                } header: {
                    Text("Recent practice")
                } footer: {
                    Text("Tick the sessions that were really someone else, then choose who. Their progress, stars and stats move with it.")
                }
            }
        }
        .task { _ = await store.importCloudReads(for: childID) }
        .navigationTitle("Practice log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Menu {
                    ForEach(others) { other in
                        Button("\(other.avatar) \(other.name)") { moveTo = other }
                    }
                } label: { Label("Move to…", systemImage: "arrow.right.circle") }
                    .disabled(selected.isEmpty || others.isEmpty)
                Spacer()
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                    .disabled(selected.isEmpty)
            }
        }
        .confirmationDialog(moveTitle, isPresented: Binding(get: { moveTo != nil }, set: { if !$0 { moveTo = nil } }),
                            titleVisibility: .visible) {
            Button("Move") {
                if let to = moveTo { store.reassign(chosen, from: childID, to: to.id) }
                selected = []; moveTo = nil
            }
        } message: {
            Text("Spaced-repetition progress, stars and streak are adjusted for both readers. Anything already uploaded to the cloud log keeps its original reader.")
        }
        .confirmationDialog("Delete \(chosen.count) session\(chosen.count == 1 ? "" : "s") from \(name)?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.reassign(chosen, from: childID, to: nil)
                selected = []
            }
        } message: { Text("Their progress goes back to how it was before this practice.") }
    }

    private var moveTitle: String {
        let cards = chosen.reduce(0) { $0 + $1.cards.count }
        return "Move \(chosen.count) session\(chosen.count == 1 ? "" : "s") (\(cards) cards) from \(name) to \(moveTo?.name ?? "…")?"
    }

    private static func when(_ s: AppStore.PracticeSession) -> String {
        s.start < Date(timeIntervalSince1970: 946_684_800) // before 2000 = imported from the cloud without a date
            ? "Earlier read (date unknown)"
            : s.start.formatted(date: .abbreviated, time: .shortened)
    }

    private func row(_ session: AppStore.PracticeSession) -> some View {
        let on = selected.contains(session.id)
        let cards = session.cards
        let words = cards.compactMap { store.item(forKey: $0.itemKey, child: childID) }
            .map { $0.kind == .passage ? ($0.title ?? $0.text) : $0.text }
        let preview = Array(NSOrderedSet(array: words)).compactMap { $0 as? String }.prefix(6).joined(separator: ", ")
        let stories = session.attempts.count
        var parts: [String] = []
        if !cards.isEmpty { parts.append("\(cards.count) card\(cards.count == 1 ? "" : "s")") }
        if stories > 0 {
            let titles = session.attempts.map { store.passageTitle($0.passageKey) }
            parts.append(stories == 1 ? "read “\(titles[0])”" : "\(stories) read-alouds")
        }
        let summary = parts.joined(separator: " · ")
        return Button {
            if on { selected.remove(session.id) } else { selected.insert(session.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? Theme.grape : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.when(session)).font(.headline)
                    Text(summary).font(.subheadline).foregroundStyle(.secondary)
                    if !preview.isEmpty { Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Self.when(session)), \(summary)")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
