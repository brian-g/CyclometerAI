import Foundation
import SwiftData
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "persistence")

/// Serializes every SwiftData Ride write behind one long-lived ModelContext, rather
/// than standing up a fresh context per call — the checkpoint path alone fires at
/// least once per 30 elapsed seconds for the entire duration of every ride, and
/// `ModelContext` isn't safe to share across concurrent callers without one.
@ModelActor
actor RidePersistenceActor {
    /// Takes the whole `RouteReference` rather than a bare id so `routeId` and the
    /// denormalized `routeName` are written together and can never disagree — and so this
    /// actor never has to read the `Route` table, which is what keeps it and
    /// `RoutePersistenceActor` on disjoint tables (#191).
    func createRide(id: UUID, startedAt: Date, route: RouteReference?) throws {
        try savingChanges("createRide", id: id, context: modelContext) {
            let ride = Ride(id: id, startedAt: startedAt)
            ride.routeId = route?.id
            ride.routeName = route?.name
            modelContext.insert(ride)
        }
    }

    /// The 30s checkpoint path — running aggregates only, no endedAt/finalization.
    func updateRideSummary(_ update: RideSummaryUpdate) throws {
        try savingChanges("updateRideSummary", id: update.rideId, context: modelContext) {
            let ride = try fetchRide(id: update.rideId)
            apply(update, to: ride)
        }
    }

    /// Ride-end: aggregates + endedAt + .ended in one fetch/save. Closing out a ride
    /// is logically one atomic write, not the two independent round trips an earlier
    /// version of this actor required to avoid two contexts racing on the same row.
    func finalizeRide(id: UUID, endedAt: Date, summary: RideSummaryUpdate, gpxFileURL: URL?) throws {
        try savingChanges("finalizeRide", id: id, context: modelContext) {
            let ride = try fetchRide(id: id)
            apply(summary, to: ride)
            ride.endedAt = endedAt
            ride.recordingState = .ended
            ride.gpxFileURL = gpxFileURL
        }
    }

    /// S10's rename field (#249). The only write the rider makes to a finished ride.
    func renameRide(id: UUID, title: String) throws {
        try savingChanges("renameRide", id: id, context: modelContext) {
            try fetchRide(id: id).title = title
        }
    }

    /// S14's map thumbnail, both appearances in one save (#177). A write of its own rather
    /// than part of `finalizeRide`: rendering needs map tiles from the network, and the ride
    /// must not wait on them to be durably over.
    func saveMapThumbnail(id: UUID, light: Data, dark: Data) throws {
        try savingChanges("saveMapThumbnail", id: id, context: modelContext) {
            let ride = try fetchRide(id: id)
            ride.mapThumbnailLight = light
            ride.mapThumbnailDark = dark
        }
    }

    /// Finished rides still without a map thumbnail, newest first (#177). Filters on
    /// `endedAt != nil` for the enum-predicate reason given on `fetchResumableRide`.
    func rideIdsMissingMapThumbnail() throws -> [UUID] {
        do {
            let descriptor = FetchDescriptor<Ride>(
                predicate: #Predicate { $0.endedAt != nil && $0.mapThumbnailLight == nil },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor).map(\.id)
        } catch {
            logger.error("rideIdsMissingMapThumbnail failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// One ride's stored thumbnail (#248). Nil for a ride without one, and for an unknown
    /// id: a row can outlive its ride by the moment a delete takes, and a missing image is
    /// what the row already shows then.
    func fetchMapThumbnail(id: UUID) throws -> RideMapThumbnailData? {
        do {
            var descriptor = FetchDescriptor<Ride>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let ride = try modelContext.fetch(descriptor).first,
                  let light = ride.mapThumbnailLight, let dark = ride.mapThumbnailDark
            else { return nil }
            return RideMapThumbnailData(light: light, dark: dark)
        } catch {
            logger.error("fetchMapThumbnail(\(id, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Inserts confirmed vehicle-pass events in one batch and one save (#172) —
    /// `VehiclePassDetector` can confirm more than one on the same radar tick.
    /// Plain inserts against the same long-lived context as the Ride writes above;
    /// unlike the checkpoint, this never overwrites an existing row.
    func appendVehiclePassEvents(_ dtos: [VehiclePassEventDTO]) throws {
        guard let firstRideId = dtos.first?.rideId else { return }
        try savingChanges("appendVehiclePassEvents", id: firstRideId, context: modelContext) {
            for dto in dtos {
                modelContext.insert(VehiclePassEvent(
                    rideId: dto.rideId,
                    timestamp: dto.timestamp,
                    latitude: dto.latitude,
                    longitude: dto.longitude,
                    alertLevelAtPass: dto.alertLevelAtPass,
                    riderSpeedKph: dto.riderSpeedKph,
                    estimatedPassSpeedKph: dto.estimatedPassSpeedKph
                ))
            }
        }
    }

    /// Deletes this ride's exported file, if it has one (#261). A no-op for a ride whose export
    /// failed, one that was never finalized, and one already gone: a delete can race its own list
    /// refresh, and a ride that no longer exists owns no file.
    ///
    /// Called before `deleteRide` below, not from it, so the row stays alive until everything it
    /// owns is gone. See `PersistenceClient.live`'s `deleteRide` for why that ordering is the
    /// point. On this actor, not beside it, so it can't interleave with `replaceGPXFile`.
    func removeGPXFile(id: UUID) throws {
        guard let fileURL = try rideRow(id: id)?.gpxFileURL else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch CocoaError.fileNoSuchFile {
            // Already gone — the rider may have deleted it from Files themselves.
        } catch {
            logger.error("removeGPXFile(\(id, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Replaces this ride's exported file in place, at the URL it already has (#286). A no-op
    /// when there is nothing to replace: no row, no export, or a file the rider deleted from
    /// Files, which a rename shouldn't bring back.
    ///
    /// Checked and written in one synchronous step on this actor, so a delete can't remove the
    /// file between the check and the write — an atomic write creates a missing file, and that
    /// would leave the orphan #261 removed. `.atomic` writes a temporary file and swaps it in,
    /// so a failed write leaves the previous file untouched.
    func replaceGPXFile(id: UUID, contents: Data) throws {
        guard let fileURL = try rideRow(id: id)?.gpxFileURL,
              FileManager.default.fileExists(atPath: fileURL.path)
        else { return }
        do {
            try contents.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("replaceGPXFile(\(id, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Removes a ride and the `VehiclePassEvent` rows keyed to it, in one save (#261).
    /// The CoreData `TrackPoint` rows are the caller's to delete — they live in the other
    /// stack — as is the GPX file.
    ///
    /// No-op when the ride is already gone, mirroring `deleteRoute`: deleting something
    /// twice is not a failure, and the swipe action can race its own list refresh.
    func deleteRide(id: UUID) throws {
        guard let ride = try rideRow(id: id) else { return }
        try savingChanges("deleteRide", id: id, context: modelContext) {
            // No `@Relationship` to cascade down (see `Ride`'s Relationships section):
            // these rows are keyed by a plain `rideId`, so deleting them is this method's
            // own job. Missing it is what left the events of every deleted ride behind.
            let events = try modelContext.fetch(
                FetchDescriptor<VehiclePassEvent>(predicate: #Predicate { $0.rideId == id })
            )
            for event in events { modelContext.delete(event) }
            modelContext.delete(ride)
        }
    }

    /// Read path for `GPXExporter` (#173) — the rest of this actor is write-only by
    /// design (#171), but GPX export needs the ride's title/startedAt for
    /// `<metadata>`/`<trk><name>`.
    func fetchRideExportMetadata(id: UUID) throws -> RideExportMetadata {
        let ride = try fetchRide(id: id)
        return RideExportMetadata(title: ride.title, startedAt: ride.startedAt, routeName: ride.routeName)
    }

    /// Read path for S15's Stats section (#251).
    func fetchRideStats(id: UUID) throws -> RideStats {
        let ride = try fetchRide(id: id)
        return RideStats(
            averageSpeedMPS: ride.averageSpeedMPS,
            maxSpeedMPS: ride.maxSpeedMPS,
            averageCadenceRPM: ride.averageCadenceRPM,
            maxCadenceRPM: ride.maxCadenceRPM,
            vehiclePassCount: ride.vehiclePassCount,
            routeName: ride.routeName
        )
    }

    /// Read path for app-relaunch resume (#175). Ordinarily at most one non-ended
    /// Ride exists at a time, so `fetchLimit = 1` alone would suffice — the
    /// `startedAt` descending sort is a deliberate second line of defense against
    /// the one known way that invariant can transiently break: `AppFeature`
    /// starting a brand-new ride while this fetch is still in flight leaves two
    /// non-ended rows until the orphaned one is closed out (`AppFeature.swift`'s
    /// `resumableRideFetched` handler). Picking the most recent by `startedAt`
    /// is what makes this method itself still return the *newer* ride rather
    /// than an arbitrary one for the brief window that can occur in.
    /// Filters on `endedAt == nil` rather than `recordingState != .ended`: SwiftData's
    /// #Predicate can't compare a RawRepresentable-backed enum property (same fault
    /// AppView.swift works around) — but every write path here only ever sets
    /// `.ended` in the same call that sets `endedAt` (finalizeRide), so the two
    /// fields are always in lockstep and `endedAt == nil` is an exact, enum-free proxy.
    func fetchResumableRide() throws -> RideSummaryUpdate? {
        do {
            var descriptor = FetchDescriptor<Ride>(
                predicate: #Predicate { $0.endedAt == nil },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            guard let ride = try modelContext.fetch(descriptor).first else { return nil }
            var summary = ride.summarySnapshot
            // A pass's `VehiclePassEvent` is saved the moment it's confirmed, but the ride's
            // count only at the next checkpoint, so a kill in between leaves the stored count
            // behind its events (#298). The events are the record; resume from whichever is
            // higher, keeping nil for a ride with neither — "no radar" (#285).
            let rideId = ride.id
            let eventCount = try modelContext.fetchCount(
                FetchDescriptor<VehiclePassEvent>(predicate: #Predicate { $0.rideId == rideId })
            )
            if summary.vehiclePassCount != nil || eventCount > 0 {
                summary.vehiclePassCount = max(summary.vehiclePassCount ?? 0, eventCount)
            }
            return summary
        } catch {
            logger.error("fetchResumableRide failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Read path for S20's Previous Rides (#195) — completed rides that were ridden on
    /// this route, newest first.
    ///
    /// Filters on `endedAt != nil` rather than `recordingState == .ended` for the reason
    /// spelled out on `fetchResumableRide` above: a `#Predicate` comparing a
    /// RawRepresentable-backed enum property against a captured value compiles and then
    /// faults at fetch time. The two fields move in lockstep, so this is an exact,
    /// enum-free proxy for "finished".
    ///
    /// A route that has since been deleted still matches its past rides here — the id is
    /// left dangling deliberately (#191) — but nothing asks for a deleted route's id, so
    /// that costs nothing.
    func fetchRides(routeId: UUID) throws -> [RouteRideSummary] {
        do {
            let descriptor = FetchDescriptor<Ride>(
                predicate: #Predicate { $0.routeId == routeId && $0.endedAt != nil },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor).map {
                RouteRideSummary(
                    rideId: $0.id,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt,
                    durationSeconds: $0.durationSeconds,
                    distanceMeters: $0.distanceMeters
                )
            }
        } catch {
            logger.error("fetchRides(route) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Read path for the Rides tab (#247) — every finished ride, newest first.
    ///
    /// Filters on `endedAt != nil` rather than `recordingState == .ended` for the same
    /// SwiftData `#Predicate`-on-enum limitation documented on `fetchResumableRide` and
    /// `fetchRides(routeId:)` above.
    func fetchRides() throws -> [RideListSummary] {
        do {
            let descriptor = FetchDescriptor<Ride>(
                predicate: #Predicate { $0.endedAt != nil },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor).map {
                RideListSummary(
                    id: $0.id,
                    title: $0.title,
                    startedAt: $0.startedAt,
                    distanceMeters: $0.distanceMeters,
                    durationSeconds: $0.durationSeconds
                )
            }
        } catch {
            logger.error("fetchRides failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Read path for `GPXExporter` (#173) — one `<wpt>` per event, oldest first.
    func fetchVehiclePassEvents(rideId: UUID) throws -> [VehiclePassEventDTO] {
        let descriptor = FetchDescriptor<VehiclePassEvent>(
            predicate: #Predicate { $0.rideId == rideId },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try modelContext.fetch(descriptor).map {
            VehiclePassEventDTO(
                rideId: $0.rideId,
                timestamp: $0.timestamp,
                latitude: $0.latitude,
                longitude: $0.longitude,
                alertLevelAtPass: $0.alertLevelAtPass,
                riderSpeedKph: $0.riderSpeedKph,
                estimatedPassSpeedKph: $0.estimatedPassSpeedKph
            )
        }
    }

    /// The row itself for the callers that need the object rather than a DTO, and nil
    /// rather than a throw when it is missing — named apart from `fetchRide(id:)` for the
    /// same reason `RoutePersistenceActor.routeRow` is.
    private func rideRow(id: UUID) throws -> Ride? {
        var descriptor = FetchDescriptor<Ride>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchRide(id: UUID) throws -> Ride {
        var descriptor = FetchDescriptor<Ride>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let ride = try modelContext.fetch(descriptor).first else {
            throw PersistenceError.rideNotFound
        }
        return ride
    }

    /// Only overwrites `vehiclePassCount` when the update carries a value. Nil from
    /// `ActiveRideFeature` means no radar has been active this ride (#285), and its
    /// count never goes from a number back to nil, so skipping nil can't hide a
    /// clear — it only keeps a checkpoint from stomping a stored count (#172).
    private func apply(_ update: RideSummaryUpdate, to ride: Ride) {
        ride.recordingState = update.recordingState
        ride.durationSeconds = update.durationSeconds
        ride.distanceMeters = update.distanceMeters
        ride.averageSpeedMPS = update.averageSpeedMPS
        ride.maxSpeedMPS = update.maxSpeedMPS
        ride.averageHeartRateBPM = update.averageHeartRateBPM
        ride.maxHeartRateBPM = update.maxHeartRateBPM
        ride.averageCadenceRPM = update.averageCadenceRPM
        ride.maxCadenceRPM = update.maxCadenceRPM
        if let vehiclePassCount = update.vehiclePassCount {
            ride.vehiclePassCount = vehiclePassCount
        }
        ride.isAutoPaused = update.isAutoPaused
        ride.zeroSpeedSeconds = update.zeroSpeedSeconds
        ride.speedSampleCount = update.speedSampleCount
        ride.hrSampleCount = update.hrSampleCount
        ride.cadenceSampleCount = update.cadenceSampleCount
        ride.trackSegmentIndex = update.trackSegmentIndex
        // `update.route` is deliberately not written: the route is `createRide`'s alone.
        ride.routeProgressMeters = update.routeProgressMeters
    }
}
