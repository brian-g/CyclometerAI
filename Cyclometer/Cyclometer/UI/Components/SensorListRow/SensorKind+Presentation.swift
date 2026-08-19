import Foundation

/// How a discovered peripheral's advertised kind is drawn on the Sensors screen (S11).
///
/// Kept out of `Models/SensorKind.swift` so the model stays free of presentation, and
/// next to `SensorListRowView` because that is the only thing that renders it.
extension SensorKind {

    /// The SF Symbol for a row's leading icon.
    ///
    /// Deliberately the same glyphs as `StartSheetFeature.SensorRow.Kind.systemImage`,
    /// duplicated rather than shared: that enum is *role*-shaped (radar, heart rate,
    /// speed, cadence) and this one is *kind*-shaped, because one CSC peripheral serves
    /// two roles and advertises one service. Collapsing the two would mean inventing a
    /// mapping that loses the distinction `SensorKind` exists to make. Keep the strings
    /// in step by hand.
    var symbolName: String {
        switch self {
        case .radar:        "dot.radiowaves.forward"
        case .heartRate:    "heart.fill"
        case .speedCadence: "speedometer"
        }
    }

    /// The icon for a peripheral advertising `kinds`, which for a combo device is more
    /// than one. Resolved by `allCases` order — the same precedence `SensorRole` uses
    /// everywhere else — so a radar that also reports heart rate reads as a radar.
    ///
    /// Falls back to the generic sensor glyph only for the empty set, which a row
    /// synthesised from a `.power` record could reach: `SensorKind(role: .power)` is nil
    /// by design, so a Phase 3 record left in the preferences file classifies as nothing.
    static func symbolName(for kinds: Set<SensorKind>) -> String {
        allCases.first(where: kinds.contains)?.symbolName ?? "sensor.tag.radiowaves.forward"
    }
}
