import Foundation

enum Activity: String {
    case intro, listenPick, soundOut, build, readAloud, tapAlong
}

struct Card: Identifiable {
    let id = UUID()
    let item: Item
    var activity: Activity
    var isRetry = false
}

/// Builds today's queue: due reviews first (a few as warm-up), then new items, then the rest.
@MainActor
enum SessionPlanner {
    static func plan(child: Child, store: AppStore, now: Date = Date()) -> [Card] {
        store.advanceStageIfReady(child.id)
        let child = store.child(child.id) ?? child
        let progress = store.progress(for: child.id)
        let pool = store.pool(for: child.id)
        let poolByKey = Dictionary(pool.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })

        // Due reviews, oldest first
        let due = progress.values
            .filter { $0.dueAt <= now && poolByKey[$0.itemKey] != nil }
            .sorted { $0.dueAt < $1.dueAt }
            .prefix(child.dailyGoal)
            .compactMap { r in poolByKey[r.itemKey].map { ($0, r) } }

        // New items: current stage first, plus up to 2 parent-added words
        let room = max(3, child.dailyGoal - due.count)
        let newCount = min(room, 6)
        var fresh = Curriculum.items(inStage: child.currentStage).filter { progress[$0.key] == nil }.prefix(newCount).map { $0 }
        if fresh.count < 3 { // stage nearly done → peek at the next one so sessions never feel empty
            fresh += Curriculum.items(inStage: child.currentStage + 1).filter { progress[$0.key] == nil }.prefix(3 - fresh.count)
        }
        let customNew = store.customWords(for: child.id).map(Curriculum.customItem).filter { progress[$0.key] == nil }.prefix(2)

        var cards: [Card] = []
        let warmup = Array(due.prefix(3))
        let rest = Array(due.dropFirst(3))
        cards += warmup.map { card(for: $0.0, reps: $0.1.repetitions) }
        for item in fresh + customNew {
            cards.append(Card(item: item, activity: introActivity(for: item)))
            cards.append(Card(item: item, activity: quizActivity(for: item, reps: 0)))
        }
        cards += rest.map { card(for: $0.0, reps: $0.1.repetitions) }
        return cards
    }

    static func card(for item: Item, reps: Int) -> Card { Card(item: item, activity: quizActivity(for: item, reps: reps)) }

    private static func introActivity(for item: Item) -> Activity {
        switch item.kind {
        case .sentence, .passage: return .tapAlong
        default: return .intro
        }
    }

    /// Easier formats first; production (reading aloud) only after repeated success.
    private static func quizActivity(for item: Item, reps: Int) -> Activity {
        switch item.kind {
        case .letter, .digraph:
            return reps >= 4 ? .readAloud : .listenPick
        case .phonicsWord:
            if reps >= 3 { return .readAloud }
            return reps % 2 == 0 ? .listenPick : .build
        case .sightWord:
            return reps >= 3 ? .readAloud : .listenPick
        case .sentence, .passage:
            return .tapAlong
        }
    }

    /// Two wrong answers that look/sound similar to the target.
    static func distractors(for item: Item, in pool: [Item], count: Int = 2) -> [Item] {
        let sameKind = pool.filter { $0.kind == item.kind && $0.key != item.key && $0.say != item.say && $0.stage <= max(item.stage, 1) + 1 }
        let similar = sameKind.filter {
            $0.text.first == item.text.first || abs($0.text.count - item.text.count) <= 1
        }
        let picks = (similar.shuffled() + sameKind.shuffled())
        var out: [Item] = []
        for p in picks where !out.contains(where: { $0.key == p.key }) {
            out.append(p)
            if out.count == count { break }
        }
        return out
    }
}
