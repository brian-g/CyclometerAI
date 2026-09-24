import ComposableArchitecture
import CoreData
import Foundation
import SwiftData
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "persistence")

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
    /// S15's Stats section (#251). Throws `rideNotFound` for an unknown id, as `fetchRide` does.
    var fetchRideStats: @Sendable (UUID) async throws -> RideStats
    /// Inserts a new Ride record at ride start, denormalizing the route it is being
    /// ridden on (nil for a free ride).
    var createRide: @Sendable (UUID, Date, RouteReference?) async throws -> Void
    /// Writes running aggregates onto an existing Ride — the 30s checkpoint
    /// (DataModel.md §1 Checkpoint Policy). Ride-end goes through `finalizeRide`
    /// instead, which writes the same aggregates in the same atomic call.
    var updateRideSummary: @Sendable (RideSummaryUpdate) async throws -> Void
    /// Writes final aggregates, endedAt, recordingState .ended, and the exported
    /// GPX file's URL (nil if export failed) in one call.
    var finalizeRide: @Sendable (UUID, Date, RideSummaryUpdate, URL?) async throws -> Void
    /// Sets a finished ride's title — S10's rename field (#249).
    var renameRide: @Sendable (UUID, String) async throws -> Void
    /// Stores S14's map thumbnail, light then dark, rendered after the ride ended (#177).
    var saveRideMapThumbnail: @Sendable (UUID, Data, Data) async throws -> Void
    /// Finished rides with no map thumbnail yet, newest first — what `RideMapThumbnail.backfill`
    /// works through: a failed capture, a ride closed out at launch, one recorded before #177.
    var fetchRideIdsMissingMapThumbnail: @Sendable () async throws -> [UUID]
    /// One ride's map thumbnail, both appearances, or nil when it has none yet (#248). Read
    /// per row as S14 shows it rather than with `fetchRides`, so a reload of the list never
    /// pulls every ride's images off disk.
    var fetchRideMapThumbnail: @Sendable (UUID) async throws -> RideMapThumbnailData?
    /// Inserts confirmed vehicle-pass events in one batch — `VehiclePassDetector`
    /// can legitimately confirm more than one on the same tick (#172, DataModel.md §3.4).
    var appendVehiclePassEvents: @Sendable ([VehiclePassEventDTO]) async throws -> Void
    /// Ascending by timestamp, for GPXExporter (#173).
    var fetchVehiclePassEvents: @Sendable (UUID) async throws -> [VehiclePassEventDTO]
    /// Removes everything one ride owns: its CoreData `TrackPoint` rows, its SwiftData
    /// `VehiclePassEvent` rows, its exported GPX file and the `Ride` itself (#261).
    /// Deleting the row alone is what left three orphaned `.gpx` files on a test device.
    var deleteRide: @Sendable (UUID) async throws -> Void
    /// Read path for app-relaunch resume (#175) — the in-progress Ride left behind
    /// by a kill mid-ride, if one exists.
    var fetchResumableRide: @Sendable () async throws -> RideSummaryUpdate?
    /// Every finished ride, newest first — the Rides tab's list (#247).
    var fetchRides: @Sendable () async throws -> [RideListSummary]
    /// Persists a parsed `.gpx` (#191) and hands back the stored summary, whose id the
    /// importing screen needs to select what it just imported.
    var importRoute: @Sendable (ImportedRoute) async throws -> RouteSummary
    /// Every saved route, newest first, without geometry — S19's list and filters.
    var fetchRoutes: @Sendable () async throws -> [RouteSummary]
    /// One route with its polyline and cues, for S20 and ride start. Nil when the id no
    /// longer resolves, which a `Ride.routeId` legitimately may.
    var fetchRoute: @Sendable (UUID) async throws -> RouteDetail?
    /// Removes a route. Past rides keep their `routeId` and `routeName`.
    var deleteRoute: @Sendable (UUID) async throws -> Void
    /// Completed rides ridden on a route, newest first — S20's Previous Rides (#195).
    /// Named for the route, not the rides: at a call site `fetchRides(someId)` would give
    /// no hint that the id has to be a *route* id, and S15's own ride-history read will
    /// want the plain name.
    var fetchRouteRides: @Sendable (UUID) async throws -> [RouteRideSummary]
    /// Stores the OpenStreetMap surface looked up after import (#252).
    var saveRouteSurface: @Sendable (UUID, RouteSurfaceBreakdown) async throws -> Void
    /// Analyses terrain on routes imported before #252; returns how many it filled in.
    var backfillRouteTerrain: @Sendable () async throws -> Int
}

