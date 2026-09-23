import ComposableArchitecture
import Foundation
import Testing
import UIKit
@testable import Cyclometer

@MainActor
@Suite("RidesFeature")
struct RidesFeatureTests {

    private static func summary(
        title: String = "River Loop",
        id: UUID = UUID(),
        startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        distanceMeters: Double = 36_050,
        durationSeconds: TimeInterval = 4_712
    ) -> RideListSummary {
        RideListSummary(id: id, title: title, startedAt: startedAt,
                        distanceMeters: distanceMeters, durationSeconds: durationSeconds)
    }

    @Test("task loads the persisted rides into state")
    func taskLoadsRides() async {
        let rides = [Self.summary(title: "River Loop"), Self.summary(title: "Summit Climb")]
        let store = TestStore(initialState: RidesFeature.State()) {
            RidesFeature()
        } withDependencies: {
            $0.persistenceClient = .mock(rides: rides)
        }

        await store.send(.task)
        await store.receive(\.reloadRides)
        await store.receive(\.ridesResponse) {
            $0.hasLoaded = true
            $0.rides = rides
        }
    }

    /// The swipe action's whole job (#261). Deleting is optimistic: the row leaves
    /// state immediately, and persistence is told to let go of everything the ride owns.
    @Test("Deleting a recorded ride removes it from state and asks persistence to delete it")
    func deleteRecordedRideReachesPersistence() async {
        let deleted = LockIsolated<[UUID]>([])
        let ride = Self.summary()
        let store = TestStore(initialState: RidesFeature.State(rides: [ride])) {
            RidesFeature()
        } withDependencies: {
            $0.persistenceClient = .mock(onDeleteRide: { id in deleted.withValue { $0.append(id) } })
        }

        await store.send(.deleteRecordedRide(ride.id)) {
            $0.rides = []
        }

        #expect(deleted.value == [ride.id])
    }

    /// The row is removed optimistically, so a failed write would otherwise leave the
    /// list quietly disagreeing with the store — this re-syncs from it instead.
    @Test("A failed delete re-syncs state from the store rather than trusting the optimistic removal")
    func deleteFailureRecoversState() async {
        let ride = Self.summary()
        let store = TestStore(initialState: RidesFeature.State(rides: [ride])) {
            RidesFeature()
        } withDependencies: {
            var client = PersistenceClient.mock(rides: [ride])
            client.deleteRide = { _ in throw PersistenceError.rideNotFound }
            $0.persistenceClient = client
        }

        await store.send(.deleteRecordedRide(ride.id)) {
            $0.rides = []
        }
        await store.receive(\.deleteFailed)
        await store.receive(\.reloadRides)
        await store.receive(\.ridesResponse) {
            $0.hasLoaded = true
            $0.rides = [ride]
        }
    }

    /// `ActiveRideFeature`'s own finish effect (flush → GPX export → `finalizeRide`) is a
    /// separate effect, unsequenced with this one — the write can easily still be in
    /// flight the instant a ride ends. `rideFinished` polls rather than reading once.
    @Test("rideFinished polls until the ride appears, rather than reading once and possibly missing it")
    func rideFinishedPollsUntilRideAppears() async {
        let testClock = TestClock()
        let ride = Self.summary()
        let callCount = LockIsolated(0)
        let store = TestStore(initialState: RidesFeature.State()) {
            RidesFeature()
        } withDependencies: {
            $0.continuousClock = testClock
            var client = PersistenceClient.mock()
            client.fetchRides = {
                let count = callCount.withValue { $0 += 1; return $0 }
                return count >= 2 ? [ride] : []
            }
            $0.persistenceClient = client
        }

        await store.send(.rideFinished(ride.id))
        await testClock.advance(by: .milliseconds(200))
        await store.receive(\.ridesResponse) {
            $0.hasLoaded = true
            $0.rides = [ride]
        }
        await store.receive(\.captureMapThumbnails)

        #expect(callCount.value == 2)
    }

    /// A write that never lands (or a finalize that genuinely failed) must not poll
    /// forever — the last read wins once the ceiling is reached.
    @Test("rideFinished gives up after its poll ceiling rather than waiting forever")
    func rideFinishedGivesUpAfterCeiling() async {
        let testClock = TestClock()
        let callCount = LockIsolated(0)
        let store = TestStore(initialState: RidesFeature.State()) {
            RidesFeature()
        } withDependencies: {
            $0.continuousClock = testClock
            var client = PersistenceClient.mock()
            client.fetchRides = {
                callCount.withValue { $0 += 1 }
                return []
            }
            $0.persistenceClient = client
        }

        await store.send(.rideFinished(UUID()))
        await testClock.advance(by: .seconds(2))
        await store.receive(\.ridesResponse) {
            $0.hasLoaded = true
        }
        await store.receive(\.captureMapThumbnails)

        #expect(callCount.value == 10)
    }

    // MARK: - Map thumbnail (#248)

