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
            let prev = idx.map { s.progress[$0] } ?? ProgressRecord(childID: childID, itemKey: item.key,
                                                                     itemType: item.kind.rawValue, stage: item.stage)
            let next = SRS.review(prev, grade: grade)
            if let idx { s.progress[idx] = next } else { s.progress.append(next) }
            s.pendingReviews.append(ReviewEvent(childID: childID, itemKey: item.key, activity: activity,
                                                grade: grade.rawValue, responseMs: responseMs,
                                                heardAudio: heardAudio, aiFeedback: aiFeedback))
        }
    }

    func recordAttempt(_ a: PassageAttempt) { mutate { $0.pendingAttempts.append(a) } }

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
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        if let last = c.lastPracticeDate.map({ cal.startOfDay(for: $0) }) {
            let days = cal.dateComponents([.day], from: last, to: today).day ?? 0
            if days == 1 { c.streakDays += 1 } else if days > 1 { c.streakDays = 1 }
            if days == 0 && c.streakDays == 0 { c.streakDays = 1 }
        } else { c.streakDays = 1 }
        c.lastPracticeDate = Date()
        c.stars += starsEarned
        updateChild(c)
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
