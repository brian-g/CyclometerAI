import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// Sending a ride again from after S10 (#632): S14's Sync swipe, S15's Synced To Retry and S12.1's
/// Retry each reach the app's upload queue, and a second tap while the first upload runs sends
/// nothing more. Through `AppFeature`, so the delegates are proven wired end to end.
@MainActor
@Suite("Sync retry")
struct SyncRetryTests {
    static let rideId = UUID(uuidString: "00000000-0000-0000-0000-000000000632")!
    static let failed = RideSyncRecord(service: .strava, status: .failed, errorMessage: "The file was empty.")
    static let ride = RideListSummary(id: rideId, title: "Gnarly", startedAt: Date(timeIntervalSince1970: 1_000_000),
                                      distanceMeters: 10_000, durationSeconds: 1_800, stravaSyncStatus: .failed)

    /// The app with Strava connected and able to take uploads, and one ride whose upload failed.
    /// Strava processes an upload a second after it lands.
    private func makeStore(
        _ state: (inout AppFeature.State) -> Void = { _ in },
        uploads: LockIsolated<Int>,
        clock: TestClock<Duration>,
        persistenceClient: PersistenceClient? = nil
    ) -> TestStoreOf<AppFeature> {
        let storage = FileStorage.inMemory
        let memory = InMemoryStorage()
        return withDependencies {
            $0.defaultFileStorage = storage
            $0.defaultInMemoryStorage = memory
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.connectedServices = [RideDetailSyncedToTests.account()] }
            var initial = AppFeature.State()
            state(&initial)
            return TestStore(initialState: initial) {
                AppFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
                $0.defaultInMemoryStorage = memory
                $0.continuousClock = clock
                $0.date = .constant(Date(timeIntervalSince1970: 1_795_996_800))
                $0.uuid = .incrementing
                $0.bleHRClient = .testValue
                $0.variaRadarClient = .testValue
                $0.locationClient = .testValue
                $0.hapticsClient = .testValue
                $0.persistenceClient = persistenceClient ?? .mock(
                    rideExportMetadata: [Self.rideId: RideExportMetadata(title: "Gnarly", startedAt: Self.ride.startedAt)],
                    syncRecords: [Self.rideId: [Self.failed]]
                )
                $0.strava = .mock(onUpload: { _ in uploads.withValue { $0 += 1 } })
            }
        }
    }

    /// Taps twice, lets Strava process the upload, and returns how many went up.
    private func tapTwice(_ store: TestStoreOf<AppFeature>, clock: TestClock<Duration>, uploads: LockIsolated<Int>,
                          _ action: AppFeature.Action) async -> Int {
        store.exhaustivity = .off
        await store.send(action)
        await store.receive(\.syncQueue.enqueue)
        await store.send(action)
        await clock.advance(by: .seconds(1))
        await store.finish()
        return uploads.value
    }

    @Test("S14's Sync swipe queues the ride once, however often it's swiped")
    func swipeQueuesOnce() async {
        let uploads = LockIsolated(0), clock = TestClock()
        let store = makeStore({ $0.rides.rides = [Self.ride] }, uploads: uploads, clock: clock)
        #expect(await tapTwice(store, clock: clock, uploads: uploads, .rides(.syncSwiped(Self.rideId))) == 1)
    }

    @Test("S15's Retry queues the ride once, however often it's tapped")
    func detailRetryQueuesOnce() async {
        let uploads = LockIsolated(0), clock = TestClock()
        let store = makeStore(uploads: uploads, clock: clock)
        var detail = RideDetailFeature.State(summary: Self.ride)
        detail.stats = RideStats(averageSpeedMPS: 6, maxSpeedMPS: 11, stravaRecord: Self.failed)
        store.exhaustivity = .off
        await store.send(.rides(.path(.push(id: 0, state: .ride(detail)))))
        #expect(await tapTwice(store, clock: clock, uploads: uploads, .rides(.path(.element(id: 0, action: .ride(.syncRetryTapped))))) == 1)
    }

    @Test("S12.1's Retry queues the ride once, however often it's tapped")
    func accountRetryQueuesOnce() async {
        let uploads = LockIsolated(0), clock = TestClock()
        let store = makeStore(uploads: uploads, clock: clock)
        var account = AccountsFeature.State()
        account.fetchedUploads = [StravaWorkItem(rideId: Self.rideId, title: "Gnarly", record: Self.failed)]
        store.exhaustivity = .off
        await store.send(.settings(.path(.push(id: 0, state: .stravaAccount(account)))))
        #expect(await tapTwice(store, clock: clock, uploads: uploads,
                               .settings(.path(.element(id: 0, action: .stravaAccount(.retryTapped(rideId: Self.rideId)))))) == 1)
    }

    @Test("S15's grey Apple Health capsule marks the ride owed its workout, from the app")
    func addToAppleHealthMarksOwed() async {
        let owed = LockIsolated<[Bool]>([])
        let store = makeStore(uploads: LockIsolated(0), clock: TestClock(),
                              persistenceClient: .mock(onSetHealthWorkoutOwed: { id, isOwed in
                                  #expect(id == Self.rideId)
                                  owed.withValue { $0.append(isOwed) }
                              }))
        store.exhaustivity = .off
        await store.send(.rides(.delegate(.addToAppleHealth(rideId: Self.rideId))))
        await store.finish()
        #expect(owed.value == [true])
    }
}
