import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// #460: a ride's ascent, descent and active energy, stored at the finish or worked out once
/// from its saved track. The owed list is scripted here and shrinks as rides are stored, the way
/// the live actor's does.
@Suite("RideFinishStats")
struct RideFinishStatsTests {
    private struct ReadFailed: Error {}

    private static let start = Date(timeIntervalSince1970: 1_757_155_800)

    private static func owed(_ rideId: UUID = UUID()) -> OwedFinishStats {
        OwedFinishStats(rideId: rideId, startedAt: start, distanceMeters: 840, movingSeconds: 120)
    }

    /// Two minutes up a steady 0.5 m/s climb at 7 m/s with a strap.
    private static func track(_ rideId: UUID, altitude: Bool = true) -> [TrackPointDTO] {
        (0..<120).map { second in
            TrackPointDTO(
                rideId: rideId, timestamp: start.addingTimeInterval(Double(second)),
                latitude: 43.07 + Double(second) * 0.00006, longitude: -89.4,
                altitudeMeters: altitude ? 260 + Double(second) * 0.5 : nil,
                horizontalAccuracyMeters: 5, speedMPS: 7, speedSource: .gps,
                heartRateBPM: 150, heartRateSource: .bleHR
            )
        }
    }

    /// A persistence mock whose owed list loses a ride when its stats are stored.
    private static func persistence(
        _ owed: LockIsolated<[OwedFinishStats]>,
        stored: LockIsolated<[UUID: RideFinishStats]>,
        trackPoints: [UUID: [TrackPointDTO]] = [:]
    ) -> PersistenceClient {
        var client = PersistenceClient.mock(trackPoints: trackPoints)
        client.fetchRidesOwedFinishStats = { owed.value }
        client.saveRideFinishStats = { id, stats in
            stored.withValue { $0[id] = stats }
            owed.withValue { $0.removeAll { $0.rideId == id } }
        }
        return client
    }

