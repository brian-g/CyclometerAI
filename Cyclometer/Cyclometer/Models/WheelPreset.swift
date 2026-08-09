import Foundation

/// Common tyre sizes and their rollout circumferences (PRD §8.9).
///
/// The raw value *is* the circumference in millimetres. Every value in the spec
/// table is distinct, so `WheelPreset(rawValue:)` doubles as the "is this stored
/// circumference one of the presets, or a custom/auto-calibrated value?" test.
enum WheelPreset: Int, CaseIterable, Identifiable, Sendable {
    case c700x23  = 2096
    case c700x25  = 2105
    case c700x28  = 2136
    case c700x32  = 2155
    case c700x35  = 2168
    case b650x47  = 2144
    case mtb29x21 = 2288
    case mtb26x20 = 2051

    /// Matches `BLECSCClient`'s built-in default, so an unconfigured rider sees
    /// no change in behaviour.
    static let `default` = WheelPreset.c700x23

    /// Sanity bounds for manual entry (PRD §8.9). Anything outside is rejected.
    static let validRange = 1500...3000

    var circumferenceMM: Int { rawValue }
    var id: Int { rawValue }

    /// As printed on the tire sidewall — road widths carry the French "c" suffix,
    /// MTB sizes are plain inches. The circumference is deliberately not part of
    /// the label; riders pick by tire size, and the millimetre value is only shown
    /// when Custom is selected.
    var label: String {
        switch self {
        case .c700x23:  return "700 x 23c"
        case .c700x25:  return "700 x 25c"
        case .c700x28:  return "700 x 28c"
        case .c700x32:  return "700 x 32c"
        case .c700x35:  return "700 x 35c"
        case .b650x47:  return "650b x 47"
        case .mtb29x21: return "29 x 2.1"
        case .mtb26x20: return "26 x 2.0"
        }
    }
}
