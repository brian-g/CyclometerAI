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
        try savingChanges("createRide", id: id) {
            let ride = Ride(id: id, startedAt: startedAt)
            ride.routeId = route?.id
            ride.routeName = route?.name
            modelContext.insert(ride)
        }
    }

    /// The 30s checkpoint path — running aggregates only, no endedAt/finalization.
    func updateRideSummary(_ update: RideSummaryUpdate) throws {
        try savingChanges("updateRideSummary", id: update.rideId) {
            let ride = try fetchRide(id: update.rideId)
            apply(update, to: ride)
        }
    }

    /// Ride-end: aggregates + endedAt + .ended in one fetch/save. Closing out a ride
    /// is logically one atomic write, not the two independent round trips an earlier
    /// version of this actor required to avoid two contexts racing on the same row.
    func finalizeRide(id: UUID, endedAt: Date, summary: RideSummaryUpdate, gpxFileURL: URL?) throws {
        try savingChanges("finalizeRide", id: id) {
            let ride = try fetchRide(id: id)
            apply(summary, to: ride)
            ride.endedAt = endedAt
            ride.recordingState = .ended
            ride.gpxFileURL = gpxFileURL
        }
    }

    /// Inserts confirmed vehicle-pass events in one batch and one save (#172) —
    /// `VehiclePassDetector` can confirm more than one on the same radar tick.
    /// Plain inserts against the same long-lived context as the Ride writes above;
    /// unlike the checkpoint, this never overwrites an existing row.
    func appendVehiclePassEvents(_ dtos: [VehiclePassEventDTO]) throws {
        guard let firstRideId = dtos.first?.rideId else { return }
        try savingChanges("appendVehiclePassEvents", id: firstRideId) {
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

    /// Read path for `GPXExporter` (#173) — the rest of this actor is write-only by
    /// design (#171), but GPX export needs the ride's title/startedAt for
    /// `<metadata>`/`<trk><name>`.
    func fetchRideExportMetadata(id: UUID) throws -> RideExportMetadata {
        let ride = try fetchRide(id: id)
        return RideExportMetadata(title: ride.title, startedAt: ride.startedAt)
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
            return try modelContext.fetch(descriptor).first?.summarySnapshot
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

    private func fetchRide(id: UUID) throws -> Ride {
        var descriptor = FetchDescriptor<Ride>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let ride = try modelContext.fetch(descriptor).first else {
            throw PersistenceError.rideNotFound
        }
        return ride
    }

    /// Only overwrites `vehiclePassCount` when the caller actually has a value —
    /// `ActiveRideFeature` passes its running count on every checkpoint/finalize
    /// (#172), but unconditionally overwriting would silently stomp a real count
    /// back to nil for any caller that doesn't track one.
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
    }

    /// Shared body for every write above: run `changes` (insert/fetch/mutate, no
    /// save), save the context, and log-then-rethrow under one label on failure.
    /// Replaces four near-identical do/save/catch blocks that differed only in the
    /// log label (code review, #172).
    private func savingChanges(_ label: String, id: UUID, _ changes: () throws -> Void) throws {
        do {
            try changes()
            try modelContext.save()
        } catch {
            logger.error("\(label, privacy: .public)(\(id, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
