import Foundation

/// Result of a read-aloud, whichever way it was done (listening or tapping).
struct ReadOutcome {
    var helped: [String]       // unique words the child needed help with or never reached
    var total: Int             // unique words in the text
    var seconds: Int
    var details: [WordResult]? // per displayed word, in order; nil for tap-along
}

/// Follows a child reading a text aloud. Pure logic with no audio or UI: feed it the words the
/// recognizer heard and it says where the child has got to. The cursor only moves when the next
/// expected word is heard, so a wrong or missing word leaves the highlight where it is.
struct ReadAlongTracker {
    private(set) var targets: [String]       // normalized, one per displayed word ("" = nothing to say)
    private(set) var cursor = 0
    private(set) var results: [WordResult]
    private var consumed = 0                 // recognizer tokens already looked at, in this segment
    private var wrongForCurrent = 0
    private var wordStart: Date
    private var preHelped: Set<Int> = []

    init(words: [String], now: Date = Date()) {
        targets = words.map(Self.normalize)
        results = targets.map { WordResult(word: $0) }
        wordStart = now
        skipBlanks()
    }

    var isFinished: Bool { cursor >= targets.count }

    // MARK: Feeding the recognizer

    /// The recognizer started a fresh utterance (it times out about once a minute); its token list restarts.
    mutating func newSegment() { consumed = 0 }

    /// `tokens` is everything heard so far in the current segment. The last token of a partial result
    /// can still be revised by the recognizer, so a mismatch there isn't counted until more arrives
    /// (or `final`). A match is accepted straight away so the highlight feels instant.
    /// Returns true if the cursor moved.
    @discardableResult
    mutating func ingest(tokens: [String], final: Bool, now: Date = Date()) -> Bool {
        var moved = false
        var i = consumed
        while i < tokens.count, !isFinished {
            let tok = tokens[i]
            if Self.matches(tok, targets[cursor]) {
                complete(now: now)
                moved = true
                i += 1; consumed = i
                continue
            }
            // Speech recognition routinely swallows tiny function words ("a", "the", "of"). If the child has clearly
            // moved on to the word after one, count the small word as read instead of leaving them stuck on it.
            if Self.softWords.contains(targets[cursor]), let nxt = nextTarget(after: cursor), Self.matches(tok, targets[nxt]) {
                complete(now: now)   // the small word
                complete(now: now)   // the word just heard
                moved = true
                i += 1; consumed = i
                continue
            }
            if Self.fillers.contains(tok) { i += 1; consumed = i; continue }
            if i == tokens.count - 1, !final { break }
            // A stable wrong word. Saying the previous word again (or the recognizer splitting it) isn't a mistake.
            let repeatsPrevious = cursor > 0 && Self.matches(tok, targets[cursor - 1])
            if !repeatsPrevious { wrongForCurrent += 1 }
            i += 1; consumed = i
        }
        return moved
    }

    /// The child asked for (or was given) help with the word at `index`. The current word is read to
    /// them and the cursor moves on; a later word is remembered so it counts as helped when reached.
    @discardableResult
    mutating func help(at index: Int, now: Date = Date()) -> Bool {
        guard index >= 0, index < targets.count, index >= cursor, !targets[index].isEmpty else { return false }
        if index == cursor {
            preHelped.insert(index)
            complete(now: now)
            return true
        }
        preHelped.insert(index)
        return false
    }

    // MARK: Results

    func outcome(seconds: Int) -> ReadOutcome {
        var helped = Set<String>()
        var unique = Set<String>()
        for r in results where !r.word.isEmpty {
            unique.insert(r.word)
            if r.helped || !r.read { helped.insert(r.word) }
        }
        return ReadOutcome(helped: helped.sorted(), total: unique.count, seconds: seconds,
                           details: results.filter { !$0.word.isEmpty })
    }

    // MARK: Internals

