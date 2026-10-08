import SwiftUI

/// Parent-facing stats for read-aloud practice: how much they read on their own, and which words trip them up.
struct ReadingStatsSection: View {
    let childID: UUID
    @EnvironmentObject var store: AppStore

    var body: some View {
        let attempts = store.readingAttempts(for: childID)
        let cal = Calendar.current
        let weekAgo = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date()))!
        let week = attempts.filter { $0.date >= weekAgo }
        let total = week.reduce(0) { $0 + $1.wordsTotal }
        let own = week.reduce(0) { $0 + $1.wordsCorrect }
        let trouble = store.stumbleWords(childID: childID)

        Section {
            if attempts.isEmpty {
                Text("Nothing read aloud yet. Stories and sentences show up here after they're read.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                LabeledContent("Read this week", value: "\(week.count)")
                if total > 0 { LabeledContent("Words read on their own", value: "\(Int((Double(own) / Double(total) * 100).rounded()))%") }
                ForEach(Array(attempts.prefix(5).enumerated()), id: \.offset) { _, a in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.passageTitle(a.passageKey)).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("\(a.wordsCorrect) of \(a.wordsTotal) words on their own · \(Self.clock(a.durationSec)) · \(a.date.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if !trouble.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Words that tripped them up").font(.subheadline.weight(.semibold))
                        FlowLayout(spacing: 6) {
                            ForEach(trouble, id: \.word) { t in
                                Text("\(t.word) ×\(t.count)")
                                    .font(.callout.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Theme.sun.opacity(0.35), in: Capsule())
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: { Text("Reading aloud") } footer: {
            Text("A word counts as tripped up when they needed it read to them or took several tries. Heard on this device only.")
        }
    }

    private static func clock(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
}