    @Test("backfill stores each owed ride's saved-track elevation and energy with Health's rider, once")
    func backfillStoresSavedTrackStats() async throws {
        let ride = Self.owed()
        let track = Self.track(ride.rideId)
        let owed = LockIsolated([ride])
        let stored = LockIsolated<[UUID: RideFinishStats]>([:])
        let dateOfBirth = DateComponents(year: 1980, month: 6, day: 1)

        let first = await withDependencies {
            $0.persistenceClient = Self.persistence(owed, stored: stored, trackPoints: [ride.rideId: track])
            $0.healthKitClient = .mock(dateOfBirth: dateOfBirth, bodyMassKilograms: 75, biologicalSex: .male)
            $0.altimeterClient.isAvailable = { true }
        } operation: {
            await RideFinishStats.backfill()
        }

        #expect(first == 1)
        let seed = try #require(ElevationTracker.Seed(savedTrack: track, source: .barometric))
        let rider = try #require(RideEnergy.Rider(kilograms: 75, dateOfBirth: dateOfBirth, sex: .male, on: Self.start))
        #expect(stored.value[ride.rideId] == RideFinishStats(
            ascentMeters: seed.ascentMeters,
            descentMeters: seed.descentMeters,
            activeKilocalories: RideEnergy.activeKilocalories(
                trackPoints: track, movingSeconds: 120, distanceMeters: 840, rider: rider
            ).kilocalories
        ))

        // Settled: a second run finds nothing owed.
        let second = await withDependencies {
            $0.persistenceClient = Self.persistence(owed, stored: stored, trackPoints: [ride.rideId: track])
            $0.healthKitClient = .mock(bodyMassKilograms: 90)
        } operation: {
            await RideFinishStats.backfill()
        }
        #expect(second == 0)
    }

    @Test("without a body mass the calories are nil, and without altitude so are ascent and descent")
    func backfillStoresNilWithoutData() async {
        let ride = Self.owed()
        let owed = LockIsolated([ride])
        let stored = LockIsolated<[UUID: RideFinishStats]>([:])

        await withDependencies {
            $0.persistenceClient = Self.persistence(
                owed, stored: stored, trackPoints: [ride.rideId: Self.track(ride.rideId, altitude: false)]
            )
            $0.healthKitClient = .mock(bodyMassKilograms: nil)
        } operation: {
            await RideFinishStats.backfill()
        }

        #expect(stored.value[ride.rideId] == RideFinishStats(ascentMeters: nil, descentMeters: nil, activeKilocalories: nil))
        #expect(owed.value.isEmpty)
    }

    @Test("a failed track read ends the batch and leaves the rest owed")
    func failedReadLeavesRidesOwed() async {
        let owed = LockIsolated([Self.owed(), Self.owed()])
        let stored = LockIsolated<[UUID: RideFinishStats]>([:])

        let count = await withDependencies {
            var client = Self.persistence(owed, stored: stored)
            client.fetchTrackPoints = { _ in throw ReadFailed() }
            $0.persistenceClient = client
            $0.healthKitClient = .mock(bodyMassKilograms: 75)
        } operation: {
            await RideFinishStats.backfill()
        }

        #expect(count == 0)
        #expect(owed.value.count == 2)
        #expect(stored.value.isEmpty)
    }

    @Test("a failed body mass read ends the batch and leaves every ride owed, rather than storing no calories")
    func failedBodyMassReadLeavesRidesOwed() async {
        let ride = Self.owed()
        let owed = LockIsolated([ride, Self.owed()])
        let stored = LockIsolated<[UUID: RideFinishStats]>([:])

        let count = await withDependencies {
            $0.persistenceClient = Self.persistence(owed, stored: stored, trackPoints: [ride.rideId: Self.track(ride.rideId)])
            var healthKitClient = HealthKitClient.mock(dateOfBirth: DateComponents(year: 1980, month: 6, day: 1),
                                                       biologicalSex: .male)
            healthKitClient.fetchBodyMass = { throw ReadFailed() }
            $0.healthKitClient = healthKitClient
        } operation: {
            await RideFinishStats.backfill()
        }

        #expect(count == 0)
        #expect(owed.value.count == 2)
        #expect(stored.value.isEmpty)
    }

    /// The acceptance criterion: a finished ride stores the energy its Health workout carries,
    /// given the same rider inputs.
    @Test("the stored active energy equals what the ride's Health workout is written with")
    func storedEnergyMatchesHealthWorkout() async throws {
        let rideId = UUID()
        let track = Self.track(rideId)
        let dateOfBirth = DateComponents(year: 1980, month: 6, day: 1)
        let rider = try #require(RideEnergy.Rider(kilograms: 75, dateOfBirth: dateOfBirth, sex: .male, on: Self.start))
        var tracker = ElevationTracker()
        for (second, point) in track.enumerated() {
            tracker.record(altitude: point.altitudeMeters ?? 0, distanceMeters: Double(second) * 7, source: .barometric)
        }
        let live = RideFinishStats(elevation: tracker, calorieTrack: track, elapsedSeconds: 120,
                                   distanceMeters: 840, rider: rider)

        let written = LockIsolated<RideWorkout?>(nil)
        try await withDependencies {
            $0.persistenceClient = .mock(trackPoints: [rideId: track])
            $0.healthKitClient = .mock(dateOfBirth: dateOfBirth, bodyMassKilograms: 75, biologicalSex: .male,
                                       onSaveWorkout: { written.setValue($0) })
        } operation: {
            try await RideHealthWorkout.write(OwedHealthWorkout(
                rideId: rideId, startedAt: Self.start, endedAt: Self.start.addingTimeInterval(180),
                distanceMeters: 840, movingSeconds: 120
            ))
        }

        #expect(live.activeKilocalories != nil)
        #expect(live.activeKilocalories == written.value?.activeEnergyKilocalories)
    }

    @Test("a later change of Health body weight doesn't move a finished ride's calories")
    func laterWeightChangeKeepsCalories() async throws {
        let (client, _) = PersistenceClientTests.makeLiveClient()
        let rideId = UUID()
        try await client.createRide(rideId, Self.start, nil)
        var summary = RideSummaryUpdate(rideId: rideId, durationSeconds: 120, distanceMeters: 840,
                                        averageSpeedMPS: 7, maxSpeedMPS: 7)
        summary.finish = RideFinishStats(ascentMeters: 60, descentMeters: 0, activeKilocalories: 31)
        try await client.finalizeRide(rideId, Self.start.addingTimeInterval(180), summary, nil)

        await withDependencies {
            $0.persistenceClient = client
            $0.healthKitClient = .mock(bodyMassKilograms: 95)
        } operation: {
            await RideFinishStats.backfill()
        }

        #expect(try await client.fetchRideStats(rideId).activeKilocalories == 31)
    }

    /// The tracker's totals as W14/W15 show them; no altitude at all is no data, not 0 m.
    @Test("the live stats take the tracker's totals, and nil with no altitude")
    func liveStatsFromTracker() {
        var tracker = ElevationTracker()
        tracker.record(altitude: 260, distanceMeters: 0, source: .barometric)
        tracker.record(altitude: 270, distanceMeters: 100, source: .barometric)
        tracker.record(altitude: 262, distanceMeters: 200, source: .barometric)
        let live = RideFinishStats(elevation: tracker, calorieTrack: [], elapsedSeconds: 60,
                                   distanceMeters: 200, rider: nil)
        #expect(live.ascentMeters == tracker.ascentMeters)
        #expect(live.descentMeters == tracker.descentMeters)
        #expect(live.activeKilocalories == nil)

        let none = RideFinishStats(elevation: ElevationTracker(), calorieTrack: [], elapsedSeconds: 60,
                                   distanceMeters: 200, rider: nil)
        #expect(none.ascentMeters == nil)
        #expect(none.descentMeters == nil)
    }
}
