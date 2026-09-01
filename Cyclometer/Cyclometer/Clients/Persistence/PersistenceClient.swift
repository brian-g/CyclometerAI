import ComposableArchitecture
import CoreData
import Foundation
import SwiftData

// MARK: - PersistenceClient

/// TCA dependency for the app's two persistence stacks: CoreData's high-frequency
/// TrackPoint time series, and SwiftData's low-frequency Ride/VehiclePassEvent
/// records (the latter delegated to `RidePersistenceActor`). UserProfile operations
/// are added to this struct by a later M9 issue once that schema exists.
struct PersistenceClient: Sendable {
    /// Batch-insert via NSBatchInsertRequest on a background context (DataModel.md §4.2).
    var flushTrackPoints: @Sendable ([TrackPointDTO]) async throws -> Void
    /// Ascending by timestamp, for GPXExporter and Ride Detail (DataModel.md §7).
    var fetchTrackPoints: @Sendable (UUID) async throws -> [TrackPointDTO]
    /// Ride metadata read path, for GPXExporter (#173) — the rest of this client is
    /// write-only for Ride by design (#171).
    var fetchRide: @Sendable (UUID) async throws -> RideExportMetadata
    /// Inserts a new Ride record at ride start.
    var createRide: @Sendable (UUID, Date) async throws -> Void
    /// Writes running aggregates onto an existing Ride — the 30s checkpoint
    /// (DataModel.md §1 Checkpoint Policy). Ride-end goes through `finalizeRide`
    /// instead, which writes the same aggregates in the same atomic call.
    var updateRideSummary: @Sendable (RideSummaryUpdate) async throws -> Void
    /// Writes final aggregates, endedAt, and recordingState .ended in one call.
    var finalizeRide: @Sendable (UUID, Date, RideSummaryUpdate) async throws -> Void
    /// Inserts confirmed vehicle-pass events in one batch — `VehiclePassDetector`
    /// can legitimately confirm more than one on the same tick (#172, DataModel.md §3.4).
    var appendVehiclePassEvents: @Sendable ([VehiclePassEventDTO]) async throws -> Void
    /// Ascending by timestamp, for GPXExporter (#173).
    var fetchVehiclePassEvents: @Sendable (UUID) async throws -> [VehiclePassEventDTO]
}

enum PersistenceError: Error, Equatable {
    case batchInsertFailed
    case rideNotFound
}

// MARK: - DependencyKey

extension PersistenceClient: DependencyKey {
    /// Factory with injectable storage, matching BLEHRClient.live(bleClient:), so tests
    /// can drive real NSBatchInsertRequest/NSFetchRequest and SwiftData behavior against
    /// in-memory containers instead of the shared singletons.
    static func live(coreDataContainer: NSPersistentContainer, modelContainer: ModelContainer) -> PersistenceClient {
        let rideActor = RidePersistenceActor(modelContainer: modelContainer)
        return PersistenceClient(
            flushTrackPoints: { try await batchInsertTrackPoints($0, container: coreDataContainer) },
            fetchTrackPoints: { try await fetchTrackPointsLive(rideId: $0, container: coreDataContainer) },
            fetchRide: { try await rideActor.fetchRideExportMetadata(id: $0) },
            createRide: { try await rideActor.createRide(id: $0, startedAt: $1) },
            updateRideSummary: { try await rideActor.updateRideSummary($0) },
            finalizeRide: { try await rideActor.finalizeRide(id: $0, endedAt: $1, summary: $2) },
            appendVehiclePassEvents: { try await rideActor.appendVehiclePassEvents($0) },
            fetchVehiclePassEvents: { try await rideActor.fetchVehiclePassEvents(rideId: $0) }
        )
    }

    static let liveValue = PersistenceClient.live(
        coreDataContainer: CoreDataStack.shared.container,
        modelContainer: SwiftDataStack.shared.container
    )

    static let testValue = PersistenceClient(
        flushTrackPoints: { _ in },
        fetchTrackPoints: { _ in [] },
        fetchRide: { _ in RideExportMetadata(title: "", startedAt: .init(timeIntervalSince1970: 0)) },
        createRide: { _, _ in },
        updateRideSummary: { _ in },
        finalizeRide: { _, _, _ in },
        appendVehiclePassEvents: { _ in },
        fetchVehiclePassEvents: { _ in [] }
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