    /// Two points with a fix, enough for `RideMapThumbnail` to draw a line.
    private static func track(_ rideId: UUID) -> [TrackPointDTO] {
        [(43.070, -89.400), (43.071, -89.401)].map { latitude, longitude in
            TrackPointDTO(
                rideId: rideId, timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                latitude: latitude, longitude: longitude,
                altitudeMeters: 0, horizontalAccuracyMeters: 5,
                speedSource: .gps, heartRateSource: .none
            )
        }
    }

    /// The row is already on screen with the placeholder when the capture lands, so without a
    /// second read it stays that way until the tab remounts.
    @Test("rideFinished captures the ride's map thumbnail once it lands, then reloads the list")
    func rideFinishedCapturesThumbnailAndReloads() async {
        let ride = Self.summary()
        let captured = LockIsolated(false)
        let store = TestStore(initialState: RidesFeature.State()) {
            RidesFeature()
        } withDependencies: {
            var client = PersistenceClient.mock(trackPoints: [ride.id: Self.track(ride.id)])
            client.fetchRides = {
                captured.value
                    ? [RideListSummary(id: ride.id, title: ride.title, startedAt: ride.startedAt,
                                       distanceMeters: ride.distanceMeters,
                                       durationSeconds: ride.durationSeconds,
                                       mapThumbnailLight: Data([1]), mapThumbnailDark: Data([2]))]
                    : [ride]
            }
            client.fetchRideIdsMissingMapThumbnail = { captured.value ? [] : [ride.id] }
            client.saveRideMapThumbnail = { _, _, _ in captured.setValue(true) }
            $0.persistenceClient = client
            $0.mapSnapshotClient = MapSnapshotClient { _, _, style in Data([style == .dark ? 2 : 1]) }
        }

        await store.send(.rideFinished(ride.id))
        await store.receive(\.ridesResponse) {
            $0.hasLoaded = true
            $0.rides = [ride]
        }
        await store.receive(\.captureMapThumbnails)
        await store.receive(\.reloadRides)
        await store.receive(\.ridesResponse) {
            $0.rides[0].mapThumbnailLight = Data([1])
            $0.rides[0].mapThumbnailDark = Data([2])
        }
    }

    /// A delete cancels `CancelID.reload` so a late read can't resurrect the row. The capture
    /// must not sit under that id: deleting an old ride in the seconds after a Finish would
    /// otherwise throw away the new ride's render and leave it to the next launch.
    @Test("a delete while the thumbnail renders doesn't cancel the render")
    func deleteDuringCaptureKeepsTheCapture() async {
        let ride = Self.summary()
        let older = Self.summary(title: "Older", startedAt: Date(timeIntervalSince1970: 1_600_000_000))
        let captured = LockIsolated(false)
        let (renderStarted, renderStartedContinuation) = AsyncStream<Void>.makeStream()
        let (release, releaseContinuation) = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: RidesFeature.State()) {
            RidesFeature()
        } withDependencies: {
            var client = PersistenceClient.mock(trackPoints: [ride.id: Self.track(ride.id)])
            client.fetchRides = {
                captured.value
                    ? [RideListSummary(id: ride.id, title: ride.title, startedAt: ride.startedAt,
                                       distanceMeters: ride.distanceMeters,
                                       durationSeconds: ride.durationSeconds,
                                       mapThumbnailLight: Data([1]), mapThumbnailDark: Data([2]))]
                    : [ride, older]
            }
            client.fetchRideIdsMissingMapThumbnail = { captured.value ? [] : [ride.id] }
            client.saveRideMapThumbnail = { _, _, _ in captured.setValue(true) }
            $0.persistenceClient = client
            // Holds the first render until the delete has gone through.
            $0.mapSnapshotClient = MapSnapshotClient { _, _, style in
                if style == .light {
                    renderStartedContinuation.yield()
                    for await _ in release { break }
                }
                try Task.checkCancellation()
                return Data([style == .dark ? 2 : 1])
            }
        }

        await store.send(.rideFinished(ride.id))
        await store.receive(\.ridesResponse) {
            $0.hasLoaded = true
            $0.rides = [ride, older]
        }
        await store.receive(\.captureMapThumbnails)
        for await _ in renderStarted { break }

        await store.send(.deleteRecordedRide(older.id)) {
            $0.rides = [ride]
        }
        releaseContinuation.yield()

        await store.receive(\.reloadRides)
        await store.receive(\.ridesResponse) {
            $0.rides[0].mapThumbnailLight = Data([1])
            $0.rides[0].mapThumbnailDark = Data([2])
        }
        #expect(captured.value)
    }

    /// A trainer ride, or one already captured: nothing new to show, so no second read.
    @Test("rideFinished doesn't reload when the backfill stored nothing")
    func rideFinishedSkipsReloadWhenNothingCaptured() async {
        let ride = Self.summary()
        let store = TestStore(initialState: RidesFeature.State()) {
            RidesFeature()
        } withDependencies: {
            $0.persistenceClient = .mock(rides: [ride], rideIdsMissingMapThumbnail: [ride.id])
        }

        await store.send(.rideFinished(ride.id))
        await store.receive(\.ridesResponse) {
            $0.hasLoaded = true
            $0.rides = [ride]
        }
        await store.receive(\.captureMapThumbnails)
        // Exhaustive: a `reloadRides` would fail the test here.
    }
}
