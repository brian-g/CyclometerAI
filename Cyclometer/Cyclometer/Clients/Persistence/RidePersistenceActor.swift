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
    func createRide(id: UUID, startedAt: Date) throws {
        try savingChanges("createRide", id: id) {
            modelContext.insert(Ride(id: id, startedAt: startedAt))
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
