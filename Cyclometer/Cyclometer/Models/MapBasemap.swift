import Foundation

/// The base map S15's full-screen map draws on (#537). Picked in the sheet's options and
/// remembered, so every ride's map opens on the rider's last choice, after a relaunch too.
///
/// Two choices: MapKit's hybrid style is offered as Satellite, since its road and place labels
/// are what a rider reads a route by. Plain imagery isn't offered.
enum MapBasemap: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard, hybrid

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .hybrid: "Satellite"
        }
    }
}
