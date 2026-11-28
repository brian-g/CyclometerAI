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
    /// GPX file's URL (nil if export failed) in one call. The last argument is whether the ride
    /// is owed its Apple Health workout: the rider's remembered Sync To choice (#631), so a kill
    /// before S10 closes follows it. Closing S10 then sets or clears it (`setHealthWorkoutOwed`).
    var finalizeRide: @Sendable (UUID, Date, RideSummaryUpdate, URL?, Bool) async throws -> Void
    /// `finalizeRide` for a ride closed out at launch with no ride-end marker: ended at the
    /// relaunch, no export, and never owed an Apple Health workout (#277), in the same one write.
    /// A finalize and then a settle would leave it owed in between, where S10's closing backfill
    /// could write a workout spanning every hour since the kill (#606).
    var finalizeRideWithoutWorkout: @Sendable (UUID, Date, RideSummaryUpdate) async throws -> Void
    /// Sets a finished ride's title — S10's rename field (#249).
    var renameRide: @Sendable (UUID, String) async throws -> Void
    /// Sets a finished ride's notes — S15's Edit sheet (#538).
    var updateRideNotes: @Sendable (UUID, String) async throws -> Void
    /// Replaces a ride's exported GPX with new contents in place, found by name in
    /// `Documents/Rides/` (#546) — a rename's rewrite (#286). A no-op for a ride with no file,
    /// including one the rider deleted from Files.
    var replaceRideGPX: @Sendable (UUID, Data) async throws -> Void
    /// Stores S14's map thumbnail, light then dark, rendered after the ride ended (#177).
    var saveRideMapThumbnail: @Sendable (UUID, Data, Data) async throws -> Void
    /// Finished rides with no map thumbnail yet, newest first — what `RideMapThumbnail.backfill`
    /// works through: a failed capture, a ride closed out at launch, one recorded before #177.
    var fetchRideIdsMissingMapThumbnail: @Sendable () async throws -> [UUID]
    /// One ride's map thumbnail, both appearances, or nil when it has none yet (#248). Read
    /// per row as S14 shows it rather than with `fetchRides`, so a reload of the list never
    /// pulls every ride's images off disk.
    var fetchRideMapThumbnail: @Sendable (UUID) async throws -> RideMapThumbnailData?
    /// Finished rides whose Apple Health workout hasn't landed yet, newest first — what
    /// `RideHealthWorkout.backfill` works through (#277).
    var fetchRidesOwedHealthWorkout: @Sendable () async throws -> [OwedHealthWorkout]
    /// Marks a ride's workout as done with: written, or skipped as another source's duplicate.
    var settleRideHealthWorkout: @Sendable (UUID) async throws -> Void
    /// Sets or clears a finished ride's Apple Health workout as owed: S10's Sync To row as the
    /// rider left it when the sheet closed (#631).
    var setHealthWorkoutOwed: @Sendable (UUID, Bool) async throws -> Void
    /// Finished rides still owed their finish stats, newest first — what
    /// `RideFinishStats.backfill` works through (#460).
    var fetchRidesOwedFinishStats: @Sendable () async throws -> [OwedFinishStats]
    /// Stores a ride's finish stats worked out from its saved track, and marks it no longer owed.
    var saveRideFinishStats: @Sendable (UUID, RideFinishStats) async throws -> Void
    /// Finished rides' sync records still pending, uploading or processing, oldest ride first:
    /// what `SyncQueueFeature` resumes at launch (#630). A ride whose track isn't on hand is left
    /// out, as for the backfills above: its GPX would be empty.
    var fetchRidesOwedSync: @Sendable () async throws -> [OwedSync]
    /// A ride's record for one service, nil when it was never sent there: what `enqueue` reads so
    /// a ride already on Strava isn't sent again (#630). Throws `rideNotFound` for a deleted ride.
    var fetchSyncRecord: @Sendable (UUID, ExternalService) async throws -> RideSyncRecord?
    /// Writes a ride's record for one service, replacing the one it had (#630). A no-op for a
    /// ride deleted while its upload ran.
    var saveSyncRecord: @Sendable (UUID, RideSyncRecord) async throws -> Void
    /// Removes a ride's record for one service, so it reads as never sent: its activity was
    /// deleted there (#632). A no-op for a ride that's gone.
    var deleteSyncRecord: @Sendable (UUID, ExternalService) async throws -> Void
    /// Finished rides whose Strava upload is under way or failed, newest first: S12.1's Uploads
    /// section (#632).
    var fetchRidesWithStravaWork: @Sendable () async throws -> [StravaWorkItem]
    /// Inserts confirmed vehicle-pass events in one batch — `VehiclePassDetector`
    /// can legitimately confirm more than one on the same tick (#172, DataModel.md §3.4).
    var appendVehiclePassEvents: @Sendable ([VehiclePassEventDTO]) async throws -> Void
    /// Ascending by timestamp, for GPXExporter (#173).
    var fetchVehiclePassEvents: @Sendable (UUID) async throws -> [VehiclePassEventDTO]
    /// Removes everything one ride owns: its CoreData `TrackPoint` rows, its SwiftData
    /// `VehiclePassEvent` rows, its exported GPX file and the `Ride` itself (#261).
    /// Deleting the row alone is what left three orphaned `.gpx` files on a test device.
    var deleteRide: @Sendable (UUID) async throws -> Void
    /// The file name of every ride's GPX export — what the launch sweep keeps (#346).
    var fetchRideGPXFileNames: @Sendable () async throws -> Set<String>
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
    /// One route without its polyline, for S15's link to S20 (#426): opening S20 needs the
    /// summary, and decoding geometry to get it is the cost `RouteSummary` exists to avoid.
    /// Nil when the id no longer resolves, as `fetchRoute`.
    var fetchRouteSummary: @Sendable (UUID) async throws -> RouteSummary?
    /// Removes a route. Past rides keep their `routeId` and `routeName`.
    var deleteRoute: @Sendable (UUID) async throws -> Void
    /// Completed rides ridden on a route, newest first — S20's Previous Rides (#195).
    /// Named for the route, not the rides: at a call site `fetchRides(someId)` would give
    /// no hint that the id has to be a *route* id, and S15's own ride-history read will
    /// want the plain name.
    var fetchRouteRides: @Sendable (UUID) async throws -> [RouteRideSummary]
    /// Stores the OpenStreetMap surface looked up after import (#252).
    var saveRouteSurface: @Sendable (UUID, RouteSurfaceBreakdown) async throws -> Void
    /// Stores S20's on-device narrative, generated after import (#203).
    var saveRouteNarrative: @Sendable (UUID, String) async throws -> Void
    /// Analyses terrain on routes imported before #252; returns how many it filled in.
    var backfillRouteTerrain: @Sendable () async throws -> Int
    /// Stores S19's map thumbnail, light then dark, rendered after import (#273).
    var saveRouteMapThumbnail: @Sendable (UUID, Data, Data) async throws -> Void
    /// Routes with no map thumbnail yet, newest first — what `RouteMapThumbnail.backfill`
    /// works through: a failed capture, or a route imported before #273.
    var fetchRouteIdsMissingMapThumbnail: @Sendable () async throws -> [UUID]
    /// One route's map thumbnail, or nil when it has none yet. Read per row, like
    /// `fetchRideMapThumbnail`, so `fetchRoutes` never pulls every route's images (#273).
    var fetchRouteMapThumbnail: @Sendable (UUID) async throws -> RideMapThumbnailData?
    /// Deletes the Strava data cached on rides and routes (segment efforts, route segments) when
    /// Strava is disconnected (PRD §8.12, DataModel.md §3.8.1). Keeps `Route.stravaRouteID` and
    /// every `RideSyncRecord`.
    var clearStravaCaches: @Sendable () async throws -> Void
    /// Which store, if either, failed to open at launch and is running on a stand-in (#206).
    var storeStatus: @Sendable () -> PersistentStoreStatus
    /// The rider's reset (#206): moves each failed store aside and opens a fresh one where it
    /// was. A no-op when both opened.
    var resetUnavailableStores: @Sendable () async throws -> PersistentStoreReset
}

