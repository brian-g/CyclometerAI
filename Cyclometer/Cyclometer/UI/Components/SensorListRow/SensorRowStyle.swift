import SwiftUI

/// The icon and tint a sensor row is drawn with, in one place for both lists.
///
/// The Start sheet (S05.1) shows fixed *role* rows; the Sensors screen (S11) shows
/// discovered *devices*, which advertise a `SensorKind` and may hold no role yet. Those
/// are genuinely different questions, which is why each list asks its own — but a rider
/// who learns that heart rate is red on one screen must find it red on the other, so the
/// answers come from the same table.
///
/// The tints are raw SwiftUI colours rather than `cy` tokens: `assets/design/colors.md`
/// has no sensor-type palette to draw on. Tokenising them needs light and dark hex per
/// sensor added there first.
extension SensorRole {

    var symbolName: String {
        switch self {
        case .radar:     "dot.radiowaves.forward"
        case .heartRate: "heart.fill"
        case .speed:     "speedometer"
        case .cadence:   "dial.medium.fill"
        case .power:     "bolt.fill"
        }
    }

    var tint: Color {
        switch self {
        case .radar:     .purple
        case .heartRate: .red
        case .speed:     .blue
        case .cadence:   .green
        case .power:     .orange
        }
    }
}

extension SensorKind {

    /// The role a kind is drawn as when nothing finer is known.
    ///
    /// `.speedCadence` resolves to `.speed`, the first of the two roles it can fill in
    /// `SensorRole.allCases` order — the same precedence the rest of the app uses. An
    /// undiscovered CSC sensor therefore reads as a speed sensor until it is paired and
    /// its actual role is known, which is the most a single advertised service can say.
    var representativeRole: SensorRole {
        switch self {
        case .radar:        .radar
        case .heartRate:    .heartRate
        case .speedCadence: .speed
        }
    }
}

/// How one row of either sensor list is drawn.
enum SensorRowStyle {

    /// The generic glyph for a device that classifies as nothing. Reachable from a
    /// `.power` record left in the preferences file: `SensorKind(role: .power)` is nil by
    /// design, so such a row carries no kinds at all.
    private static let unknownSymbol = "sensor.tag.radiowaves.forward"

    /// A device row on S11.
    ///
    /// Keyed on the roles the rider has actually assigned, falling back to what the
    /// peripheral advertises while it is merely discovered. A CSC sensor paired as
    /// Cadence therefore shows the green dial here *and* on the Start sheet, rather than
    /// a blue speedometer on one and a green dial on the other.
    ///
    /// Both sets resolve in `allCases` order, so a device serving two profiles reads as
    /// the first — the same precedence its subtitle lists roles in.
    static func device(
        roles: Set<SensorRole>, kinds: Set<SensorKind>
    ) -> (symbol: String, tint: Color) {
        if let role = SensorRole.allCases.first(where: roles.contains) {
            return (role.symbolName, role.tint)
        }
        guard let kind = SensorKind.allCases.first(where: kinds.contains) else {
            return (unknownSymbol, .cyPrimary)
        }
        return (kind.representativeRole.symbolName, kind.representativeRole.tint)
    }
}
