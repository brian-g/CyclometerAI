import Foundation

/// One reading on a widget sheet: its value and unit as a `ReadingColumn` shows them, and how
/// VoiceOver reads it — units and times in words, and "No reading" for "—" (UX.md §Widget Details,
/// #361). A missing reading has no unit, so "—" stands alone (#494).
struct MetricReading: Equatable {
    /// "12.3", "1:40", "—".
    let value: String
    /// "km", "/km", "%"; empty for a time, a name or "—".
    var unit: String = ""
    let spoken: String

    /// Value and unit as one string, "12.3 km", for a place that shows them as text.
    var shown: String { unit.isEmpty ? value : "\(value) \(unit)" }

    static let missing = MetricReading(value: "—", spoken: "No reading")
}