    private mutating func complete(now: Date) {
        let ms = min(10_000, max(0, Int(now.timeIntervalSince(wordStart) * 1000)))
        results[cursor].tries = wrongForCurrent
        results[cursor].helped = preHelped.contains(cursor)
        results[cursor].ms = ms
        results[cursor].read = true
        cursor += 1
        wrongForCurrent = 0
        wordStart = now
        skipBlanks()
    }

    private func nextTarget(after index: Int) -> Int? {
        var j = index + 1
        while j < targets.count {
            if !targets[j].isEmpty { return j }
            j += 1
        }
        return nil
    }

    private mutating func skipBlanks() {
        while cursor < targets.count, targets[cursor].isEmpty { cursor += 1 }
    }

    // MARK: Text helpers

    /// Short words recognizers often drop or mishear; the tracker doesn't hold the child on these.
    private static let softWords: Set<String> = ["a", "an", "the", "of", "to", "in", "is", "it", "at", "on", "as", "and", "i"]

    /// How these words commonly come back from the recognizer when a child says them quickly.
    private static let variants: [String: Set<String>] = [
        "a": ["uh", "eh", "ah", "ay", "er", "8"], "the": ["thee", "thuh", "duh", "da", "de", "th", "this"],
        "to": ["too", "two", "tu", "tuh", "2"], "of": ["uv", "ov", "off"], "is": ["iz", "its"],
        "i": ["eye", "ai", "hi"], "an": ["on", "en"], "and": ["an", "en", "in"], "at": ["it", "eh"],
        "in": ["an", "en"], "it": ["at", "eat"], "on": ["an", "own"], "as": ["is", "has"],
    ]

    private static let fillers: Set<String> = ["um", "uh", "umm", "uhh", "hmm", "mm", "er", "ah"]

    private static let numberWords = ["0": "zero", "1": "one", "2": "two", "3": "three", "4": "four", "5": "five",
                                      "6": "six", "7": "seven", "8": "eight", "9": "nine", "10": "ten"]

    /// Lowercase, keep letters/digits/apostrophes, spell out small numbers.
    static func normalize(_ word: String) -> String {
        let kept = word.lowercased().replacingOccurrences(of: "’", with: "'")
            .filter { $0.isLetter || $0.isNumber || $0 == "'" }
        let trimmed = kept.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        return numberWords[trimmed] ?? trimmed
    }

    /// Recognizer output → tokens comparable with `normalize`d targets.
    static func tokens(from transcript: String) -> [String] {
        transcript.lowercased().replacingOccurrences(of: "’", with: "'")
            .split { !($0.isLetter || $0.isNumber || $0 == "'") }
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
    }

    static func matches(_ heard: String, _ target: String) -> Bool {
        if heard == target { return true }
        if homophone(heard, target) { return true }
        if variants[target]?.contains(heard) == true { return true }
        // Small-child speech and on-device recognition are imperfect: allow one slip on longer words.
        if heard.count >= 4, target.count >= 4, editDistance(heard, target) <= 1 { return true }
        return false
    }

    static func homophone(_ a: String, _ b: String) -> Bool {
        homophoneGroups.contains { $0.contains(a) && $0.contains(b) }
    }

    private static let homophoneGroups: [[String]] = [
        ["to", "too", "two"], ["for", "four", "fore"], ["no", "know"], ["see", "sea"], ["one", "won"],
        ["red", "read"], ["be", "bee"], ["i", "eye"], ["there", "their", "they're"], ["our", "are"], ["by", "buy", "bye"],
        ["new", "knew"], ["write", "right"], ["would", "wood"], ["so", "sew"], ["ate", "eight"],
        ["hear", "here"], ["sun", "son"], ["blue", "blew"], ["hi", "high"], ["nose", "knows"], ["meet", "meat"],
        ["tail", "tale"], ["wait", "weight"], ["pair", "pear", "pare"], ["bear", "bare"], ["in", "inn"],
        ["a", "uh"], ["the", "thee"], ["its", "it's"], ["your", "you're"], ["whole", "hole"], ["week", "weak"],
    ]

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }
}
