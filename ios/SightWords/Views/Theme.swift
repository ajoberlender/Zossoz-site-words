import SwiftUI

enum Theme {
    /// A colour that switches between appearances.
    static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    // Surfaces — these adapt to light/dark.
    static let sky = dynamic(light: (0.93, 0.97, 1.0), dark: (0.09, 0.09, 0.17))
    static let skyBottom = dynamic(light: (1, 1, 1), dark: (0.04, 0.04, 0.09))
    /// Cards, tiles and answer buttons.
    static let card = dynamic(light: (1, 1, 1), dark: (0.18, 0.18, 0.29))
    /// Primary text on `card` / `sky`.
    static let ink = dynamic(light: (0.14, 0.12, 0.25), dark: (0.95, 0.94, 1.0))

    // Fills — each is dark/saturated enough for white text (≥ 4.5:1) in both appearances.
    static let grape = Color(red: 0.45, green: 0.30, blue: 0.85)
    static let mint = Color(red: 0.04, green: 0.50, blue: 0.32)
    static let coral = Color(red: 0.76, green: 0.19, blue: 0.19)
    static let slate = Color(red: 0.33, green: 0.31, blue: 0.48)
    /// Bright yellow highlight. Always pair with `onSun`, never with `ink`/white.
    static let sun = Color(red: 1.0, green: 0.80, blue: 0.25)
    static let onSun = Color(red: 0.14, green: 0.12, blue: 0.25)
    static let avatars = ["🦄", "🐼", "🦊", "🐸", "🐙", "🦋", "🐯", "🐰", "🐳", "🦉", "🐢", "🌈"]

}

/// Rounded display font that follows the user's Dynamic Type setting.
private struct BigFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    var weight: Font.Weight
    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .title)
        self.weight = weight
    }
    func body(content: Content) -> some View { content.font(.system(size: size, weight: weight, design: .rounded)) }
}

struct BigButton: View {
    let title: String
    var systemImage: String?
    var color: Color = Theme.grape
    var textColor: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .bigFont(22, weight: .bold)
            .foregroundStyle(textColor)
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
        .accessibilityHint("Reads it aloud")
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
        background(LinearGradient(colors: [Theme.sky, Theme.skyBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    func bigFont(_ size: CGFloat, weight: Font.Weight = .heavy) -> some View {
        modifier(BigFont(size: size, weight: weight))
    }
}

/// Simple "ask a grown-up" gate (multiplication) in front of settings and account actions.
struct GrownUpGate: View {
    var dismissOnPass = true
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
                    if Int(answer) == a * b { onPass(); if dismissOnPass { dismiss() } }
                    else { wrong = true; answer = ""; a = Int.random(in: 6...9); b = Int.random(in: 6...9) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .presentationDetents([.medium])
    }
}