enum PersistenceError: Error, Equatable {
    case batchInsertFailed
    case batchDeleteFailed
    case rideNotFound
    /// History is on its in-memory stand-in (#206), so it can't say which exports are a ride's.
    case storeUnavailable
}

// MARK: - DependencyKey

extension PersistenceClient: DependencyKey {
    /// Factory with injectable storage, matching BLEHRClient.live(bleClient:), so tests
    /// can drive real NSBatchInsertRequest/NSFetchRequest and SwiftData behavior against
    /// in-memory containers instead of the shared singletons.
    ///
    /// Every call reads the current stores from `stores` once, rather than capturing them
    /// here, so a reset can replace them in place (#206).
    static func live(stores: PersistentStores) -> PersistenceClient {
        PersistenceClient(
            flushTrackPoints: { try await batchInsertTrackPoints($0, container: stores.trackContainer) },
            // Interpolated here, the one read every consumer of a saved track shares, so the map,
            // GPX, Health route and energy all put a poor-GPS second in the same place.
            fetchTrackPoints: {
                TrackPointDTO.interpolatingUntrustedPositions(
                    try await fetchTrackPointsLive(rideId: $0, container: stores.trackContainer)
                )
            },
            fetchRide: { try await stores.rideActor.fetchRideExportMetadata(id: $0) },
            fetchRideStats: { try await stores.rideActor.fetchRideStats(id: $0) },
            createRide: { try await stores.rideActor.createRide(id: $0, startedAt: $1, route: $2) },
            updateRideSummary: { try await stores.rideActor.updateRideSummary($0) },
            finalizeRide: { id, endedAt, summary, gpxFileURL, owesHealthWorkout in
                try stores.retainExportIfHistoryUnavailable(gpxFileURL)
                try await stores.rideActor.finalizeRide(
                    id: id, endedAt: endedAt, summary: summary, gpxFileURL: gpxFileURL, owesHealthWorkout: owesHealthWorkout
                )
            },
            finalizeRideWithoutWorkout: { id, endedAt, summary in
                try await stores.rideActor.finalizeRide(
                    id: id, endedAt: endedAt, summary: summary, gpxFileURL: nil, owesHealthWorkout: false
                )
            },
            renameRide: { try await stores.rideActor.renameRide(id: $0, title: $1) },
            updateRideNotes: { try await stores.rideActor.updateRideNotes(id: $0, notes: $1) },
            replaceRideGPX: { try await stores.rideActor.replaceGPXFile(id: $0, contents: $1) },
            saveRideMapThumbnail: { try await stores.rideActor.saveMapThumbnail(id: $0, light: $1, dark: $2) },
            fetchRideIdsMissingMapThumbnail: { try await stores.rideActor.rideIdsMissingMapThumbnail() },
            fetchRideMapThumbnail: { try await stores.rideActor.fetchMapThumbnail(id: $0) },
            fetchRidesOwedHealthWorkout: {
                try await ridesWithTrackOnHand(try await stores.rideActor.ridesOwedHealthWorkout(), rideId: \.rideId, stores: stores)
            },
            settleRideHealthWorkout: { try await stores.rideActor.settleHealthWorkout(id: $0) },
            setHealthWorkoutOwed: { try await stores.rideActor.setHealthWorkoutOwed(id: $0, owed: $1) },
            fetchRidesOwedFinishStats: {
                try await ridesWithTrackOnHand(try await stores.rideActor.ridesOwedFinishStats(), rideId: \.rideId, stores: stores)
            },
            saveRideFinishStats: { try await stores.rideActor.saveFinishStats(id: $0, stats: $1) },
            fetchRidesOwedSync: {
                try await ridesWithTrackOnHand(try await stores.rideActor.ridesOwedSync(), rideId: \.rideId, stores: stores)
            },
            fetchSyncRecord: { try await stores.rideActor.syncRecord(id: $0, service: $1) },
            saveSyncRecord: { id, record in
                try await stores.rideActor.saveSyncRecord(id: id, record: record)
                if record.service == .strava { publishStravaRecord(record, rideId: id) }
            },
            deleteSyncRecord: { id, service in
                try await stores.rideActor.deleteSyncRecord(id: id, service: service)
                if service == .strava { publishStravaRecord(nil, rideId: id) }
            },
            fetchRidesWithStravaWork: { try await stores.rideActor.ridesWithStravaWork() },
            appendVehiclePassEvents: { try await stores.rideActor.appendVehiclePassEvents($0) },
            fetchVehiclePassEvents: { try await stores.rideActor.fetchVehiclePassEvents(rideId: $0) },
            deleteRide: { try await deleteRideLive(id: $0, rideActor: stores.rideActor, container: stores.trackContainer) },
            fetchRideGPXFileNames: { try await stores.gpxFileNamesToKeep() },
            fetchResumableRide: { try await stores.rideActor.fetchResumableRide() },
            fetchRides: { try await stores.rideActor.fetchRides() },
            importRoute: { try await stores.routeActor.importRoute($0) },
            fetchRoutes: { try await stores.routeActor.fetchRoutes() },
            fetchRoute: { try await stores.routeActor.fetchRoute(id: $0) },
            fetchRouteSummary: { try await stores.routeActor.fetchRouteSummary(id: $0) },
            deleteRoute: { try await stores.routeActor.deleteRoute(id: $0) },
            fetchRouteRides: { try await stores.rideActor.fetchRides(routeId: $0) },
            saveRouteSurface: { try await stores.routeActor.saveRouteSurface(id: $0, surface: $1) },
            saveRouteNarrative: { try await stores.routeActor.saveRouteNarrative(id: $0, narrative: $1) },
            backfillRouteTerrain: { try await stores.routeActor.backfillRouteTerrain() },
            saveRouteMapThumbnail: { try await stores.routeActor.saveMapThumbnail(id: $0, light: $1, dark: $2) },
            fetchRouteIdsMissingMapThumbnail: { try await stores.routeActor.routeIdsMissingMapThumbnail() },
            fetchRouteMapThumbnail: { try await stores.routeActor.fetchMapThumbnail(id: $0) },
            clearStravaCaches: {
                try await stores.rideActor.clearStravaCaches()
                try await stores.routeActor.clearStravaCaches()
            },
            storeStatus: { stores.status },
            resetUnavailableStores: {
                @Dependency(\.date) var date
                return try stores.resetUnavailableStores(now: date.now)
            }
        )
    }

