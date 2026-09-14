import Foundation

/// Which way up the full-screen map sheet draws the world (#199; DataModel.md §3.6, PRD §8.6).
///
/// Governs the sheet only. The W8 widget is always heading-up: it has no controls, so nothing on it can
/// take the rider out of follow (#62), and a glance at the dashboard always reads in the direction of travel.
enum MapOrientation: String, Codable, Sendable {
    /// The map turns so the direction of travel points up. The default.
    case headingUp
    /// North stays at the top while the map follows the rider.
    case northUp

    mutating func toggle() {
        self = self == .headingUp ? .northUp : .headingUp
    }
}
