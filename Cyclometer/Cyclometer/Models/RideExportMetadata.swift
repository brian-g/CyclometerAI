import Foundation

/// Minimal `Sendable` read of a `Ride`, carrying only the fields `GPXExporter` needs
/// for `<metadata>`/`<trk><name>`, the route that names an untitled ride at ride end (#286), and
/// the notes a Strava upload sends as its description (#630) — not a general-purpose Ride DTO (see
/// `RideSummaryUpdate` for the write side).
struct RideExportMetadata: Sendable, Equatable {
    var title: String
    var startedAt: Date
    var routeName: String? = nil
    var notes: String = ""
}
