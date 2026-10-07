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

struct ReviewEvent: Codable, Hashable {
    var childID: UUID
    var itemKey: String
    var activity: String
    var grade: Int
    var responseMs: Int
    var heardAudio: Bool
    var aiFeedback: String?
    var date: Date = Date()
}

struct PassageAttempt: Codable, Hashable {
    var childID: UUID
    var passageKey: String
    var wordsTotal: Int
    var wordsCorrect: Int
    var durationSec: Int
    var missedWords: [String]
    var date: Date = Date()
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
}
