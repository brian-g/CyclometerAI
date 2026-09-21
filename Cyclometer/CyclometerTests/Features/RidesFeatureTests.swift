import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

@MainActor
@Suite("RidesFeature")
struct RidesFeatureTests {

    @Test("Deleting a demo ride drops it from state")
    func deleteDemoRideRemovesIt() async {
        let demoRides = DemoRide.sampleRides
        let doomed = demoRides[0]
        let store = TestStore(initialState: RidesFeature.State(demoRides: demoRides)) {
            RidesFeature()
        }

        await store.send(.deleteDemoRide(doomed.id)) {
            $0.demoRides.removeAll { $0.id == doomed.id }
        }
    }

    /// The swipe action's whole job (#261). A recorded ride is SwiftData's, reaching the
    /// list through `AppView`'s `@Query`, so nothing changes in this reducer's state —
    /// what must happen is that persistence is told to let go of everything the ride owns.
    @Test("Deleting a recorded ride asks persistence to delete it")
    func deleteRecordedRideReachesPersistence() async {
        let deleted = LockIsolated<[UUID]>([])
        let rideId = UUID()
        let store = TestStore(initialState: RidesFeature.State()) {
            RidesFeature()
        } withDependencies: {
            $0.persistenceClient = .mock(onDeleteRide: { id in deleted.withValue { $0.append(id) } })
        }

        await store.send(.deleteRecordedRide(rideId))

        #expect(deleted.value == [rideId])
    }

    /// A failed delete is logged, not propagated: there is no state to roll back and no
    /// alert in this screen's design to show. It must not crash the reducer.
    @Test("A persistence failure does not escape the reducer")
    func deleteFailureIsContained() async {
        let store = TestStore(initialState: RidesFeature.State()) {
            RidesFeature()
        } withDependencies: {
            $0.persistenceClient.deleteRide = { _ in throw PersistenceError.rideNotFound }
        }

        await store.send(.deleteRecordedRide(UUID()))
    }
}
