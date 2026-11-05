import ComposableArchitecture
import Foundation
import os

// Stream live: Console.app / Xcode console, filter subsystem "xyz.acmeapps.ride".
private let logger = Logger.cyclometer(.recording)

/// What a ride stores at the finish for S15's Summary (#460): ascent, descent and active energy,
/// kept on the `Ride` so they never change after the fact (UX.md §S15).
///
/// A ride whose live state covered all of it stores the dashboard's own totals through
/// `RideSummaryUpdate.finish`. Every other ride is owed them, and `backfill` works them out from
/// its saved track.
struct RideFinishStats: Sendable, Equatable {
    /// Nil for a ride with no altitude, as both are.
    var ascentMeters: Double?
    var descentMeters: Double?
    /// Nil without a body mass in Health (#276).
    var activeKilocalories: Double?

    /// The live ride's numbers: W14/W15's totals, and the estimate W23 would make now, on the
    /// arguments its minute tick passes.
    init(elevation: ElevationTracker, calorieTrack: [TrackPointDTO], elapsedSeconds: Int,
         distanceMeters: Double, rider: RideEnergy.Rider?) {
        // No altitude at all leaves the range unset; the totals would read 0 m of climbing.
        let hasAltitude = elevation.highestMeters != nil
        ascentMeters = hasAltitude ? elevation.ascentMeters : nil
        descentMeters = hasAltitude ? elevation.descentMeters : nil
        activeKilocalories = rider.map {
            RideEnergy.activeKilocalories(
                trackPoints: calorieTrack, movingSeconds: TimeInterval(elapsedSeconds),
                distanceMeters: distanceMeters, rider: $0
            ).kilocalories
        }
    }

    /// A finished ride's numbers from its saved track, as the Health workout reads it, replayed
    /// through the live elevation rule (`ElevationTracker.Seed`).
    init(savedTrack: [TrackPointDTO], altitudeSource: AltitudeResolver.Source,
         movingSeconds: TimeInterval, distanceMeters: Double, rider: RideEnergy.Rider?) {
        let seed = ElevationTracker.Seed(savedTrack: savedTrack, source: altitudeSource)
        ascentMeters = seed?.ascentMeters
        descentMeters = seed?.descentMeters
        activeKilocalories = rider.map {
            RideEnergy.activeKilocalories(
                trackPoints: savedTrack, movingSeconds: movingSeconds,
                distanceMeters: distanceMeters, rider: $0
            ).kilocalories
        }
    }

    init(ascentMeters: Double?, descentMeters: Double?, activeKilocalories: Double?) {
        self.ascentMeters = ascentMeters
        self.descentMeters = descentMeters
        self.activeKilocalories = activeKilocalories
    }
}

/// A finished ride still owed its finish stats (#460): what they're worked out from, apart from
/// the track, which is read separately.
struct OwedFinishStats: Sendable, Equatable {
    var rideId: UUID
    var startedAt: Date
    var distanceMeters: Double
    /// `Ride.durationSeconds`, which excludes paused time — the energy estimate's moving time.
    var movingSeconds: TimeInterval
}

extension RideFinishStats {
    /// Works out and stores the stats of every finished ride still owed them, newest first, and
    /// returns how many it stored. Runs at launch and after AppFeature's close-outs, like the
    /// workout and thumbnail backfills; a Finish stores the live numbers itself.
    ///
    /// Calories use Health's body mass as it is now: for a ride closed out at launch that is
    /// moments after the ride, and for a ride from before #460 it is the closest there is. Once
    /// stored, a later change of weight no longer reaches the ride.
    ///
    /// The first failed read or write ends the batch and leaves the rest owed, to be tried at the
    /// next launch. Two runs at once (a close-out during the launch run) both store the same
    /// numbers, so they aren't serialised.
    @discardableResult
    static func backfill() async -> Int {
        @Dependency(\.persistenceClient) var persistenceClient
        @Dependency(\.healthKitClient) var healthKitClient
        @Dependency(\.altimeterClient) var altimeterClient
        let owed: [OwedFinishStats]
        do {
            owed = try await persistenceClient.fetchRidesOwedFinishStats()
        } catch {
            return 0 // Logged inside RidePersistenceActor.
        }
        guard !owed.isEmpty else { return 0 }

        async let kilograms = try? healthKitClient.fetchBodyMass()
        async let dateOfBirth = try? healthKitClient.fetchDateOfBirth()
        async let sex = try? healthKitClient.fetchBiologicalSex()
        let (riderKilograms, riderDateOfBirth, riderSex) = await (kilograms, dateOfBirth, sex)
        // As the resume decides (`ActiveRideFeature.seedFromSavedTrack`): the track doesn't record
        // which source each altitude came from, and a phone with a barometer most likely used it.
        let source: AltitudeResolver.Source = altimeterClient.isAvailable() ? .barometric : .gps

        var stored = 0
        for ride in owed {
            do {
                let stats = RideFinishStats(
                    savedTrack: try await persistenceClient.fetchTrackPoints(ride.rideId),
                    altitudeSource: source,
                    movingSeconds: ride.movingSeconds,
                    distanceMeters: ride.distanceMeters,
                    rider: RideEnergy.Rider(
                        kilograms: riderKilograms, dateOfBirth: riderDateOfBirth, sex: riderSex, on: ride.startedAt
                    )
                )
                try await persistenceClient.saveRideFinishStats(ride.rideId, stats)
                stored += 1
            } catch PersistenceError.rideNotFound {
                logger.notice("ride \(ride.rideId, privacy: .public) was deleted during its finish-stats backfill")
            } catch {
                logger.error("finish stats for ride \(ride.rideId, privacy: .public) not stored: \(error.localizedDescription, privacy: .public) — retried next launch")
                break
            }
        }
        return stored
    }
}
