import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// S14's Sync swipe (#632, UX §S14): offered for a failed upload or a ride never sent while Strava
/// is connected, never for one on its way or on Strava, and S15's sends pass through the tab.
@MainActor
@Suite("RidesFeature — Sync swipe")
struct RidesSyncSwipeTests {
    private static func ride(_ status: SyncStatus?) -> RideListSummary {
        RideListSummary(id: UUID(), title: "Gnarly", startedAt: Date(timeIntervalSince1970: 1_000_000),
                        distanceMeters: 10_000, durationSeconds: 1_800, stravaSyncStatus: status)
    }

    private func makeStore(connected: Bool = true, rides: [RideListSummary]) -> TestStoreOf<RidesFeature> {
        let storage = FileStorage.inMemory
        let memory = InMemoryStorage()
        return withDependencies {
            $0.defaultFileStorage = storage
            $0.defaultInMemoryStorage = memory
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.connectedServices = connected ? [RideDetailSyncedToTests.account()] : [] }
            return TestStore(initialState: RidesFeature.State(rides: rides)) {
                RidesFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
                $0.defaultInMemoryStorage = memory
            }
        }
    }

    @Test("Offered for a failed upload, and for a ride never sent while Strava is connected", arguments: [
        (SyncStatus?.some(.failed), true, true), (nil, true, true), (nil, false, false), (.failed, false, true),
        (.pending, true, false), (.uploading, true, false), (.processing, true, false), (.synced, true, false),
    ])
    func offered(_ status: SyncStatus?, _ connected: Bool, _ offered: Bool) {
        let ride = Self.ride(status)
        #expect(makeStore(connected: connected, rides: [ride]).state.offersSync(ride) == offered)
    }

    @Test("A record written since the list loaded decides: on its way hides the swipe, a reset brings it back")
    func followsLiveRecords() {
        let failed = Self.ride(.failed), synced = Self.ride(.synced)
        let store = makeStore(rides: [failed, synced])
        store.exhaustivity = .off
        withDependencies { $0.defaultInMemoryStorage = store.dependencies.defaultInMemoryStorage } operation: {
            @Shared(.liveStravaSyncRecords) var live
            $live.withLock {
                $0.set(RideSyncRecord(service: .strava, status: .uploading), for: failed.id)
                $0.set(nil, for: synced.id)
            }
        }
        #expect(!store.state.offersSync(failed))
        #expect(store.state.offersSync(synced))
    }

    @Test("The swipe sends the ride to the app; on a row that doesn't offer it, nothing")
    func swipeSends() async {
        let failed = Self.ride(.failed), synced = Self.ride(.synced)
        let store = makeStore(rides: [failed, synced])

        await store.send(.syncSwiped(failed.id))
        await store.receive(.delegate(.uploadToStrava(rideId: failed.id)))
        await store.send(.syncSwiped(synced.id))
    }

    @Test("S15's Synced To sends on this tab's stack reach the app")
    func detailSendsPassThrough() async {
        let ride = Self.ride(nil)
        let store = makeStore(rides: [ride])
        store.exhaustivity = .off
        await store.send(.path(.push(id: 0, state: .ride(RideDetailFeature.State(summary: ride)))))

        await store.send(.path(.element(id: 0, action: .ride(.delegate(.uploadToStrava(rideId: ride.id))))))
        await store.receive(.delegate(.uploadToStrava(rideId: ride.id)))
        await store.send(.path(.element(id: 0, action: .ride(.delegate(.addToAppleHealth(rideId: ride.id))))))
        await store.receive(.delegate(.addToAppleHealth(rideId: ride.id)))
    }
}
