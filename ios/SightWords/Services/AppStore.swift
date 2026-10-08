import Foundation

/// Offline-first store. Everything is written to disk immediately; `sync()` reconciles with NCB.
@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snap = LocalSnapshot()
    @Published private(set) var syncing = false
    @Published private(set) var lastSyncError: String?
    @Published private(set) var lastSyncDate: Date?

    private let fileURL: URL
    private let client = NCBClient.shared

    init(userID: String) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("snapshot-\(userID).json")
        if let data = try? Data(contentsOf: fileURL) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            if let s = try? dec.decode(LocalSnapshot.self, from: data) { snap = s }
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(snap) { try? data.write(to: fileURL, options: .atomic) }
    }

    private func mutate(_ f: (inout LocalSnapshot) -> Void) {
        var s = snap
        f(&s)
        snap = s
        save()
    }

    // MARK: Children

    var children: [Child] { snap.children }
    func child(_ id: UUID) -> Child? { snap.children.first { $0.id == id } }

    func addChild(name: String, avatar: String) {
        mutate { $0.children.append(Child(name: name, avatar: avatar)) }
        Task { await sync() }
    }

    func updateChild(_ c: Child) {
        var c = c
        c.dirty = true
        mutate { s in
            if let i = s.children.firstIndex(where: { $0.id == c.id }) { s.children[i] = c }
        }
    }

    func deleteChild(_ id: UUID) {
        mutate { s in
            if let sid = s.children.first(where: { $0.id == id })?.serverID { s.deletedChildServerIDs.append(sid) }
            s.children.removeAll { $0.id == id }
            s.progress.removeAll { $0.childID == id }
            s.pendingReviews.removeAll { $0.childID == id }
            s.history.removeAll { $0.childID == id }
            s.readingHistory.removeAll { $0.childID == id }
            s.pendingAttempts.removeAll { $0.childID == id }
            s.customWords.removeAll { $0.childID == id }
            s.stories.removeAll { $0.childID == id }
        }
        Task { await sync() }
    }

    // MARK: Progress

    func progress(for childID: UUID) -> [String: ProgressRecord] {
        Dictionary(snap.progress.filter { $0.childID == childID }.map { ($0.itemKey, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Pool of items this child can be shown: built-in curriculum + parent-added words.
    func pool(for childID: UUID) -> [Item] {
        Curriculum.all + customWords(for: childID).map(Curriculum.customItem)
    }

    func item(forKey key: String, child: UUID) -> Item? {
        Curriculum.byKey[key] ?? pool(for: child).first { $0.key == key }
    }

    func record(childID: UUID, item: Item, grade: Grade, activity: String, responseMs: Int,
                heardAudio: Bool, aiFeedback: String? = nil) {
        mutate { s in
            let idx = s.progress.firstIndex { $0.childID == childID && $0.itemKey == item.key }
            let before = idx.map { s.progress[$0] }
            let prev = before ?? ProgressRecord(childID: childID, itemKey: item.key,
                                                                     itemType: item.kind.rawValue, stage: item.stage)
            let next = SRS.review(prev, grade: grade)
            if let idx { s.progress[idx] = next } else { s.progress.append(next) }
            let event = ReviewEvent(childID: childID, itemKey: item.key, activity: activity,
                                    grade: grade.rawValue, responseMs: responseMs,
                                    heardAudio: heardAudio, aiFeedback: aiFeedback,
                                    undo: ProgressUndo(previous: before))
            s.pendingReviews.append(event)
            s.history.append(event)
            if s.history.count > 20_000 { s.history.removeFirst(s.history.count - 20_000) }
        }
    }

    func history(for childID: UUID) -> [ReviewEvent] { snap.history.filter { $0.childID == childID } }

    func recordAttempt(_ a: PassageAttempt) {
        mutate { s in
            s.pendingAttempts.append(a)
            s.readingHistory.append(a)
            if s.readingHistory.count > 5_000 { s.readingHistory.removeFirst(s.readingHistory.count - 5_000) }
        }
    }

    /// Feeds how each word of a listen-along read went into spaced repetition — only for words the
    /// child is already being taught (reading a story shouldn't introduce new cards). Once per unique word,
    /// using the worst result: read cleanly → good; needed help or took several tries → hinted.
    func recordWordOutcomes(childID: UUID, details: [WordResult], activity: String = "read_along") {
        var worst: [String: Grade] = [:]
        for d in details where d.read && !d.word.isEmpty {
            let g: Grade = (d.helped || d.tries >= 2) ? .hinted : .good
            if let cur = worst[d.word], cur.rawValue <= g.rawValue { continue }
            worst[d.word] = g
        }
        let prog = progress(for: childID)
        for (w, g) in worst {
            for key in ["sight_word:\(w)", "phonics_word:\(w)", "custom:\(w)"] where prog[key] != nil {
                if let it = item(forKey: key, child: childID) {
                    record(childID: childID, item: it, grade: g, activity: activity, responseMs: 0, heardAudio: g == .hinted)
                }
            }
        }
    }

    /// Human-readable name for a passage key stored on an attempt.
    func passageTitle(_ key: String) -> String {
        if key.hasPrefix("story:"), let s = snap.stories.first(where: { "story:\($0.id)" == key }) { return s.title }
        if key.hasPrefix("passage:") { return Curriculum.byKey[key]?.title ?? String(key.dropFirst("passage:".count)) }
        return Curriculum.byKey[key]?.title ?? Curriculum.byKey[key]?.text ?? key
    }

    func readingAttempts(for childID: UUID) -> [PassageAttempt] {
        snap.readingHistory.filter { $0.childID == childID }.sorted { $0.date > $1.date }
    }

    /// Words this child keeps needing help with while reading aloud, most often first.
    func stumbleWords(childID: UUID, limit: Int = 10) -> [(word: String, count: Int)] {
        var counts: [String: Int] = [:]
        for a in readingAttempts(for: childID) {
            if let words = a.words {
                for w in words where !w.word.isEmpty && (w.helped || w.tries >= 2) { counts[w.word, default: 0] += 1 }
            } else {
                for w in a.missedWords where !w.isEmpty { counts[w, default: 0] += 1 }
            }
        }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(limit).map { ($0.key, $0.value) }
    }

    /// Moves a child up a stage once ≥80% of the current stage has been seen twice.
    @discardableResult
    func advanceStageIfReady(_ childID: UUID) -> Bool {
        guard var c = child(childID), c.currentStage < Curriculum.stages.count else { return false }
        let prog = progress(for: childID)
        let items = Curriculum.items(inStage: c.currentStage)
        guard !items.isEmpty else { return false }
        let solid = items.filter { (prog[$0.key]?.repetitions ?? 0) >= 2 }.count
        guard Double(solid) / Double(items.count) >= 0.8 else { return false }
        c.currentStage += 1
        updateChild(c)
        return true
    }

    func finishSession(childID: UUID, starsEarned: Int) {
        guard var c = child(childID) else { return }
        Self.registerPractice(&c, on: Date())
        c.stars += starsEarned
        updateChild(c)
        Task { await sync() }
    }

    /// Streak bookkeeping for practice on `date` (never moves the streak backwards in time).
    private static func registerPractice(_ c: inout Child, on date: Date) {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        if let last = c.lastPracticeDate.map({ cal.startOfDay(for: $0) }) {
            let days = cal.dateComponents([.day], from: last, to: day).day ?? 0
            if days < 0 { return }
            if days == 1 { c.streakDays += 1 } else if days > 1 { c.streakDays = 1 }
            if days == 0 && c.streakDays == 0 { c.streakDays = 1 }
        } else { c.streakDays = 1 }
        c.lastPracticeDate = date
    }

    // MARK: Practice log — fixing a session filed under the wrong reader

    struct PracticeSession: Identifiable {
        var id: Date { start }
        var events: [ReviewEvent]
        var attempts: [PassageAttempt]
        var start: Date
        var end: Date

        /// Word-level detail events aren't "cards" the child was shown.
        var cards: [ReviewEvent] { events.filter { !Self.detailActivities.contains($0.activity) } }
        static let detailActivities: Set<String> = ["read_along", "story_help"]
    }

    /// Groups a reader's recent activity into sessions (a gap of 20+ minutes starts a new one), newest first.
    func practiceSessions(for childID: UUID, limit: Int = 40) -> [PracticeSession] {
        enum Mark { case event(ReviewEvent), attempt(PassageAttempt) }
        var marks: [(Date, Mark)] = snap.history.filter { $0.childID == childID }.map { ($0.date, Mark.event($0)) }
        marks += snap.readingHistory.filter { $0.childID == childID }.map { ($0.date, Mark.attempt($0)) }
        marks.sort { $0.0 < $1.0 }

        var sessions: [PracticeSession] = []
        for (date, mark) in marks {
            if var last = sessions.last, date.timeIntervalSince(last.end) < 20 * 60 {
                last.end = date
                switch mark { case .event(let e): last.events.append(e); case .attempt(let a): last.attempts.append(a) }
                sessions[sessions.count - 1] = last
            } else {
                var n = PracticeSession(events: [], attempts: [], start: date, end: date)
                switch mark { case .event(let e): n.events.append(e); case .attempt(let a): n.attempts.append(a) }
                sessions.append(n)
            }
        }
        return Array(sessions.reversed().prefix(limit))
    }

    /// Moves practice from one reader to another (`to == nil` deletes it). The first reader's progress is
    /// rewound to how it was before those events and the second reader's is replayed forward, stars follow,
    /// and streaks are adjusted. Anything already uploaded to the cloud review log stays there under the
    /// original reader; progress and stats on the devices are corrected and synced.
    func reassign(_ sessions: [PracticeSession], from source: UUID, to dest: UUID?) {
        let events = sessions.flatMap(\.events).sorted { $0.date < $1.date }
        let attempts = sessions.flatMap(\.attempts)
        guard !events.isEmpty || !attempts.isEmpty else { return }
        let selected = Set(events)
        let selectedAttempts = Set(attempts)
        let keys = Set(events.map(\.itemKey))
        var itemsByKey: [String: Item] = [:]
        if let dest { for k in keys { if let it = item(forKey: k, child: dest) { itemsByKey[k] = it } } }

        mutate { s in
            // 1. Rewind the source reader's progress for every item touched.
            for key in keys {
                guard let first = events.first(where: { $0.itemKey == key }), let undo = first.undo,
                      let cur = s.progress.firstIndex(where: { $0.childID == source && $0.itemKey == key }) else { continue }
                let current = s.progress[cur]
                var base = undo.previous ?? ProgressRecord(childID: source, itemKey: key, itemType: current.itemType, stage: current.stage)
                base.serverID = current.serverID
                // Replay what they genuinely did afterwards, refreshing each event's own "before" snapshot.
                let later = s.history.enumerated()
                    .filter { $0.element.childID == source && $0.element.itemKey == key && $0.element.date >= first.date && !selected.contains($0.element) }
                    .sorted { $0.element.date < $1.element.date }
                for (idx, e) in later {
                    s.history[idx].undo = ProgressUndo(previous: base)
                    base = SRS.review(base, grade: Grade(rawValue: e.grade) ?? .good, now: e.date)
                }
                base.dirty = true
                s.progress[cur] = base
            }

            // 2. Replay onto the destination reader.
            var moved: [ReviewEvent] = []
            if let dest {
                for e in events {
                    var m = e
                    m.childID = dest
                    if let item = itemsByKey[e.itemKey] {
                        let idx = s.progress.firstIndex { $0.childID == dest && $0.itemKey == e.itemKey }
                        let before = idx.map { s.progress[$0] }
                        let prev = before ?? ProgressRecord(childID: dest, itemKey: item.key, itemType: item.kind.rawValue, stage: item.stage)
                        let next = SRS.review(prev, grade: Grade(rawValue: e.grade) ?? .good, now: e.date)
                        if let idx { s.progress[idx] = next } else { s.progress.append(next) }
                        m.undo = ProgressUndo(previous: before)
                    } else {
                        m.undo = nil // not an item the destination has (e.g. the other reader's custom word)
                    }
                    moved.append(m)
                }
            }

            // 3. Swap the events and attempts over.
            let wasPending = Set(s.pendingReviews).intersection(selected)
            s.history.removeAll { selected.contains($0) }
            s.pendingReviews.removeAll { selected.contains($0) }
            if dest != nil {
                s.history.append(contentsOf: moved)
                s.history.sort { $0.date < $1.date }
                for (orig, m) in zip(events, moved) where wasPending.contains(orig) { s.pendingReviews.append(m) }
            }
            let pendingAttempts = Set(s.pendingAttempts).intersection(selectedAttempts)
            s.readingHistory.removeAll { selectedAttempts.contains($0) }
            s.pendingAttempts.removeAll { selectedAttempts.contains($0) }
            if let dest {
                let movedAttempts: [PassageAttempt] = attempts.map { var a = $0; a.childID = dest; return a }
                s.readingHistory.append(contentsOf: movedAttempts)
                s.readingHistory.sort { $0.date < $1.date }
                for (orig, m) in zip(attempts, movedAttempts) where pendingAttempts.contains(orig) { s.pendingAttempts.append(m) }
            }

            // 4. Stars and streaks. Only flash-card answers earned stars.
            let starEvents = events.filter { $0.grade >= Grade.good.rawValue && !PracticeSession.detailActivities.contains($0.activity) && $0.activity != "story" }
            let earned = starEvents.count
            let cal = Calendar.current
            if let si = s.children.firstIndex(where: { $0.id == source }) {
                s.children[si].stars = max(0, s.children[si].stars - earned)
                // If that was the only practice on the last practice day, step the streak back.
                if let last = s.children[si].lastPracticeDate {
                    let stillPracticed = s.history.contains { $0.childID == source && cal.isDate($0.date, inSameDayAs: last) }
                    let removedThatDay = events.contains { cal.isDate($0.date, inSameDayAs: last) }
                        || attempts.contains { cal.isDate($0.date, inSameDayAs: last) }
                    if removedThatDay && !stillPracticed {
                        s.children[si].streakDays = max(0, s.children[si].streakDays - 1)
                        s.children[si].lastPracticeDate = s.history.filter { $0.childID == source }.map(\.date).max()
                    }
                }
                s.children[si].dirty = true
            }
            if let dest, let di = s.children.firstIndex(where: { $0.id == dest }) {
                s.children[di].stars += earned
                var c = s.children[di]
                let days = Set((events.map(\.date) + attempts.map(\.date)).map { cal.startOfDay(for: $0) }).sorted()
                for d in days { Self.registerPractice(&c, on: d) }
                c.dirty = true
                s.children[di] = c
            }
        }
        Task { await sync() }
    }

    // MARK: Custom words & stories

    func customWords(for childID: UUID) -> [CustomWord] { snap.customWords.filter { $0.childID == childID } }

    func addCustomWord(childID: UUID, word: String, sentence: String?, note: String?) {
        let w = word.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty else { return }
        mutate { $0.customWords.append(CustomWord(childID: childID, word: w, sentence: sentence, note: note)) }
        Task { await sync() }
    }

    func deleteCustomWord(_ id: UUID) {
        mutate { s in
            if let sid = s.customWords.first(where: { $0.id == id })?.serverID { s.deletedCustomWordServerIDs.append(sid) }
            s.customWords.removeAll { $0.id == id }
        }
        Task { await sync() }
    }

    func stories(for childID: UUID) -> [GeneratedStory] {
        snap.stories.filter { $0.childID == childID }.sorted { $0.date > $1.date }
    }
    func saveStory(_ s: GeneratedStory) { mutate { $0.stories.append(s) } }

    // MARK: Stats

    func masteredCount(childID: UUID, stage: Int) -> (mastered: Int, seen: Int, total: Int) {
        let prog = progress(for: childID)
        let items = Curriculum.items(inStage: stage)
        return (items.filter { prog[$0.key]?.mastered == true }.count,
                items.filter { (prog[$0.key]?.repetitions ?? 0) > 0 }.count,
                items.count)
    }

    /// Items the child keeps missing, worst first.
    func trouble(childID: UUID, limit: Int = 8) -> [(Item, ProgressRecord)] {
        progress(for: childID).values
            .filter { $0.lapses > 0 }
            .sorted { ($0.lapses, -$0.ease) > ($1.lapses, -$1.ease) }
            .compactMap { r in item(forKey: r.itemKey, child: childID).map { ($0, r) } }
            .prefix(limit).map { $0 }
    }

    /// Words the child has actually learned (used to constrain AI stories).
    func knownWords(childID: UUID) -> [String] {
        progress(for: childID).values
            .filter { $0.repetitions >= 2 && ($0.itemType == "sight_word" || $0.itemType == "phonics_word") }
            .compactMap { item(forKey: $0.itemKey, child: childID)?.text.lowercased() }
    }
}

// MARK: - Sync

extension AppStore {
    func sync() async {
        guard !syncing, client.token != nil else { return }
        syncing = true
        defer { syncing = false }
        do {
            try await push()
            try await pull()
            lastSyncError = nil
            lastSyncDate = Date()
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    private func serverID(of childID: UUID) -> Int? { child(childID)?.serverID }

    private func push() async throws {
        // 1. Deletions
        for sid in snap.deletedChildServerIDs {
            try await client.delete("children", id: sid)
            mutate { $0.deletedChildServerIDs.removeAll { $0 == sid } }
        }
        for sid in snap.deletedCustomWordServerIDs {
            try await client.delete("custom_words", id: sid)
            mutate { $0.deletedCustomWordServerIDs.removeAll { $0 == sid } }
        }

        // 2. Children first (everything else references child_id)
        for c in snap.children where c.dirty {
            let body: [String: Any] = [
                "name": c.name, "avatar": c.avatar, "current_stage": c.currentStage,
                "tts_voice": c.voiceID ?? NSNull(), "tts_rate": c.speechRate, "daily_goal": c.dailyGoal,
                "streak_days": c.streakDays, "stars": c.stars,
                "last_practice_date": c.lastPracticeDate.map(NCBDate.string) ?? NSNull(),
            ]
            if let sid = c.serverID { try await client.update("children", id: sid, body) }
            else {
                let sid = try await client.create("children", body)
                mutate { s in if let i = s.children.firstIndex(where: { $0.id == c.id }) { s.children[i].serverID = sid } }
            }
            mutate { s in if let i = s.children.firstIndex(where: { $0.id == c.id }) { s.children[i].dirty = false } }
        }

        // 3. Progress
        for p in snap.progress where p.dirty {
            guard let csid = serverID(of: p.childID) else { continue }
            let body: [String: Any] = [
                "child_id": csid, "item_key": p.itemKey, "item_type": p.itemType, "stage": p.stage,
                "ease": p.ease, "interval_days": p.intervalDays, "repetitions": p.repetitions, "lapses": p.lapses,
                "due_at": NCBDate.string(p.dueAt),
                "last_reviewed_at": p.lastReviewedAt.map(NCBDate.string) ?? NSNull(),
                "mastered": p.mastered ? 1 : 0,
            ]
            var sid = p.serverID
            if let existing = sid { try await client.update("item_progress", id: existing, body) }
            else { sid = try await client.create("item_progress", body) }
            mutate { s in
                if let i = s.progress.firstIndex(where: { $0.childID == p.childID && $0.itemKey == p.itemKey }) {
                    s.progress[i].serverID = sid
                    if s.progress[i].lastReviewedAt == p.lastReviewedAt { s.progress[i].dirty = false }
                }
            }
        }

        // 4. Custom words
        for w in snap.customWords where w.dirty {
            guard let csid = serverID(of: w.childID) else { continue }
            let body: [String: Any] = ["child_id": csid, "word": w.word,
                                       "sentence": w.sentence ?? NSNull(), "note": w.note ?? NSNull()]
            if let sid = w.serverID { try await client.update("custom_words", id: sid, body) }
            else {
                let sid = try await client.create("custom_words", body)
                mutate { s in if let i = s.customWords.firstIndex(where: { $0.id == w.id }) { s.customWords[i].serverID = sid } }
            }
            mutate { s in if let i = s.customWords.firstIndex(where: { $0.id == w.id }) { s.customWords[i].dirty = false } }
        }

        // 5. Append-only logs, in chunks
        let reviews = snap.pendingReviews.filter { serverID(of: $0.childID) != nil }
        for chunk in reviews.chunked(100) {
            let records: [[String: Any]] = chunk.map { e in
                ["child_id": serverID(of: e.childID)!, "item_key": e.itemKey, "activity": e.activity,
                 "grade": e.grade, "response_ms": e.responseMs, "heard_audio": e.heardAudio ? 1 : 0,
                 "ai_feedback": e.aiFeedback ?? NSNull()]
            }
            try await client.bulkCreate("review_log", records: records)
            let sent = Set(chunk)
            mutate { $0.pendingReviews.removeAll { sent.contains($0) } }
        }
        let attempts = snap.pendingAttempts.filter { serverID(of: $0.childID) != nil }
        for chunk in attempts.chunked(100) {
            let records: [[String: Any]] = chunk.map { a in
                ["child_id": serverID(of: a.childID)!, "passage_key": a.passageKey, "words_total": a.wordsTotal,
                 "words_correct": a.wordsCorrect, "duration_sec": a.durationSec,
                 "missed_words": a.missedWords.joined(separator: ",")]
            }
            try await client.bulkCreate("passage_attempts", records: records)
            let sent = Set(chunk)
            mutate { $0.pendingAttempts.removeAll { sent.contains($0) } }
        }
    }

    private func pull() async throws {
        let childRows = try await client.readAll("children")
        let progressRows = try await client.readAll("item_progress")
        let wordRows = try await client.readAll("custom_words")

        mutate { s in
            // Children
            let serverIDs = Set(childRows.compactMap { $0.int("id") })
            for row in childRows {
                guard let sid = row.int("id") else { continue }
                if let i = s.children.firstIndex(where: { $0.serverID == sid }) {
                    if s.children[i].dirty { continue } // local edits win until pushed
                    s.children[i] = Self.child(from: row, keeping: s.children[i])
                } else {
                    s.children.append(Self.child(from: row, keeping: Child(name: row.string("name") ?? "Reader")))
                }
            }
            // Removed on another device
            let gone = s.children.filter { $0.serverID != nil && !serverIDs.contains($0.serverID!) && !$0.dirty }.map(\.id)
            s.children.removeAll { gone.contains($0.id) }
            s.progress.removeAll { gone.contains($0.childID) }

            let localByServer = Dictionary(uniqueKeysWithValues: s.children.compactMap { c in c.serverID.map { ($0, c.id) } })

            // Progress
            for row in progressRows {
                guard let csid = row.int("child_id"), let cid = localByServer[csid], let key = row.string("item_key") else { continue }
                let remote = ProgressRecord(
                    childID: cid, itemKey: key, itemType: row.string("item_type") ?? "sight_word", stage: row.int("stage") ?? 0,
                    ease: row.double("ease") ?? 2.5, intervalDays: row.double("interval_days") ?? 0,
                    repetitions: row.int("repetitions") ?? 0, lapses: row.int("lapses") ?? 0,
                    dueAt: row.date("due_at") ?? Date(), lastReviewedAt: row.date("last_reviewed_at"),
                    mastered: row.bool("mastered"), serverID: row.int("id"), dirty: false)
                if let i = s.progress.firstIndex(where: { $0.childID == cid && $0.itemKey == key }) {
                    let local = s.progress[i]
                    if local.dirty || (local.lastReviewedAt ?? .distantPast) > (remote.lastReviewedAt ?? .distantPast) {
                        s.progress[i].serverID = remote.serverID // keep local data, adopt id
                    } else { s.progress[i] = remote }
                } else { s.progress.append(remote) }
            }

            // Custom words
            let wordServerIDs = Set(wordRows.compactMap { $0.int("id") })
            for row in wordRows {
                guard let sid = row.int("id"), let csid = row.int("child_id"), let cid = localByServer[csid],
                      let word = row.string("word") else { continue }
                if !s.customWords.contains(where: { $0.serverID == sid }) {
                    s.customWords.append(CustomWord(serverID: sid, childID: cid, word: word,
                                                    sentence: row.string("sentence"), note: row.string("note"), dirty: false))
                }
            }
            s.customWords.removeAll { $0.serverID != nil && !wordServerIDs.contains($0.serverID!) && !$0.dirty }
        }
    }

    private static func child(from row: [String: Any], keeping base: Child) -> Child {
        var c = base
        c.serverID = row.int("id")
        c.name = row.string("name") ?? base.name
        c.avatar = row.string("avatar") ?? base.avatar
        c.currentStage = row.int("current_stage") ?? base.currentStage
        c.voiceID = row.string("tts_voice")
        c.speechRate = row.double("tts_rate") ?? base.speechRate
        c.dailyGoal = row.int("daily_goal") ?? base.dailyGoal
        c.streakDays = row.int("streak_days") ?? 0
        c.lastPracticeDate = row.date("last_practice_date")
        c.stars = row.int("stars") ?? 0
        c.dirty = false
        return c
    }
}

private extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
