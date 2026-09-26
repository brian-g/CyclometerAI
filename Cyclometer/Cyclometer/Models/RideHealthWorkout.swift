import ComposableArchitecture
import Foundation
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "healthkit")

/// The ride's outdoor cycling `HKWorkout` (UX.md §S10, #250), written until it lands (#277).
enum RideHealthWorkout {
    /// Writes the workout of every finished ride still owed one, newest first, and returns how
    /// many it settled.
    ///
    /// The one way workouts get written, whichever way a ride ended, like
    /// `RideMapThumbnail.backfill`. It runs right after a Finish's `finalizeRide`, where the
    /// newest ride is the one just finished. It runs again at launch (unless the launch resumes
    /// a ride) and after AppFeature's close-outs, which catches a ride whose finalize failed
    /// (#188), an app killed before the write, and any write that threw. A ride's workout is
    /// then late rather than never.
    ///
    /// Without Workouts share access it does nothing, not even the reads: every write would
    /// fail. The rides stay owed, so a rider who allows Health later still gets the rides
    /// recorded before they did. Otherwise the first failed write ends the batch, since a
    /// locked store fails every ride the same way.
    ///
    /// One at a time: a Finish can land while the launch backfill is still writing, and both
    /// would write the same rides. The later one waits, then reads the owed list afresh.
    @discardableResult
    static func backfill() async -> Int {
        @Dependency(\.healthWorkoutGate) var gate
        return await gate.run { await backfillNow() }
    }

    private static func backfillNow() async -> Int {
        @Dependency(\.persistenceClient) var persistenceClient
        @Dependency(\.healthKitClient) var healthKitClient
        guard healthKitClient.isWorkoutSharingAllowed() else {
            logger.notice("workout backfill skipped: Workouts share not allowed in Health — owed rides wait")
            return 0
        }
        let owed: [OwedHealthWorkout]
        do {
            owed = try await persistenceClient.fetchRidesOwedHealthWorkout()
        } catch {
            return 0 // Logged inside RidePersistenceActor.
        }
        var settled = 0
        for ride in owed {
            do {
                try await write(ride)
                settled += 1
            } catch {
                logger.error("workout for ride \(ride.rideId, privacy: .public) not written: \(error.localizedDescription, privacy: .public) — retried next launch")
                break
            }
        }
        return settled
    }

    /// Writes one ride's workout, then marks it settled. `HealthKitClient.saveWorkout` returns
    /// normally both when it writes and when it skips another source's duplicate, and either
    /// way the ride is done with. A throw leaves it owed.
    ///
    /// Rewriting a workout that already landed, because the app was killed before the settle,
    /// replaces it rather than adding a second: it carries the ride's sync identifier.
    static func write(_ ride: OwedHealthWorkout) async throws {
        @Dependency(\.persistenceClient) var persistenceClient
        @Dependency(\.healthKitClient) var healthKitClient

        // `saveWorkout` would throw on this every time, and a failure that never clears would
        // hold back every ride queued behind it. A device clock set back mid-ride produces it.
        guard ride.endedAt > ride.startedAt else {
            logger.error("workout for ride \(ride.rideId, privacy: .public) never written: it ends before it starts (device clock changed mid-ride?)")
            try await settle(ride.rideId)
            return
        }

        async let riderKilograms = try? healthKitClient.fetchBodyMass()
        async let dateOfBirth = try? healthKitClient.fetchDateOfBirth()
        async let sex = try? healthKitClient.fetchBiologicalSex()
        // The persisted track, so already filtered of untrustworthy fixes (#210) and of
        // anything recorded while paused. Becomes the workout's route (#295).
        let trackPoints = try await persistenceClient.fetchTrackPoints(ride.rideId)
        // No body mass, no energy (#276): a guessed weight would be written to Health as if
        // it were measured.
        var energy: RideEnergy.Estimate?
        if let kilograms = await riderKilograms {
            let rider = RideEnergy.Rider(
                kilograms: kilograms,
                age: RiderProfile.age(fromDateOfBirth: await dateOfBirth, on: ride.startedAt),
                sex: await sex
            )
            let estimate = RideEnergy.activeKilocalories(
                trackPoints: trackPoints,
                movingSeconds: ride.movingSeconds,
                distanceMeters: ride.distanceMeters,
                rider: rider
            )
            energy = estimate
            logger.notice("energy for ride \(ride.rideId, privacy: .public): \(Int(estimate.kilocalories.rounded()), privacy: .public) kcal from \(estimate.method.rawValue, privacy: .public)")
        }
        // Write failures are logged in the client.
        try await healthKitClient.saveWorkout(RideWorkout(
            rideId: ride.rideId,
            startedAt: ride.startedAt,
            endedAt: ride.endedAt,
            distanceMeters: ride.distanceMeters,
            trackPoints: trackPoints,
            activeEnergyKilocalories: energy?.kilocalories
        ))
        try await settle(ride.rideId)
    }

    /// A ride deleted since the owed list was read has nothing left to owe, so its missing row
    /// is not a failure that should end the batch. Removing its workout from Health is the
    /// deletion's decision, not this one's (#277).
    private static func settle(_ rideId: UUID) async throws {
        @Dependency(\.persistenceClient) var persistenceClient
        do {
            try await persistenceClient.settleRideHealthWorkout(rideId)
        } catch PersistenceError.rideNotFound {
            logger.notice("ride \(rideId, privacy: .public) was deleted during its workout write")
        }
    }
}
