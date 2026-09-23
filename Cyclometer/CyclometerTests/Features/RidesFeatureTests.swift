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

    /// S15 is reducer state on the tab's stack (#251), not a view-built destination — so the
    /// ride a row pushed is the one whose data the detail reads.
    @Test("Tapping a ride pushes its detail onto the stack, which loads that ride's data")
    func tappingARidePushesItsDetail() async {
        let ride = Self.summary()
        let stats = RideStats(averageSpeedMPS: 6, maxSpeedMPS: 11, averageCadenceRPM: 88, maxCadenceRPM: 104)
        let store = TestStore(initialState: RidesFeature.State(rides: [ride])) {
            RidesFeature()
        } withDependencies: {
            $0.persistenceClient = .mock(rideStats: [ride.id: stats])
        }

        await store.send(.path(.push(id: 0, state: .detail(RideDetailFeature.State(summary: ride))))) {
            $0.path[id: 0] = .detail(RideDetailFeature.State(summary: ride))
        }
        store.exhaustivity = .off
        await store.send(.path(.element(id: 0, action: .detail(.task))))
        await store.finish()
        await store.skipReceivedActions()

        #expect(store.state.path[id: 0, case: \.detail]?.stats == stats)
        #expect(store.state.path[id: 0, case: \.detail]?.summary == ride)
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
        let finalized = LockIsolated(false)
        let store = TestStore(initialState: RidesFeature.State()) {
            RidesFeature()
        } withDependencies: {
            $0.continuousClock = testClock
            var client = PersistenceClient.mock()
            client.fetchRides = { finalized.value ? [ride] : [] }
            $0.persistenceClient = client
        }

        await store.send(.rideFinished(ride.id))
        finalized.setValue(true)
        await testClock.advance(by: .milliseconds(200))
        await store.receive(\.ridesResponse) {
            $0.hasLoaded = true
            $0.rides = [ride]
        }
        // The thumbnail's own wait reads once a second.
        await testClock.advance(by: .seconds(1))
        await store.receive(\.captureMapThumbnails)
    }

    /// A write that never lands (or a finalize that genuinely failed) must not poll
    /// forever — the last read wins once the ceiling is reached.
    @Test("rideFinished gives up after its poll ceiling rather than waiting forever")
    func rideFinishedGivesUpAfterCeiling() async {
        let testClock = TestClock()
        let store = TestStore(initialState: RidesFeature.State()) {
            RidesFeature()
        } withDependencies: {
            $0.continuousClock = testClock
            $0.persistenceClient = .mock()
        }

        await store.send(.rideFinished(UUID()))
        await testClock.advance(by: .seconds(2))
        await store.receive(\.ridesResponse) {
            $0.hasLoaded = true
        }
        // The thumbnail waits longer, then captures anyway: nothing new to find.
        await testClock.advance(by: .seconds(60))
        await store.receive(\.captureMapThumbnails)
    }

    /// Pre-existing until the #248 review: a read failing every time was sent as an empty
    /// success, which cleared the list and claimed "No Rides Yet" with rides on disk.
    @Test("rideFinished keeps the list when every read fails, rather than emptying it")
    func rideFinishedKeepsListWhenReadsFail() async {
        let testClock = TestClock()
        let existing = Self.summary()
        var state = RidesFeature.State()
        state.rides = [existing]
        state.hasLoaded = true
        let store = TestStore(initialState: state) {
            RidesFeature()
        } withDependencies: {
            $0.continuousClock = testClock
            var client = PersistenceClient.mock()
            client.fetchRides = { throw PersistenceError.rideNotFound }
            $0.persistenceClient = client
        }

        await store.send(.rideFinished(UUID()))
        await testClock.advance(by: .seconds(2))
        await store.receive(\.ridesResponse.failure)
        #expect(store.state.rides == [existing])
        await testClock.advance(by: .seconds(60))
        await store.receive(\.captureMapThumbnails)
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

    /// A PNG that decodes, so the row's images are real rather than a stand-in `Data`.
    private static let png: Data = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
        UIColor.gray.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    }

    private static func isLoaded(_ thumbnail: RidesFeature.Thumbnail?) -> Bool {
        if case .loaded = thumbnail { return true }
        return false
    }

    @Test("a row's first appearance reads and decodes its thumbnail, once")
    func rowAppearanceLoadsThumbnail() async {
        let ride = Self.summary()
        let reads = LockIsolated(0)
        let store = TestStore(initialState: RidesFeature.State()) {
            RidesFeature()
        } withDependencies: {
            var client = PersistenceClient.mock()
            client.fetchRideMapThumbnail = { _ in
                reads.withValue { $0 += 1 }
                return RideMapThumbnailData(light: Self.png, dark: Self.png)
            }
            $0.persistenceClient = client
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.rowAppeared(ride.id)) {
            $0.thumbnails[ride.id] = .loading
        }
        await store.receive(\.thumbnailLoaded)
        #expect(Self.isLoaded(store.state.thumbnails[ride.id]))

        // Scrolled away and back: already loaded, so no second read.
        await store.send(.rowAppeared(ride.id))
        #expect(reads.value == 1)
    }

    @Test("a ride with no stored image shows as missing")
    func rowWithoutImageIsMissing() async {
        let ride = Self.summary()
        let store = TestStore(initialState: RidesFeature.State()) {
            RidesFeature()
        } withDependencies: {
            $0.persistenceClient = .mock()
        }

        await store.send(.rowAppeared(ride.id)) {
            $0.thumbnails[ride.id] = .loading
        }
        await store.receive(\.thumbnailLoaded) {
            $0.thumbnails[ride.id] = .missing
        }
    }

    /// The row is already on screen with the placeholder when the capture lands, and it
    /// won't appear again, so the reducer has to go back for it.
    @Test("after a Finish, a row on screen without an image picks up the capture")
    func captureRefreshesMissingRows() async {
        let ride = Self.summary()
        let captured = LockIsolated(false)
        var state = RidesFeature.State()
        state.thumbnails[ride.id] = .missing
        let store = TestStore(initialState: state) {
            RidesFeature()
        } withDependencies: {
            var client = PersistenceClient.mock(trackPoints: [ride.id: Self.track(ride.id)], rides: [ride])
            client.fetchRideIdsMissingMapThumbnail = { captured.value ? [] : [ride.id] }
            client.saveRideMapThumbnail = { _, _, _ in captured.setValue(true) }
            client.fetchRideMapThumbnail = { _ in
                captured.value ? RideMapThumbnailData(light: Self.png, dark: Self.png) : nil
            }
            $0.persistenceClient = client
            $0.mapSnapshotClient = MapSnapshotClient { _, _, _ in Self.png }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.rideFinished(ride.id))
        await store.receive(\.captureMapThumbnails)
        await store.receive(\.mapThumbnailsCaptured)
        await store.receive(\.thumbnailLoaded)
        #expect(Self.isLoaded(store.state.thumbnails[ride.id]))
    }

    /// A trainer ride, or one already captured: nothing new, so no rows are re-read.
    @Test("a capture that stores nothing doesn't re-read any rows")
    func captureOfNothingReadsNothing() async {
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
        // Exhaustive: a `mapThumbnailsCaptured` would fail the test here.
    }

    /// The #248 review's finding: the capture used to start from inside the list's poll,
    /// so a delete in the seconds after a Finish, before the finalize had landed, cancelled
    /// it before it began.
    @Test("a delete while the ride is still finalizing doesn't stop its thumbnail")
    func deleteBeforeFinalizeKeepsTheCapture() async {
        let testClock = TestClock()
        let ride = Self.summary()
        let older = Self.summary(title: "Older")
        let finalized = LockIsolated(false)
        let captured = LockIsolated(false)
        var state = RidesFeature.State()
        state.rides = [older]
        let store = TestStore(initialState: state) {
            RidesFeature()
        } withDependencies: {
            $0.continuousClock = testClock
            var client = PersistenceClient.mock(trackPoints: [ride.id: Self.track(ride.id)])
            client.fetchRides = { finalized.value ? [ride] : [older] }
            client.fetchRideIdsMissingMapThumbnail = { finalized.value && !captured.value ? [ride.id] : [] }
            client.saveRideMapThumbnail = { _, _, _ in captured.setValue(true) }
            $0.persistenceClient = client
            $0.mapSnapshotClient = MapSnapshotClient { _, _, _ in Self.png }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.rideFinished(ride.id))
        await store.send(.deleteRecordedRide(older.id))
        finalized.setValue(true)
        await testClock.advance(by: .seconds(1))
        await store.receive(\.captureMapThumbnails)
        await store.receive(\.mapThumbnailsCaptured)
        #expect(captured.value)
    }

    /// Once rendering, the capture must not sit under the list's cancel id either.
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
            var client = PersistenceClient.mock(trackPoints: [ride.id: Self.track(ride.id)], rides: [ride, older])
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
                return Self.png
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.rideFinished(ride.id))
        await store.receive(\.captureMapThumbnails)
        for await _ in renderStarted { break }

        await store.send(.deleteRecordedRide(older.id))
        releaseContinuation.yield()

        await store.receive(\.mapThumbnailsCaptured)
        #expect(captured.value)
    }

    /// Every capture shares one id and the newest wins, so an offline launch's backfill and
    /// a Finish don't both render and save the same rides.
    @Test("a second capture replaces the one in flight rather than running beside it")
    func captureCancelsTheOneInFlight() async {
        let ride = Self.summary()
        let saves = LockIsolated(0)
        let renders = LockIsolated(0)
        let (firstStarted, firstStartedContinuation) = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: RidesFeature.State()) {
            RidesFeature()
        } withDependencies: {
            var client = PersistenceClient.mock(trackPoints: [ride.id: Self.track(ride.id)])
            client.fetchRideIdsMissingMapThumbnail = { saves.value > 0 ? [] : [ride.id] }
            client.saveRideMapThumbnail = { _, _, _ in saves.withValue { $0 += 1 } }
            $0.persistenceClient = client
            // The first render hangs until cancelled, like one waiting on a dead network.
            $0.mapSnapshotClient = MapSnapshotClient { _, _, _ in
                let render = renders.withValue { $0 += 1; return $0 }
                if render == 1 {
                    firstStartedContinuation.yield()
                    try await Task.never()
                }
                return Self.png
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.captureMapThumbnails)
        for await _ in firstStarted { break }
        await store.send(.captureMapThumbnails)
        await store.receive(\.mapThumbnailsCaptured)

        // The first run never saves: it was cancelled with a render still hanging. One
        // save, from the second run, rather than one from each.
        #expect(saves.value == 1)
    }
}