enum PersistenceError: Error, Equatable {
    case batchInsertFailed
    case batchDeleteFailed
    case rideNotFound
}

// MARK: - DependencyKey

extension PersistenceClient: DependencyKey {
    /// Factory with injectable storage, matching BLEHRClient.live(bleClient:), so tests
    /// can drive real NSBatchInsertRequest/NSFetchRequest and SwiftData behavior against
    /// in-memory containers instead of the shared singletons.
    static func live(coreDataContainer: NSPersistentContainer, modelContainer: ModelContainer) -> PersistenceClient {
        let rideActor = RidePersistenceActor(modelContainer: modelContainer)
        let routeActor = RoutePersistenceActor(modelContainer: modelContainer)
        return PersistenceClient(
            flushTrackPoints: { try await batchInsertTrackPoints($0, container: coreDataContainer) },
            fetchTrackPoints: { try await fetchTrackPointsLive(rideId: $0, container: coreDataContainer) },
            fetchRide: { try await rideActor.fetchRideExportMetadata(id: $0) },
            fetchRideStats: { try await rideActor.fetchRideStats(id: $0) },
            createRide: { try await rideActor.createRide(id: $0, startedAt: $1, route: $2) },
            updateRideSummary: { try await rideActor.updateRideSummary($0) },
            finalizeRide: { try await rideActor.finalizeRide(id: $0, endedAt: $1, summary: $2, gpxFileURL: $3) },
            renameRide: { try await rideActor.renameRide(id: $0, title: $1) },
            saveRideMapThumbnail: { try await rideActor.saveMapThumbnail(id: $0, light: $1, dark: $2) },
            fetchRideIdsMissingMapThumbnail: { try await rideActor.rideIdsMissingMapThumbnail() },
            fetchRideMapThumbnail: { try await rideActor.fetchMapThumbnail(id: $0) },
            appendVehiclePassEvents: { try await rideActor.appendVehiclePassEvents($0) },
            fetchVehiclePassEvents: { try await rideActor.fetchVehiclePassEvents(rideId: $0) },
            deleteRide: { try await deleteRideLive(id: $0, rideActor: rideActor, container: coreDataContainer) },
            fetchResumableRide: { try await rideActor.fetchResumableRide() },
            fetchRides: { try await rideActor.fetchRides() },
            importRoute: { try await routeActor.importRoute($0) },
            fetchRoutes: { try await routeActor.fetchRoutes() },
            fetchRoute: { try await routeActor.fetchRoute(id: $0) },
            deleteRoute: { try await routeActor.deleteRoute(id: $0) },
            fetchRouteRides: { try await rideActor.fetchRides(routeId: $0) },
            saveRouteSurface: { try await routeActor.saveRouteSurface(id: $0, surface: $1) },
            backfillRouteTerrain: { try await routeActor.backfillRouteTerrain() }
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
        fetchRideStats: { _ in RideStats(averageSpeedMPS: 0, maxSpeedMPS: 0) },
        createRide: { _, _, _ in },
        updateRideSummary: { _ in },
        finalizeRide: { _, _, _, _ in },
        renameRide: { _, _ in },
        saveRideMapThumbnail: { _, _, _ in },
        fetchRideIdsMissingMapThumbnail: { [] },
        fetchRideMapThumbnail: { _ in nil },
        appendVehiclePassEvents: { _ in },
        fetchVehiclePassEvents: { _ in [] },
        deleteRide: { _ in },
        fetchResumableRide: { nil },
        fetchRides: { [] },
        importRoute: { _ in RouteSummary.empty },
        fetchRoutes: { [] },
        fetchRoute: { _ in nil },
        deleteRoute: { _ in },
        fetchRouteRides: { _ in [] },
        saveRouteSurface: { _, _ in },
        backfillRouteTerrain: { 0 }
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
        // Every optional sensor field stores "no reading" as a negative sentinel, because
        // the attributes are non-optional scalars. It has to be negative, not 0: a
        // coasting rider genuinely reads 0 rpm and a stopped rider 0 m/s, and 0 as the
        // sentinel silently erased those readings on the way back out (#211).
        mo.speedMPS = point.speedMPS ?? -1.0
        mo.speedSourceRaw = point.speedSource.rawValue
        mo.heartRateBPM = Int16(clamping: point.heartRateBPM ?? -1)
        mo.heartRateSourceRaw = point.heartRateSource.rawValue
        mo.cadenceRPM = Int16(clamping: point.cadenceRPM ?? -1)
        mo.powerWatts = Int16(clamping: point.powerWatts ?? -1)
        // Not a sensor reading, so no sentinel: 0 is the first segment (#263).
        mo.segmentIndex = Int16(clamping: point.segmentIndex)
        index += 1
        return false
    })
    request.resultType = .statusOnly
    try await context.perform {
        let result = try context.execute(request) as! NSBatchInsertResult
        guard result.result as? Bool == true else { throw PersistenceError.batchInsertFailed }
    }
}

