import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// #277: a ride's Apple Health workout is written until it lands. The owed list is scripted
/// here and shrinks as rides are settled, the way the live actor's does.
@Suite("RideHealthWorkout")
struct RideHealthWorkoutTests {
    private struct WriteFailed: Error {}

    private static let start = Date(timeIntervalSince1970: 1_757_155_800)

    private static func owed(_ rideId: UUID = UUID(), minutes: Double = 30) -> OwedHealthWorkout {
        OwedHealthWorkout(
            rideId: rideId,
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            distanceMeters: 12_000,
            movingSeconds: minutes * 60 - 120
        )
    }

    private static func track(_ rideId: UUID) -> [TrackPointDTO] {
        [0, 1].map {
            TrackPointDTO(
                rideId: rideId, timestamp: start.addingTimeInterval(Double($0)),
                latitude: 43.07 + Double($0) * 0.0001, longitude: -89.4,
                altitudeMeters: 260, horizontalAccuracyMeters: 5,
                speedSource: .gps, heartRateSource: .none
            )
        }
    }

    /// A persistence mock whose owed list loses a ride when it is settled.
    private static func persistence(
        _ owed: LockIsolated<[OwedHealthWorkout]>,
        trackPoints: [UUID: [TrackPointDTO]] = [:]
    ) -> PersistenceClient {
        var client = PersistenceClient.mock(trackPoints: trackPoints)
        client.fetchRidesOwedHealthWorkout = { owed.value }
        client.settleRideHealthWorkout = { id in owed.withValue { $0.removeAll { $0.rideId == id } } }
        return client
    }

