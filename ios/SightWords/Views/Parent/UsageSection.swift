import SwiftUI
import Charts

/// Parent-facing usage analytics, computed from the local activity log.
struct UsageSection: View {
    let childID: UUID
    @EnvironmentObject var store: AppStore

    private struct Day: Identifiable { let id: Date; let cards: Int }

    var body: some View {
        let events = store.history(for: childID)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days: [Day] = (0..<14).reversed().map { off in
            let d = cal.date(byAdding: .day, value: -off, to: today)!
            return Day(id: d, cards: events.filter { cal.isDate($0.date, inSameDayAs: d) }.count)
        }
        let week = events.filter { $0.date >= cal.date(byAdding: .day, value: -6, to: today)! }
        let activeDays = Set(week.map { cal.startOfDay(for: $0.date) }).count
        let correct = week.filter { $0.grade >= Grade.good.rawValue }.count
        let accuracy = week.isEmpty ? nil : Int((Double(correct) / Double(week.count) * 100).rounded())
        let avgSec = week.isEmpty ? nil : Double(week.map(\.responseMs).reduce(0, +)) / Double(week.count) / 1000
        let help = week.isEmpty ? nil : Int((Double(week.filter(\.heardAudio).count) / Double(week.count) * 100).rounded())
        let byActivity = Dictionary(grouping: week, by: \.activity).mapValues(\.count).sorted { $0.value > $1.value }

        Section {
            if events.isEmpty {
                Text("No practice recorded yet. Stats appear after the first session.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Chart(days) { BarMark(x: .value("Day", $0.id, unit: .day), y: .value("Cards", $0.cards)).foregroundStyle(Theme.grape) }
                    .frame(height: 120)
                LabeledContent("Practiced this week", value: "\(activeDays) of 7 days")
                LabeledContent("Cards this week", value: "\(week.count)")
                LabeledContent("Cards all time", value: "\(events.count)")
                if let accuracy { LabeledContent("Got it right", value: "\(accuracy)%") }
                if let avgSec { LabeledContent("Avg. time per card", value: String(format: "%.1fs", avgSec)) }
                if let help { LabeledContent("Needed audio help", value: "\(help)%") }
                if let last = events.map(\.date).max() {
                    LabeledContent("Last practiced", value: last.formatted(.relative(presentation: .named)))
                }
                ForEach(byActivity, id: \.key) { a in
                    LabeledContent(a.key.replacingOccurrences(of: "_", with: " ").capitalized, value: "\(a.value)")
                }
            }
        } header: { Text("Usage") } footer: { Text("Last 14 days in the chart; the numbers cover the last 7 days. Tracked on this device from now on.") }
    }
}
