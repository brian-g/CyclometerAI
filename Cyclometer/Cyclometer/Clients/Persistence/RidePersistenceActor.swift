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
        modelContext.insert(Ride(id: id, startedAt: startedAt))
        do {
            try modelContext.save()
        } catch {
            logger.error("createRide(\(id, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// The 30s checkpoint path — running aggregates only, no endedAt/finalization.
    func updateRideSummary(_ update: RideSummaryUpdate) throws {
        do {
            let ride = try fetchRide(id: update.rideId)
            apply(update, to: ride)
            try modelContext.save()
        } catch {
            logger.error("updateRideSummary(\(update.rideId, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Ride-end: aggregates + endedAt + .ended in one fetch/save. Closing out a ride
    /// is logically one atomic write, not the two independent round trips an earlier
    /// version of this actor required to avoid two contexts racing on the same row.
    func finalizeRide(id: UUID, endedAt: Date, summary: RideSummaryUpdate) throws {
        do {
            let ride = try fetchRide(id: id)
            apply(summary, to: ride)
            ride.endedAt = endedAt
            ride.recordingState = .ended
            try modelContext.save()
        } catch {
            logger.error("finalizeRide(\(id, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            throw error
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
    /// every current caller passes `nil` (vehicle-pass counting is #172's job), and
    /// unconditionally overwriting would silently stomp a real count back to nil the
    /// next time this ride is touched once that lands.
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
}
