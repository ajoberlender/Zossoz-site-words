import SwiftUI

enum Theme {
    static let sky = Color(red: 0.93, green: 0.97, blue: 1.0)
    static let grape = Color(red: 0.45, green: 0.30, blue: 0.85)
    static let sun = Color(red: 1.0, green: 0.80, blue: 0.25)
    static let mint = Color(red: 0.25, green: 0.78, blue: 0.55)
    static let coral = Color(red: 0.98, green: 0.42, blue: 0.40)
    static let ink = Color(red: 0.14, green: 0.12, blue: 0.25)
    static let avatars = ["🦄", "🐼", "🦊", "🐸", "🐙", "🦋", "🐯", "🐰", "🐳", "🦉", "🐢", "🌈"]

    static func big(_ size: CGFloat = 64) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
}

struct BigButton: View {
    let title: String
    var systemImage: String?
    var color: Color = Theme.grape
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: color.opacity(0.35), radius: 0, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }
}

/// Round speaker button — available everywhere so a child can always "ask for help".
struct SpeakerButton: View {
    var size: CGFloat = 64
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Theme.grape, in: Circle())
                .shadow(color: Theme.grape.opacity(0.35), radius: 0, x: 0, y: 4)
        }
        .accessibilityLabel("Hear it")
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

extension View {
    func screenBackground() -> some View {
        background(LinearGradient(colors: [Theme.sky, .white], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }
}

/// Simple "ask a grown-up" gate (multiplication) in front of settings and account actions.
struct GrownUpGate: View {
    var onPass: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var a = Int.random(in: 6...9)
    @State private var b = Int.random(in: 6...9)
    @State private var answer = ""
    @State private var wrong = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Grown-ups only").font(.title.bold())
            Text("What is \(a) × \(b)?").font(.title2)
            TextField("Answer", text: $answer)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 160)
            if wrong { Text("Not quite. Try again.").foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                Button("Continue") {
                    if Int(answer) == a * b { dismiss(); onPass() }
                    else { wrong = true; answer = ""; a = Int.random(in: 6...9); b = Int.random(in: 6...9) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .presentationDetents([.medium])
    }
}
