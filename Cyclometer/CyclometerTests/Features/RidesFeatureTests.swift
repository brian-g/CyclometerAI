import ComposableArchitecture
import Foundation
import Testing
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
}
