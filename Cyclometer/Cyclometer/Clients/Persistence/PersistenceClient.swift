import ComposableArchitecture
import CoreData
import Foundation

// MARK: - PersistenceClient

/// TCA dependency for CoreData's high-frequency TrackPoint time series. SwiftData-backed
/// Ride/VehiclePassEvent/UserProfile operations are added to this struct by later M7/M9
/// issues once those schemas exist (#171, #172) — this is the CoreData half only.
struct PersistenceClient: Sendable {
    /// Batch-insert via NSBatchInsertRequest on a background context (DataModel.md §4.2).
    var flushTrackPoints: @Sendable ([TrackPointDTO]) async throws -> Void
    /// Ascending by timestamp, for GPXExporter and Ride Detail (DataModel.md §7).
    var fetchTrackPoints: @Sendable (UUID) async throws -> [TrackPointDTO]
}

enum PersistenceError: Error {
    case batchInsertFailed
}

// MARK: - DependencyKey

extension PersistenceClient: DependencyKey {
    /// Factory with injectable storage, matching BLEHRClient.live(bleClient:), so tests
    /// can drive real NSBatchInsertRequest/NSFetchRequest behavior against an in-memory
    /// container instead of the shared singleton.
    static func live(container: NSPersistentContainer) -> PersistenceClient {
        PersistenceClient(
            flushTrackPoints: { try await batchInsertTrackPoints($0, container: container) },
            fetchTrackPoints: { try await fetchTrackPointsLive(rideId: $0, container: container) }
        )
    }

    static let liveValue = PersistenceClient.live(container: CoreDataStack.shared.container)

    static let testValue = PersistenceClient(
        flushTrackPoints: { _ in },
        fetchTrackPoints: { _ in [] }
    )
}

extension DependencyValues {
    var persistenceClient: PersistenceClient {
        get { self[PersistenceClient.self] }
        set { self[PersistenceClient.self] = newValue }
    }
}

// MARK: - Live implementation

private func batchInsertTrackPoints(_ points: [TrackPointDTO], container: NSPersistentContainer) async throws {
    let context = container.newBackgroundContext()
    var index = 0
    let request = NSBatchInsertRequest(entityName: "TrackPoint", managedObjectHandler: { managedObject in
        guard index < points.count else { return true }
        let point = points[index]
        let mo = managedObject as! TrackPointMO
        mo.id = point.id
        mo.rideId = point.rideId
        mo.timestamp = point.timestamp
        mo.latitude = point.latitude
        mo.longitude = point.longitude
        mo.altitudeMeters = point.altitudeMeters
        mo.horizontalAccuracyMeters = point.horizontalAccuracyMeters
        mo.speedMPS = point.speedMPS ?? -1.0
        mo.speedSourceRaw = point.speedSource.rawValue
        mo.heartRateBPM = Int16(clamping: point.heartRateBPM ?? 0)
        mo.heartRateSourceRaw = point.heartRateSource.rawValue
        mo.cadenceRPM = Int16(clamping: point.cadenceRPM ?? 0)
        mo.powerWatts = Int16(clamping: point.powerWatts ?? 0)
        index += 1
        return false
    })
    request.resultType = .statusOnly
    try await context.perform {
        let result = try context.execute(request) as! NSBatchInsertResult
        guard result.result as? Bool == true else { throw PersistenceError.batchInsertFailed }
    }
}

private func fetchTrackPointsLive(rideId: UUID, container: NSPersistentContainer) async throws -> [TrackPointDTO] {
    let context = container.newBackgroundContext()
    return try await context.perform {
        let request = NSFetchRequest<TrackPointMO>(entityName: "TrackPoint")
        request.predicate = NSPredicate(format: "rideId == %@", rideId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        request.fetchBatchSize = 500
        return try context.fetch(request).map { mo in
            TrackPointDTO(
                id: mo.id,
                rideId: mo.rideId,
                timestamp: mo.timestamp,
                latitude: mo.latitude,
                longitude: mo.longitude,
                altitudeMeters: mo.altitudeMeters,
                horizontalAccuracyMeters: mo.horizontalAccuracyMeters,
                speedMPS: mo.speedMPS < 0 ? nil : mo.speedMPS,
                speedSource: SensorSource(rawValue: mo.speedSourceRaw) ?? .none,
                heartRateBPM: mo.heartRateBPM == 0 ? nil : Int(mo.heartRateBPM),
                heartRateSource: SensorSource(rawValue: mo.heartRateSourceRaw) ?? .none,
                cadenceRPM: mo.cadenceRPM == 0 ? nil : Int(mo.cadenceRPM),
                powerWatts: mo.powerWatts == 0 ? nil : Int(mo.powerWatts)
            )
        }
    }
}
