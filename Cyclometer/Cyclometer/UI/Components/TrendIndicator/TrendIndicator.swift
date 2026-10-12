import SwiftUI

/// Which way a value is heading against its widget's own rule: W1's speed against the ride average,
/// W4's last 10 s of heart rate against the 20 s before, W5's cadence against the ride average.
enum Trend: Equatable, Sendable {
    case up, steady, down
}

/// The ▲ (`cyRatingGood`) or ▼ (`cyRatingBad`) shared by W1, W4 and W5 (#402); nothing when
/// steady. A quarter of the digits' height, as in the #81 mock (16 of 63 px). Place it on a hero
/// with `.trendIndicator(_:)` or `HeroNumber.heroTrend(_:)`.
struct TrendIndicator: View {
    let trend: Trend
    /// The digits' height, from `dDINCapAccessory`.
    let capHeight: CGFloat

    private static let heightToCapHeight: CGFloat = 0.25

    var body: some View {
        switch trend {
        case .up:     glyph("arrowtriangle.up.fill").foregroundStyle(Color.cyRatingGood)
        case .down:   glyph("arrowtriangle.down.fill").foregroundStyle(Color.cyRatingBad)
        case .steady: EmptyView()
        }
    }

    // Resizable, so it's tight to the glyph: a text-styled symbol pads above it.
    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .frame(height: capHeight * Self.heightToCapHeight)
    }
}

extension View {
    /// A `TrendIndicator` right of this D-DIN hero text, level with the tops of its digits.
    func trendIndicator(_ trend: Trend) -> some View {
        dDINCapAccessory { TrendIndicator(trend: trend, capHeight: $0) }
    }
}

extension HeroNumber {
    /// A `TrendIndicator` right of the value, level with the tops of its digits.
    func heroTrend(_ trend: Trend) -> Self {
        heroCapAccessory { TrendIndicator(trend: trend, capHeight: $0) }
    }
}

// MARK: - Previews

#Preview("Up / Down / Steady") {
    VStack(alignment: .leading, spacing: Spacing.lg) {
        HeroNumber("32.4", unit: "km/h").heroTrend(.up)
        HeroNumber("156", unit: "bpm").heroNumberSize(.medium).heroTrend(.down)
        HeroNumber("92", unit: "rpm").heroNumberSize(.medium).heroTrend(.steady)
    }
    .padding()
}