    @Test("backfill writes every owed ride in the order given, each from its persisted summary and track, and settles it")
    func backfillWritesEveryOwedRide() async {
        let newest = Self.owed(minutes: 45), oldest = Self.owed(minutes: 20)
        let owed = LockIsolated([newest, oldest])
        let written = LockIsolated<[RideWorkout]>([])
        let tracks = [newest.rideId: Self.track(newest.rideId), oldest.rideId: Self.track(oldest.rideId)]

        let settled = await withDependencies {
            $0.persistenceClient = Self.persistence(owed, trackPoints: tracks)
            $0.healthKitClient = .mock(onSaveWorkout: { workout in written.withValue { $0.append(workout) } })
        } operation: {
            await RideHealthWorkout.backfill()
        }

        #expect(settled == 2)
        #expect(owed.value.isEmpty)
        #expect(written.value == [newest, oldest].map {
            RideWorkout(
                rideId: $0.rideId, startedAt: $0.startedAt, endedAt: $0.endedAt,
                distanceMeters: $0.distanceMeters, trackPoints: tracks[$0.rideId] ?? [],
                // No body mass in the mock, so no energy (#276).
                activeEnergyKilocalories: nil
            )
        })
    }

    @Test("with body mass in Health, the energy is estimated over the ride's moving time, not its span")
    func energyUsesMovingSeconds() async throws {
        let ride = Self.owed()
        let track = Self.track(ride.rideId)
        let written = LockIsolated<[RideWorkout]>([])

        await withDependencies {
            $0.persistenceClient = Self.persistence(LockIsolated([ride]), trackPoints: [ride.rideId: track])
            $0.healthKitClient = .mock(bodyMassKilograms: 75, onSaveWorkout: { workout in written.withValue { $0.append(workout) } })
        } operation: {
            await RideHealthWorkout.backfill()
        }

        let workout = try #require(written.value.first)
        let expected = RideEnergy.activeKilocalories(
            trackPoints: track, movingSeconds: ride.movingSeconds,
            distanceMeters: ride.distanceMeters, rider: RideEnergy.Rider(kilograms: 75)
        )
        let overSpan = RideEnergy.activeKilocalories(
            trackPoints: track, movingSeconds: ride.endedAt.timeIntervalSince(ride.startedAt),
            distanceMeters: ride.distanceMeters, rider: RideEnergy.Rider(kilograms: 75)
        )
        // Distinct, so the comparison below can tell the two apart.
        #expect(expected.kilocalories != overSpan.kilocalories)
        #expect(workout.activeEnergyKilocalories == expected.kilocalories)
    }

    @Test("backfill stops at the first failed write, leaving that ride and the rest owed")
    func backfillStopsAtFirstFailure() async {
        let first = Self.owed(), second = Self.owed()
        let owed = LockIsolated([first, second])
        let attempts = LockIsolated<[UUID]>([])

        let settled = await withDependencies {
            $0.persistenceClient = Self.persistence(owed)
            // What a revoked permission looks like from here: every ride would fail the same way.
            $0.healthKitClient = .mock(onSaveWorkout: { workout in
                attempts.withValue { $0.append(workout.rideId) }
                throw WriteFailed()
            })
        } operation: {
            await RideHealthWorkout.backfill()
        }

        #expect(settled == 0)
        #expect(attempts.value == [first.rideId])
        #expect(owed.value == [first, second])
    }

    /// `saveWorkout` returns normally when it skips a ride another source already recorded
    /// (#250), exactly as when it writes one. Either way the ride is done with.
    @Test("a write that returns, including a skipped duplicate, settles the ride, and the next run doesn't try it again")
    func settledRideIsNotRetried() async {
        let ride = Self.owed()
        let owed = LockIsolated([ride])
        let attempts = LockIsolated(0)

        let runs = await withDependencies {
            $0.persistenceClient = Self.persistence(owed)
            $0.healthKitClient = .mock(onSaveWorkout: { _ in attempts.withValue { $0 += 1 } })
        } operation: {
            (await RideHealthWorkout.backfill(), await RideHealthWorkout.backfill())
        }

        #expect(runs.0 == 1)
        #expect(runs.1 == 0)
        #expect(attempts.value == 1)
        #expect(owed.value.isEmpty)
    }

    @Test("a ride that ends before it starts is settled without a write, and doesn't hold back the rides after it")
    func endsBeforeStartIsSettledUnwritten() async {
        let backwards = Self.owed(minutes: -1)
        let good = Self.owed()
        let owed = LockIsolated([backwards, good])
        let written = LockIsolated<[UUID]>([])

        let settled = await withDependencies {
            $0.persistenceClient = Self.persistence(owed)
            $0.healthKitClient = .mock(onSaveWorkout: { workout in written.withValue { $0.append(workout.rideId) } })
        } operation: {
            await RideHealthWorkout.backfill()
        }

        #expect(written.value == [good.rideId])
        #expect(settled == 2)
        #expect(owed.value.isEmpty)
    }

    /// A Finish's backfill landing while the launch backfill is still writing must not write
    /// the same ride a second time.
    @Test("an overlapping backfill waits for the one running, then finds nothing left to do")
    func overlappingBackfillsRunOneAtATime() async {
        let ride = Self.owed()
        let owed = LockIsolated([ride])
        let reads = LockIsolated(0)
        let writes = LockIsolated(0)
        let (writeStarted, writeStartedContinuation) = AsyncStream<Void>.makeStream()
        let (release, releaseContinuation) = AsyncStream<Void>.makeStream()

        await withDependencies {
            var client = Self.persistence(owed)
            client.fetchRidesOwedHealthWorkout = {
                reads.withValue { $0 += 1 }
                return owed.value
            }
            $0.persistenceClient = client
            // Only the very first write holds, until the second backfill has had its chance.
            $0.healthKitClient = .mock(onSaveWorkout: { _ in
                if writes.withValue({ $0 += 1; return $0 }) == 1 {
                    writeStartedContinuation.yield()
                    for await _ in release { break }
                }
            })
        } operation: {
            async let first = RideHealthWorkout.backfill()
            for await _ in writeStarted { break }
            async let second = RideHealthWorkout.backfill()
            // Real time, not yields, for the reason given on RideMapThumbnailTests' twin of this
            // test: a loaded machine can only make this pass wrongly, never fail wrongly.
            try? await Task.sleep(for: .milliseconds(200))
            #expect(reads.value == 1, "the second backfill started while the first was writing")
            releaseContinuation.yield()
            let settled = await (first, second)
            #expect(settled.0 == 1)
            #expect(settled.1 == 0)
        }
        #expect(writes.value == 1)
    }
}