/// Deletes a ride's file, its time series and its rows, in that order (#261).
///
/// The order is the whole design: the `Ride` row is the only thing that knows where the
/// GPX file is and the only thing any screen can reach the other three from, so it goes
/// last. Interrupted anywhere before that — a crash, a throw — leaves a ride the rider can
/// see and delete again, rather than the unreachable leftovers this issue is about.
///
/// File removal is non-fatal for the same reason: a missing or unreadable file must not
/// strand the rows behind it, and the rider's intent was to be rid of the ride either way.
private func deleteRideLive(
    id: UUID,
    rideActor: RidePersistenceActor,
    container: NSPersistentContainer
) async throws {
    if let fileURL = try await rideActor.gpxFileURL(id: id) {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch CocoaError.fileNoSuchFile {
            // Already gone — the rider may have deleted it from Files themselves.
        } catch {
            logger.error("deleteRide: removing GPX failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    try await batchDeleteTrackPoints(rideId: id, container: container)
    try await rideActor.deleteRide(id: id)
}

/// The CoreData half — a 70-minute ride is roughly 4 200 rows, so this is a batch delete
/// rather than a fetch-and-delete loop, mirroring `batchInsertTrackPoints`.
///
/// Nothing merges the result into `viewContext`, deliberately: no view holds a fetched
/// `TrackPointMO`. Every read of this table goes through `fetchTrackPointsLive`, which
/// starts a fresh background context and so sees the deletion already applied.
private func batchDeleteTrackPoints(rideId: UUID, container: NSPersistentContainer) async throws {
    let context = container.newBackgroundContext()
    try await context.perform {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "TrackPoint")
        fetchRequest.predicate = NSPredicate(format: "rideId == %@", rideId as CVarArg)
        let request = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        request.resultType = .resultTypeStatusOnly
        let result = try context.execute(request) as! NSBatchDeleteResult
        guard result.result as? Bool == true else { throw PersistenceError.batchDeleteFailed }
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
                // Negative is the "no reading" sentinel for every optional sensor
                // field; 0 is a real measurement and round-trips as one (#211).
                speedMPS: mo.speedMPS < 0 ? nil : mo.speedMPS,
                speedSource: SensorSource(rawValue: mo.speedSourceRaw) ?? .none,
                heartRateBPM: mo.heartRateBPM < 0 ? nil : Int(mo.heartRateBPM),
                heartRateSource: SensorSource(rawValue: mo.heartRateSourceRaw) ?? .none,
                cadenceRPM: mo.cadenceRPM < 0 ? nil : Int(mo.cadenceRPM),
                powerWatts: mo.powerWatts < 0 ? nil : Int(mo.powerWatts),
                segmentIndex: Int(mo.segmentIndex)
            )
        }
    }
}
