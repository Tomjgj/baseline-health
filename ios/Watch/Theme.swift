import SwiftUI

/// The app's design rules on the watch: black background, the data colours, rounded numerals, nothing heavier than semibold
/// except the one big number on a screen.
enum Theme {
    static let strain = Color(hex: 0x3B8DEB)
    static let sleep = Color(hex: 0x8F7BF0)
    static let stress = Color(hex: 0xDB6A24)
    static let hrv = Color(hex: 0x1AA394)
    static let heart = Color(hex: 0xE0526E)
    static let water = Color(hex: 0x3AAEE0)
    static let good = Color(hex: 0x2EA866)
    static let warn = Color(hex: 0xE0A82E)
    static let crit = Color(hex: 0xE05252)
    static let card = Color.white.opacity(0.08)

    static func band(_ name: String?) -> Color {
        switch name { case "high": return good; case "mid": return warn; case "low": return crit; default: return .gray }
    }
    static func number(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// A score ring: a faint track, the value as an arc, and an optional target arc outside it.
struct Ring<Label: View>: View {
    var value: Double            // 0...1
    var color: Color
    var lineWidth: CGFloat = 6
    var target: ClosedRange<Double>? = nil
    @ViewBuilder var label: () -> Label

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let t = target {
                Circle().inset(by: -lineWidth * 0.9).trim(from: t.lowerBound, to: t.upperBound)
                    .stroke(Theme.good, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            label()
        }
    }
}

/// A rounded card the way the phone draws them.
struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
