import Foundation

/// Spaced repetition: SM-2 adapted for young learners.
///  - short first intervals (hours → 1 day → 3 days): 5–7 year olds forget faster
///  - a miss resets to a re-learn step, with a gentler ease penalty
enum Grade: Int, Codable {
    case missed = 0   // got it wrong
    case hinted = 1   // needed the audio help, or was slow
    case good = 2     // got it
    case easy = 3     // instant
}

enum SRS {
    static let masteredIntervalDays = 21.0
    private static let day: TimeInterval = 86_400

    static func review(_ p: ProgressRecord, grade: Grade, now: Date = Date()) -> ProgressRecord {
        var r = p
        r.lastReviewedAt = now
        r.dirty = true

        if grade == .missed {
            r.lapses += 1
            r.repetitions = 0
            r.ease = max(1.3, r.ease - 0.2)
            r.intervalDays = 0
            r.dueAt = now.addingTimeInterval(10 * 60)
            r.mastered = false
            return r
        }

        let q = Double(grade.rawValue + 2) // SM-2 quality: 3, 4, 5
        r.ease = max(1.3, r.ease + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)))
        r.repetitions += 1
        switch r.repetitions {
        case 1: r.intervalDays = grade == .hinted ? 0.25 : 1
        case 2: r.intervalDays = grade == .hinted ? 1 : 3
        default:
            let mult = grade == .hinted ? 0.8 : (grade == .easy ? 1.15 : 1.0)
            r.intervalDays = (r.intervalDays * r.ease * mult * 10).rounded() / 10
        }
        r.dueAt = now.addingTimeInterval(r.intervalDays * day)
        r.mastered = r.intervalDays >= masteredIntervalDays
        return r
    }
}
