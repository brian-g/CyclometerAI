import Foundation

/// Top-level ride summary stored in SwiftData.
/// High-frequency samples (speed, HR, GPS) stored separately in CoreData.
struct Ride: Identifiable {
    let id: UUID
    var startDate: Date
    var endDate: Date?
    var distanceMetres: Double
    var averageSpeedKPH: Double
    var maxSpeedKPH: Double
    var averageHeartRate: Int
    var maxHeartRate: Int
    var elevationGainMetres: Double
    var radarVehiclePassCount: Int     // GPX cyc: namespace extension (PRD spec)
    var gpxFileURL: URL?
}
