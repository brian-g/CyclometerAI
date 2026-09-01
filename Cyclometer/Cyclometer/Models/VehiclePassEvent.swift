import Foundation
import SwiftData

/// A confirmed vehicle overtake, persisted for the post-ride `vehiclePassCount`
/// and (future GPX-export issue) `cyc:` waypoints — DataModel.md §3.4, PRD §8.7.
/// Linked to `Ride` by `rideId` only, matching `TrackPoint`'s CoreData-side FK
/// pattern rather than a SwiftData `@Relationship` (#172).
@Model
final class VehiclePassEvent {
    var id: UUID
    var rideId: UUID
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var alertLevelAtPass: AlertLevel
    var riderSpeedKph: Double
    var estimatedPassSpeedKph: Double?

    init(
        rideId: UUID,
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        alertLevelAtPass: AlertLevel,
        riderSpeedKph: Double,
        estimatedPassSpeedKph: Double?
    ) {
        self.id = UUID()
        self.rideId = rideId
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.alertLevelAtPass = alertLevelAtPass
        self.riderSpeedKph = riderSpeedKph
        self.estimatedPassSpeedKph = estimatedPassSpeedKph
    }
}

/// `VehiclePassEvent`'s boundary DTO — `@Model` classes aren't `Sendable`, so this
/// is what actually crosses `PersistenceClient`'s `@Sendable` closures, mirroring
/// `TrackPointDTO`'s relationship to its CoreData `TrackPointMO`.
struct VehiclePassEventDTO: Sendable, Equatable {
    var rideId: UUID
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var alertLevelAtPass: AlertLevel
    var riderSpeedKph: Double
    var estimatedPassSpeedKph: Double?
}