    /// Already-open containers, as the tests build them. No store failed, so there is nothing
    /// to reset.
    static func live(coreDataContainer: NSPersistentContainer, modelContainer: ModelContainer) -> PersistenceClient {
        @Dependency(\.gpxDocumentsDirectory) var documentsDirectory
        return live(stores: PersistentStores(
            history: SwiftDataStack(container: modelContainer),
            tracks: CoreDataStack(container: coreDataContainer),
            supportDirectory: FileManager.default.temporaryDirectory
                .appending(component: "PersistentStores-\(UUID().uuidString)", directoryHint: .isDirectory),
            documentsDirectory: documentsDirectory
        ))
    }

    /// Tells the screens of a Strava record written or deleted (#632), once the store has it.
    private static func publishStravaRecord(_ record: RideSyncRecord?, rideId: UUID) {
        @Shared(.liveStravaSyncRecords) var live
        $live.withLock { $0.set(record, for: rideId) }
    }

    static let liveValue = PersistenceClient.live(stores: PersistentStores(
        history: .shared,
        tracks: .shared,
        supportDirectory: .applicationSupportDirectory,
        documentsDirectory: .documentsDirectory
    ))

    static let testValue = PersistenceClient(
        flushTrackPoints: { _ in },
        fetchTrackPoints: { _ in [] },
        fetchRide: { _ in RideExportMetadata(title: "", startedAt: .init(timeIntervalSince1970: 0)) },
        fetchRideStats: { _ in RideStats(averageSpeedMPS: 0, maxSpeedMPS: 0) },
        createRide: { _, _, _ in },
        updateRideSummary: { _ in },
        finalizeRide: { _, _, _, _, _ in },
        finalizeRideWithoutWorkout: { _, _, _ in },
        renameRide: { _, _ in },
        updateRideNotes: { _, _ in },
        replaceRideGPX: { _, _ in },
        saveRideMapThumbnail: { _, _, _ in },
        fetchRideIdsMissingMapThumbnail: { [] },
        fetchRideMapThumbnail: { _ in nil },
        fetchRidesOwedHealthWorkout: { [] },
        settleRideHealthWorkout: { _ in },
        setHealthWorkoutOwed: { _, _ in },
        fetchRidesOwedFinishStats: { [] },
        saveRideFinishStats: { _, _ in },
        fetchRidesOwedSync: { [] },
        fetchSyncRecord: { _, _ in nil },
        saveSyncRecord: { _, _ in },
        deleteSyncRecord: { _, _ in },
        fetchRidesWithStravaWork: { [] },
        appendVehiclePassEvents: { _ in },
        fetchVehiclePassEvents: { _ in [] },
        deleteRide: { _ in },
        fetchRideGPXFileNames: { [] },
        fetchResumableRide: { nil },
        fetchRides: { [] },
        importRoute: { _ in RouteSummary.empty },
        fetchRoutes: { [] },
        fetchRoute: { _ in nil },
        fetchRouteSummary: { _ in nil },
        deleteRoute: { _ in },
        fetchRouteRides: { _ in [] },
        saveRouteSurface: { _, _ in },
        saveRouteNarrative: { _, _ in },
        backfillRouteTerrain: { 0 },
        saveRouteMapThumbnail: { _, _, _ in },
        fetchRouteIdsMissingMapThumbnail: { [] },
        fetchRouteMapThumbnail: { _ in nil },
        clearStravaCaches: {},
        storeStatus: { .available },
        resetUnavailableStores: { PersistentStoreReset(preservedStores: [], status: .available) }
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
    // Built inside `perform`, on the context's queue: the request isn't Sendable, so it
    // can't be made out here and carried in.
    try await context.perform {
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
            mo.altitudeMeters = point.altitudeMeters.map(NSNumber.init(value:))
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
            mo.isPositionTrusted = point.isPositionTrusted
            index += 1
            return false
        })
        request.resultType = .statusOnly
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
    try await rideActor.removeGPXFile(id: id)
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

/// The owed rides whose track can be read (#206). While tracks are on their stand-in, that is
/// only the rides recorded since launch: every other ride's points are in the store that didn't
/// open. A backfill reading none there would store finish stats and write an Apple Health
/// workout from an empty track, for good. Those rides stay owed until the store opens again or
/// is reset.
private func ridesWithTrackOnHand<Owed: Sendable>(
    _ owed: [Owed],
    rideId: (Owed) -> UUID,
    stores: PersistentStores
) async throws -> [Owed] {
    guard stores.status.tracks != nil else { return owed }
    let container = stores.trackContainer
    var onHand: [Owed] = []
    for ride in owed {
        if try await hasTrackPoints(rideId: rideId(ride), container: container) {
            onHand.append(ride)
        }
    }
    return onHand
}

private func hasTrackPoints(rideId: UUID, container: NSPersistentContainer) async throws -> Bool {
    let context = container.newBackgroundContext()
    return try await context.perform {
        let request = NSFetchRequest<TrackPointMO>(entityName: "TrackPoint")
        request.predicate = NSPredicate(format: "rideId == %@", rideId as CVarArg)
        request.fetchLimit = 1
        return try context.count(for: request) > 0
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
                altitudeMeters: mo.altitudeMeters?.doubleValue,
                horizontalAccuracyMeters: mo.horizontalAccuracyMeters,
                // Negative is the "no reading" sentinel for every optional sensor
                // field; 0 is a real measurement and round-trips as one (#211).
                speedMPS: mo.speedMPS < 0 ? nil : mo.speedMPS,
                speedSource: SensorSource(rawValue: mo.speedSourceRaw) ?? .none,
                heartRateBPM: mo.heartRateBPM < 0 ? nil : Int(mo.heartRateBPM),
                heartRateSource: SensorSource(rawValue: mo.heartRateSourceRaw) ?? .none,
                cadenceRPM: mo.cadenceRPM < 0 ? nil : Int(mo.cadenceRPM),
                powerWatts: mo.powerWatts < 0 ? nil : Int(mo.powerWatts),
                segmentIndex: Int(mo.segmentIndex),
                isPositionTrusted: mo.isPositionTrusted
            )
        }
    }
}
