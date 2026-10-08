import Foundation

struct Child: Codable, Identifiable, Hashable {
    var id = UUID()
    var serverID: Int?
    var name: String
    var avatar: String = "🦄"
    var currentStage: Int = 1
    var voiceID: String?
    var speechRate: Double = 0.42 // AVSpeechUtterance scale (default is 0.5); a little slower for learners
    var dailyGoal: Int = 10
    var streakDays: Int = 0
    var lastPracticeDate: Date?
    var stars: Int = 0
    var dirty: Bool = true
}

struct ProgressRecord: Codable, Hashable {
    var childID: UUID
    var itemKey: String
    var itemType: String
    var stage: Int
    var ease: Double = 2.5
    var intervalDays: Double = 0
    var repetitions: Int = 0
    var lapses: Int = 0
    var dueAt: Date = Date()
    var lastReviewedAt: Date?
    var mastered: Bool = false
    var serverID: Int?
    var dirty: Bool = true
}

/// What an item's progress looked like just before an event was applied, so a mis-filed
/// practice session can be rewound. `nil` on events logged before this existed.
struct ProgressUndo: Codable, Hashable {
    var previous: ProgressRecord?
}

/// How one word of a read-aloud went.
struct WordResult: Codable, Hashable {
    var word: String      // lowercased, punctuation stripped
    var tries: Int = 0    // wrong things heard before the right word
    var helped: Bool = false
    var ms: Int = 0
    var read: Bool = false // false = the child stopped before reaching it
}

struct ReviewEvent: Codable, Hashable {
    var childID: UUID
    var itemKey: String
    var activity: String
    var grade: Int
    var responseMs: Int
    var heardAudio: Bool
    var aiFeedback: String?
    var date: Date = Date()
    var undo: ProgressUndo?
}

struct PassageAttempt: Codable, Hashable {
    var childID: UUID
    var passageKey: String
    var wordsTotal: Int
    var wordsCorrect: Int
    var durationSec: Int
    var missedWords: [String]
    var date: Date = Date()
    /// Per-word detail from listen-along reading. `nil` for tap-along reads and older attempts.
    var words: [WordResult]?
}

struct CustomWord: Codable, Identifiable, Hashable {
    var id = UUID()
    var serverID: Int?
    var childID: UUID
    var word: String
    var sentence: String?
    var note: String?
    var dirty: Bool = true
}

/// A story the on-device model wrote for one child. Kept on this device only.
struct GeneratedStory: Codable, Identifiable, Hashable {
    var id = UUID()
    var childID: UUID
    var title: String
    var body: String
    var date: Date = Date()
}

/// Everything persisted locally (offline-first), synced to NCB when online.
struct LocalSnapshot: Codable {
    var children: [Child] = []
    var progress: [ProgressRecord] = []
    var pendingReviews: [ReviewEvent] = []
    var pendingAttempts: [PassageAttempt] = []
    var customWords: [CustomWord] = []
    var deletedCustomWordServerIDs: [Int] = []
    var deletedChildServerIDs: [Int] = []
    var stories: [GeneratedStory] = []
    /// Permanent local activity log (pendingReviews is cleared after sync) — powers parent analytics.
    var history: [ReviewEvent] = []
    /// Permanent local log of passage reads (pendingAttempts is cleared after sync).
    var readingHistory: [PassageAttempt] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        children = try c.decodeIfPresent([Child].self, forKey: .children) ?? []
        progress = try c.decodeIfPresent([ProgressRecord].self, forKey: .progress) ?? []
        pendingReviews = try c.decodeIfPresent([ReviewEvent].self, forKey: .pendingReviews) ?? []
        pendingAttempts = try c.decodeIfPresent([PassageAttempt].self, forKey: .pendingAttempts) ?? []
        customWords = try c.decodeIfPresent([CustomWord].self, forKey: .customWords) ?? []
        deletedCustomWordServerIDs = try c.decodeIfPresent([Int].self, forKey: .deletedCustomWordServerIDs) ?? []
        deletedChildServerIDs = try c.decodeIfPresent([Int].self, forKey: .deletedChildServerIDs) ?? []
        stories = try c.decodeIfPresent([GeneratedStory].self, forKey: .stories) ?? []
        history = try c.decodeIfPresent([ReviewEvent].self, forKey: .history) ?? []
        readingHistory = try c.decodeIfPresent([PassageAttempt].self, forKey: .readingHistory) ?? []
    }
}
