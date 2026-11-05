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
    /// Nil without a body mass in Health (#276). The last point of `calorieSeries` when the
    /// numbers are worked out here.
    var activeKilocalories: Double?
    /// W23's chart for S15 (#536): one point a minute and one on the finish second, nil exactly
    /// when `activeKilocalories` is.
    var calorieSeries: [CaloriePoint]?

    /// The live ride's numbers: W14/W15's totals, and W23's series as the dashboard has it
    /// (`calories`) closed with the estimate W23 would make now, on the arguments its minute tick
    /// passes. A series still empty — a resume whose rebuild hasn't landed — is rebuilt from the
    /// track, as that rebuild would.
    init(elevation: ElevationTracker, calorieTrack: [TrackPointDTO], calories: [CaloriePoint],
         elapsedSeconds: Int, movingSeconds: Int, distanceMeters: Double, rider: RideEnergy.Rider?) {
        // No altitude at all leaves the range unset; the totals would read 0 m of climbing.
        let hasAltitude = elevation.highestMeters != nil
        ascentMeters = hasAltitude ? elevation.ascentMeters : nil
        descentMeters = hasAltitude ? elevation.descentMeters : nil
        calorieSeries = rider.map {
            CalorieSeries.closing(
                calories.isEmpty ? CalorieSeries.rebuild(track: calorieTrack, through: elapsedSeconds, rider: $0) : calories,
                track: calorieTrack, rideSeconds: elapsedSeconds, movingSeconds: movingSeconds,
                distanceMeters: distanceMeters, rider: $0
            )
        }
        activeKilocalories = calorieSeries?.last?.kilocalories
    }

    /// A finished ride's numbers from its saved track, as the Health workout reads it, replayed
    /// through the live elevation rule (`ElevationTracker.Seed`) and W23's rebuild.
    init(savedTrack: [TrackPointDTO], altitudeSource: AltitudeResolver.Source,
         movingSeconds: TimeInterval, distanceMeters: Double, rider: RideEnergy.Rider?) {
        let seed = ElevationTracker.Seed(savedTrack: savedTrack, source: altitudeSource)
        ascentMeters = seed?.ascentMeters
        descentMeters = seed?.descentMeters
        let rideSeconds = Int(movingSeconds)
        // W3's moving seconds, by the odometer rule `CalorieSeries.rebuild` replays.
        let odometerSeconds = savedTrack.count(where: { ($0.speedMPS ?? 0) > ActiveRideFeature.stationarySpeedMPS })
        calorieSeries = rider.map {
            CalorieSeries.closing(
                CalorieSeries.rebuild(track: savedTrack, through: rideSeconds, rider: $0),
                track: savedTrack, rideSeconds: rideSeconds, movingSeconds: odometerSeconds,
                distanceMeters: distanceMeters, rider: $0
            )
        }
        activeKilocalories = calorieSeries?.last?.kilocalories
    }

    init(ascentMeters: Double?, descentMeters: Double?, activeKilocalories: Double?,
         calorieSeries: [CaloriePoint]? = nil) {
        self.ascentMeters = ascentMeters
        self.descentMeters = descentMeters
        self.activeKilocalories = activeKilocalories
        self.calorieSeries = calorieSeries
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
    /// returns how many it stored. Runs at launch, after AppFeature's close-outs and after a
    /// Finish, like the workout backfill; a Finish whose live state covered the whole ride has
    /// already stored the live numbers, so it is not owed.
    ///
    /// Calories use Health's body mass as it is now: for a ride closed out at launch that is
    /// moments after the ride, and for a ride from before #460 it is the closest there is. Once
    /// stored, a later change of weight no longer reaches the ride.
    ///
    /// The first failed read or write ends the batch and leaves the rest owed, to be tried at the
    /// next launch. That includes Health's body mass: a read that throws is not "no body mass",
    /// and storing nil for it would be final. Two runs at once (a close-out or a Finish during the
    /// launch run) both store the same numbers, so they aren't serialised.
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

        async let dateOfBirth = try? healthKitClient.fetchDateOfBirth()
        async let sex = try? healthKitClient.fetchBiologicalSex()
        let riderKilograms: Double?
        do {
            riderKilograms = try await healthKitClient.fetchBodyMass()
        } catch {
            logger.error("finish stats for \(owed.count, privacy: .public) rides not stored: body mass read failed — retried next launch")
            return 0 // The read's own failure is logged inside HealthKitClient.
        }
        let (riderDateOfBirth, riderSex) = await (dateOfBirth, sex)
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
