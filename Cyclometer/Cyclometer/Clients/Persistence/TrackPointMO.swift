import CoreData
import Foundation

/// Managed-object mirror of the `TrackPoint` CoreData entity (CyclometerTimeSeries.xcdatamodeld).
/// Codegen is Manual/None — this class is the entity's only source of truth.
@objc(TrackPointMO)
final class TrackPointMO: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var rideId: UUID
    @NSManaged var timestamp: Date
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var altitudeMeters: Double
    @NSManaged var horizontalAccuracyMeters: Double
    @NSManaged var speedMPS: Double
    @NSManaged var speedSourceRaw: String
    @NSManaged var heartRateBPM: Int16
    @NSManaged var heartRateSourceRaw: String
    @NSManaged var cadenceRPM: Int16
    @NSManaged var powerWatts: Int16
}
