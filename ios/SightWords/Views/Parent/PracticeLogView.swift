import SwiftUI

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

    private func row(_ session: AppStore.PracticeSession) -> some View {
        let on = selected.contains(session.id)
        let cards = session.cards
        let words = cards.compactMap { store.item(forKey: $0.itemKey, child: childID) }
            .map { $0.kind == .passage ? ($0.title ?? $0.text) : $0.text }
        let preview = Array(NSOrderedSet(array: words)).compactMap { $0 as? String }.prefix(6).joined(separator: ", ")
        let stories = session.attempts.count
        var parts: [String] = []
        if !cards.isEmpty { parts.append("\(cards.count) card\(cards.count == 1 ? "" : "s")") }
        if stories > 0 { parts.append("\(stories) read-aloud\(stories == 1 ? "" : "s")") }
        let summary = parts.joined(separator: " · ")
        return Button {
            if on { selected.remove(session.id) } else { selected.insert(session.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? Theme.grape : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.start.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                    Text(summary).font(.subheadline).foregroundStyle(.secondary)
                    if !preview.isEmpty { Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.start.formatted(date: .abbreviated, time: .shortened)), \(summary)")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
