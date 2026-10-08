import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device AI via Apple's Foundation Models framework (iOS 26+, Apple Intelligence devices).
/// Nothing is sent to a server. If the model isn't available, every feature falls back to a
/// deterministic, non-AI version so the app is fully usable on any device.
enum AIAvailability: Equatable {
    case available
    case appleIntelligenceOff   // device is eligible; user must enable it in Settings
    case modelDownloading
    case unsupported            // older iOS or ineligible device
}

struct StoryDraft {
    var title: String
    var body: String
    var offListWords: [String]  // words outside what the child has learned (still tappable to hear)
    var usedAI: Bool
}

struct CoachNotes {
    var summary: String
    var tips: [String]
    var usedAI: Bool
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct StoryOutput {
    @Guide(description: "A cheerful title of two to four words")
    var title: String
    @Guide(description: "The story, one very short sentence per item, each at most seven words", .count(6))
    var sentences: [String]
}

@available(iOS 26.0, *)
@Generable
struct CoachOutput {
    @Guide(description: "One warm, encouraging sentence for the parent summarizing the child's progress")
    var summary: String
    @Guide(description: "Specific, practical things a parent can do at home this week", .count(3))
    var tips: [String]
}
#endif

@MainActor
final class AIService: ObservableObject {
    static let shared = AIService()
    @Published private(set) var availability: AIAvailability = .unsupported

    static let themes = ["a cat", "a dog", "a fish", "a ship", "a duck", "a hen", "a pig", "a bus", "the sun", "a hat"]

    init() { refresh() }

