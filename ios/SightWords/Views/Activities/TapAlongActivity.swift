import SwiftUI

/// Reading practice for sentences and paragraphs. Tap any word to hear it (counts as "needed help");
/// "Read to me" speaks everything with a moving highlight.
struct TapAlongActivity: View {
    var title: String?
    let text: String
    let child: Child
    /// helpedWords (unique, lowercased), totalWords, seconds
    var onFinish: (_ helped: [String], _ total: Int, _ seconds: Int) -> Void

    @ObservedObject private var speech = SpeechService.shared
    @State private var helped: Set<String> = []
    @State private var started = Date()
    @State private var tappedIndex: Int?

    private var words: [(text: String, range: NSRange)] {
        let ns = text as NSString
        let re = try! NSRegularExpression(pattern: "\\S+")
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { (ns.substring(with: $0.range), $0.range) }
    }

    var body: some View {
        VStack(spacing: 20) {
            if let title { Text(title).font(Theme.big(30)).foregroundStyle(Theme.ink) }
            else { Text("Read the sentence").font(.title2.bold()).foregroundStyle(Theme.ink) }
            Text("Tap a word if you need help.").font(.callout).foregroundStyle(.secondary)

            ScrollView {
                FlowLayout(spacing: 6) {
                    ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                        let clean = Self.clean(w.text)
                        Text(w.text)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(highlight(i, clean: clean), in: RoundedRectangle(cornerRadius: 10))
                            .onTapGesture {
                                helped.insert(clean)
                                tappedIndex = i
                                Task { await SpeechService.shared.speak(clean, child: child, rate: 0.35); tappedIndex = nil }
                            }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal)

            HStack(spacing: 14) {
                SpeakerButton(size: 72) {
                    // Reading the whole thing to them counts as help on every word.
                    helped.formUnion(words.map { Self.clean($0.text) })
                    Task { await SpeechService.shared.speak(text, child: child) }
                }
                BigButton(title: "I read it!", systemImage: "checkmark", color: Theme.mint) {
                    SpeechService.shared.stop()
                    let uniqueTotal = Set(words.map { Self.clean($0.text) }).count
                    onFinish(helped.sorted(), uniqueTotal, Int(Date().timeIntervalSince(started)))
                }
            }
            .padding(.horizontal).padding(.bottom, 12)
        }
        .onAppear { started = Date() }
    }

    private func highlight(_ i: Int, clean: String) -> Color {
        if let r = speech.currentRange, NSIntersectionRange(r, words[i].range).length > 0 { return Theme.sun }
        if tappedIndex == i { return Theme.sun.opacity(0.7) }
        if helped.contains(clean) { return Theme.grape.opacity(0.12) }
        return .clear
    }

    static func clean(_ w: String) -> String {
        w.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }
}
