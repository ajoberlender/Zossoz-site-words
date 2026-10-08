import Foundation

/// Adaptive reading-level check. It asks a few cards at one level, then moves up after a pass or down after
/// a fail, until it has bracketed the highest level the child can read. Pure logic, no UI.
///
/// At each level: 3 right passes, 2 wrong fails (so 2–4 cards). It starts in the middle (level 3), so a
/// typical test is 8–15 cards.
struct PlacementEngine {
    private(set) var level: Int
    private(set) var current: Item?
    private(set) var finished = false
    private(set) var asked = 0
    private(set) var correctKeys = Set<String>()
    private(set) var missedKeys = Set<String>()

    private var queue: [Item] = []
    private var right = 0
    private var wrong = 0
    private var passed = Set<Int>()
    private var failed = Set<Int>()

    static let cardsPerLevel = 4
    static var levelCount: Int { Curriculum.testLevels.count }

    init(startLevel: Int = 3) {
        level = min(max(startLevel, 1), Self.levelCount)
        loadLevel()
    }

    /// Record the answer to the current card and move on.
    mutating func answer(correct: Bool) {
        guard let item = current, !finished else { return }
        asked += 1
        if correct { right += 1; correctKeys.insert(item.key) } else { wrong += 1; missedKeys.insert(item.key) }
        if right >= 3 { resolve(pass: true) }
        else if wrong >= 2 { resolve(pass: false) }
        else if queue.isEmpty { resolve(pass: right > wrong) }
        else { current = queue.removeFirst() }
    }

    /// End now with whatever has been learned so far.
    mutating func stopEarly() { finish() }

    var result: Placement {
        Placement(level: passed.max() ?? 0, correct: correctKeys, missed: missedKeys)
    }

    private mutating func resolve(pass: Bool) {
        if pass {
            passed.insert(level)
            let next = level + 1
            if next > Self.levelCount || failed.contains(next) { finish() } else { level = next; loadLevel() }
        } else {
            failed.insert(level)
            let next = level - 1
            if next < 1 || passed.contains(next) { finish() } else { level = next; loadLevel() }
        }
    }

    private mutating func loadLevel() {
        right = 0
        wrong = 0
        queue = Array(Curriculum.testLevels[level - 1].shuffled().prefix(Self.cardsPerLevel))
        if queue.isEmpty { finish() } else { current = queue.removeFirst() }
    }

    private mutating func finish() {
        finished = true
        current = nil
    }
}