    func refresh() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: availability = .available
            case .unavailable(.appleIntelligenceNotEnabled): availability = .appleIntelligenceOff
            case .unavailable(.modelNotReady): availability = .modelDownloading
            default: availability = .unsupported
            }
            return
        }
        #endif
        availability = .unsupported
    }

    // MARK: Story maker

    /// Writes a short decodable story using (mostly) words the child already knows.
    /// `recentlyRead` (passage key → when it was last read) steers the library fallback toward stories not read yet.
    func makeStory(childName: String, known: [String], theme: String, recentlyRead: [String: Date] = [:]) async -> StoryDraft {
        let allowed = Set(known.map { $0.lowercased() } + Curriculum.alwaysAllowed.map { $0.lowercased() }
                          + Self.tokens(childName) + Self.tokens(theme))
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), availability == .available {
            var best: StoryDraft?
            for _ in 0..<3 {
                if let out = try? await generateStory(childName: childName, known: known, theme: theme) {
                    let body = out.sentences.joined(separator: " ")
                    let off = Self.offList(body, allowed: allowed)
                    let draft = StoryDraft(title: out.title, body: body, offListWords: off, usedAI: true)
                    if best == nil || off.count < best!.offListWords.count { best = draft }
                    if off.count <= 1 { break }
                }
            }
            // Accept the best attempt only if it's close enough to what the child can read.
            if let best, best.offListWords.count <= 3 { return best }
        }
        #endif
        return fallbackStory(allowed: allowed, theme: theme, recentlyRead: recentlyRead)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateStory(childName: String, known: [String], theme: String) async throws -> StoryOutput {
        // Keep the prompt small: the context window is shared between input and output.
        // A random sample, so a bigger vocabulary gives different stories (alphabetical would always start at "a").
        let words = Array(Set(known.map { $0.lowercased() })).shuffled().prefix(150).joined(separator: ", ")
        let instructions = """
        You write tiny, cheerful stories for a five-year-old who is just learning to read.
        Use ONLY simple words from the allowed word list, plus the child's name and the words in the theme.
        Every sentence must be very short. DO NOT use any word that is not on the list.
        DO NOT write anything scary, sad, or about danger.
        """
        let prompt = """
        Allowed words: \(words), the, a, is, and, I, can, see, to, we, it, in, on, was
        Child's name: \(childName)
        Theme: \(theme)
        Write a story with a happy ending.
        """
        let session = LanguageModelSession(instructions: instructions)
        let resp = try await session.respond(to: prompt, generating: StoryOutput.self,
                                             options: GenerationOptions(temperature: 0.6))
        return resp.content
    }
    #endif

    /// Picks the built-in passage that best matches what the child can already read.
    /// Among the stories the child can mostly read, prefer one they haven't read (or read longest ago),
    /// then one that mentions the theme, then the one with the fewest unfamiliar words.
    private func fallbackStory(allowed: Set<String>, theme: String, recentlyRead: [String: Date]) -> StoryDraft {
        let scored = Curriculum.passages.map { p -> (Item, [String]) in (p, Self.offList(p.text, allowed: allowed)) }
        let fewest = scored.map { $0.1.count }.min() ?? 0
        let readable = scored.filter { $0.1.count <= max(fewest, 2) }
        let noun = Self.tokens(theme).filter { !["a", "an", "the"].contains($0) }
        func rank(_ s: (Item, [String])) -> (Int, Date, Int, Int) {
            let text = s.0.text.lowercased()
            return (recentlyRead[s.0.key] == nil ? 0 : 1, recentlyRead[s.0.key] ?? .distantPast,
                    noun.contains { text.contains($0) } ? 0 : 1, s.1.count)
        }
        let best = (readable.isEmpty ? scored : readable).min { rank($0) < rank($1) } ?? scored[0]
        return StoryDraft(title: best.0.title ?? "A Story", body: best.0.text, offListWords: best.1, usedAI: false)
    }

    // MARK: Parent coach

    func coachNotes(childName: String, stageTitle: String, masteredCount: Int, streak: Int,
                    trouble: [(word: String, misses: Int)]) async -> CoachNotes {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), availability == .available {
            let instructions = """
            You are a kind, practical early-reading coach speaking to a parent.
            Be encouraging and specific. Suggest short games and routines, never screen time.
            DO NOT give medical or diagnostic advice.
            """
            let tough = trouble.map { "\($0.word) (missed \($0.misses)x)" }.joined(separator: ", ")
            let prompt = """
            Child: \(childName). Current stage: \(stageTitle). Items mastered: \(masteredCount). Practice streak: \(streak) days.
            Words they keep missing: \(tough.isEmpty ? "none yet" : tough).
            """
            let session = LanguageModelSession(instructions: instructions)
            if let r = try? await session.respond(to: prompt, generating: CoachOutput.self,
                                                  options: GenerationOptions(temperature: 0.5)) {
                return CoachNotes(summary: r.content.summary, tips: r.content.tips, usedAI: true)
            }
        }
        #endif
        return fallbackCoach(childName: childName, mastered: masteredCount, streak: streak, trouble: trouble)
    }

    private func fallbackCoach(childName: String, mastered: Int, streak: Int,
                               trouble: [(word: String, misses: Int)]) -> CoachNotes {
        var tips = ["Keep sessions short and happy: 5–10 minutes beats an hour.",
                    "Point to each word as you read together, then let \(childName) point while you read."]
        if let first = trouble.first {
            tips.insert("Write “\(first.word)” on a sticky note and spot it around the house.", at: 0)
        } else {
            tips.insert("Play “I spy” with the letter sounds you’ve practiced.", at: 0)
        }
        let summary = streak > 1
            ? "\(childName) has practiced \(streak) days in a row and has mastered \(mastered) items. Great consistency!"
            : "\(childName) has mastered \(mastered) items so far. A little practice each day adds up quickly."
        return CoachNotes(summary: summary, tips: Array(tips.prefix(3)), usedAI: false)
    }

    // MARK: Helpers

    static func tokens(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init)
    }

    static func offList(_ text: String, allowed: Set<String>) -> [String] {
        var seen = Set<String>()
        return tokens(text).filter { !allowed.contains($0) && seen.insert($0).inserted }
    }
}
