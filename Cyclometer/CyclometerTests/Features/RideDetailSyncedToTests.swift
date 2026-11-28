import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// S15's Synced To row (#632): which capsules it draws from a ride's `RideSyncRecord` and Health
/// workout, and what tapping them, or Retry, does.
@MainActor
@Suite("RideDetailFeature — Synced To")
struct RideDetailSyncedToTests {

    // MARK: Harness

    nonisolated private static let summary = RideListSummary(
        id: UUID(), title: "River Loop", startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        distanceMeters: 36_050, durationSeconds: 4_712
    )

    nonisolated private static let synced = RideSyncRecord(service: .strava, status: .synced, syncedAt: .distantPast, remoteActivityId: "987")
    nonisolated private static let failed = RideSyncRecord(service: .strava, status: .failed, errorMessage: "The file was empty.")

    nonisolated private static func stats(strava: RideSyncRecord? = nil, healthOwed: Bool = false) -> RideStats {
        RideStats(averageSpeedMPS: 6, maxSpeedMPS: 11, endedAt: summary.startedAt.addingTimeInterval(4_800),
                  stravaRecord: strava, isHealthWorkoutOwed: healthOwed)
    }

    nonisolated static func account(scopes: [String] = StravaConfig.requestedScopes, isDisconnected: Bool = false) -> ConnectedService {
        ConnectedService(serviceType: .strava, keychainIdentifier: StravaConfig.keychainAccount, athleteID: "1",
                         grantedScopes: Set(scopes), connectedAt: .distantPast, isDisconnected: isDisconnected)
    }

    /// S15 with its stats in, and Strava connected unless `account` is nil.
    private func makeStore(
        stats: RideStats? = Self.stats(),
        account: ConnectedService? = Self.account(),
        healthPresence: HealthWorkoutPresence? = HealthWorkoutPresence.none,
        configure: (inout RideDetailFeature.State) -> Void = { _ in },
        dependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<RideDetailFeature> {
        let storage = FileStorage.inMemory
        let memory = InMemoryStorage()
        return withDependencies {
            $0.defaultFileStorage = storage
            $0.defaultInMemoryStorage = memory
        } operation: {
            var state = RideDetailFeature.State(summary: Self.summary)
            state.$preferences.withLock { $0.connectedServices = account.map { [$0] } ?? [] }
            state.stats = stats
            state.healthPresence = healthPresence
            configure(&state)
            return TestStore(initialState: state) {
                RideDetailFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
                $0.defaultInMemoryStorage = memory
                $0.persistenceClient = .mock()
                $0.strava = .mock()
                $0.openURL = OpenURLEffect { _ in Issue.record("opened a URL"); return true }
                dependencies(&$0)
            }
        }
    }

    private typealias Capsule = RideDetailFeature.SyncedTo.Capsule

    // MARK: - The row, from fixtures

    @Test("No row before the stats, nor for a ride sent nowhere with Strava not connected")
    func hiddenRows() {
        #expect(makeStore(stats: nil).state.syncedTo == nil)
        #expect(makeStore(account: nil).state.syncedTo == nil)
    }

    @Test("Never sent, Strava connected: both capsules grey, no status line")
    func neverSent() {
        #expect(makeStore().state.syncedTo == RideDetailFeature.SyncedTo(
            capsules: [Capsule(destination: .appleHealth, isSent: false), Capsule(destination: .service(.strava), isSent: false)],
            status: nil
        ))
    }

    @Test("Strava filled from the moment it's queued: S15 shows no progress", arguments: [SyncStatus.pending, .uploading, .processing, .synced])
    func stravaFilled(_ status: SyncStatus) {
        let syncedTo = makeStore(stats: Self.stats(strava: RideSyncRecord(service: .strava, status: status))).state.syncedTo
        #expect(syncedTo?.capsules.last == Capsule(destination: .service(.strava), isSent: true))
        #expect(syncedTo?.status == nil)
    }

    @Test("A failed upload: Strava grey, with Strava's reason on the status line")
    func failedUpload() {
        let syncedTo = makeStore(stats: Self.stats(strava: Self.failed)).state.syncedTo
        #expect(syncedTo?.capsules.last == Capsule(destination: .service(.strava), isSent: false))
        #expect(syncedTo?.status == .failed("The file was empty."))
    }

    @Test("A ride with a record keeps its Strava capsule while Strava isn't connected")
    func recordWithoutAccount() {
        let syncedTo = makeStore(stats: Self.stats(strava: Self.synced), account: nil).state.syncedTo
        #expect(syncedTo?.capsules == [Capsule(destination: .appleHealth, isSent: false), Capsule(destination: .service(.strava), isSent: true)])
    }

    @Test("Apple Health is filled for our workout, another source's, or one owed", arguments: [(HealthWorkoutPresence?, Bool)]([
        (.ours, false), (.otherSource, false), (HealthWorkoutPresence.none, true), (nil, true),
    ]))
    func healthFilled(_ presence: HealthWorkoutPresence?, _ owed: Bool) {
        let store = makeStore(stats: Self.stats(healthOwed: owed), account: nil, healthPresence: presence)
        #expect(store.state.syncedTo == RideDetailFeature.SyncedTo(capsules: [Capsule(destination: .appleHealth, isSent: true)], status: nil))
    }

    @Test("A record written since the stats loaded wins over theirs; a deleted one leaves the ride unsent")
    func liveRecordWins() {
        let store = makeStore(stats: Self.stats(strava: Self.synced))
        // Written from outside the store, as the live persistence client writes it.
        store.exhaustivity = .off
        withDependencies { $0.defaultInMemoryStorage = store.dependencies.defaultInMemoryStorage } operation: {
            @Shared(.liveStravaSyncRecords) var live
            $live.withLock { $0.set(Self.failed, for: Self.summary.id) }
        }
        #expect(store.state.stravaRecord == Self.failed)
        withDependencies { $0.defaultInMemoryStorage = store.dependencies.defaultInMemoryStorage } operation: {
            @Shared(.liveStravaSyncRecords) var live
            $live.withLock { $0.set(nil, for: Self.summary.id) }
        }
        #expect(store.state.stravaRecord == nil)
        #expect(store.state.syncedTo?.capsules.last == Capsule(destination: .service(.strava), isSent: false))
    }

    // MARK: - Taps

    @Test("A grey Strava capsule sends the ride at once, with no dialog")
    func greyStravaUploads() async {
        let store = makeStore(configure: { $0.isStravaActivityDeleted = true })
        await store.send(.syncedToTapped(.service(.strava))) { $0.isStravaActivityDeleted = false }
        await store.receive(.delegate(.uploadToStrava(rideId: Self.summary.id)))
    }

    @Test("Retry on a failed upload sends it again; with nothing failed it does nothing")
    func retry() async {
        let failed = makeStore(stats: Self.stats(strava: Self.failed))
        await failed.send(.syncRetryTapped)
        await failed.receive(.delegate(.uploadToStrava(rideId: Self.summary.id)))

        await makeStore(stats: Self.stats(strava: Self.synced)).send(.syncRetryTapped)
    }

    @Test("A filled Strava capsule on its way has no activity yet, so it opens nothing")
    func inFlightOpensNothing() async {
        await makeStore(stats: Self.stats(strava: RideSyncRecord(service: .strava, status: .processing))).send(.syncedToTapped(.service(.strava)))
    }

    @Test("A synced ride opens in the Strava app; without the app, on the web")
    func opensActivity() async {
        for hasApp in [true, false] {
            let opened = LockIsolated<[URL]>([])
            let store = makeStore(stats: Self.stats(strava: Self.synced)) {
                $0.openURL = OpenURLEffect { url in
                    opened.withValue { $0.append(url) }
                    return hasApp || url.scheme == "https"
                }
            }
            await store.send(.syncedToTapped(.service(.strava)))
            await store.finish()
            let app = URL(string: "strava://activities/987")!, web = URL(string: "https://www.strava.com/activities/987")!
            #expect(opened.value == (hasApp ? [app] : [app, web]))
        }
    }

    @Test("An activity deleted on Strava resets the record, says so, and opens nothing")
    func deletedOnStrava() async {
        let deleted = LockIsolated<[UUID]>([])
        let store = makeStore(stats: Self.stats(strava: Self.synced)) {
            $0.strava = .mock(deletedActivities: ["987"])
            $0.persistenceClient = .mock(onDeleteSyncRecord: { id, service in
                #expect(service == .strava)
                deleted.withValue { $0.append(id) }
            })
        }
        await store.send(.syncedToTapped(.service(.strava)))
        await store.receive(.stravaActivityDeleted) {
            $0.stats?.stravaRecord = nil
            $0.isStravaActivityDeleted = true
        }
        #expect(deleted.value == [Self.summary.id])
        #expect(store.state.syncedTo?.status == .deletedOnStrava)
        #expect(store.state.syncedTo?.capsules.last == Capsule(destination: .service(.strava), isSent: false))
    }

    @Test("Without the private-activities scope a 404 can't mean deleted: nothing is checked, and it opens")
    func noPrivateScopeNoCheck() async {
        let opened = LockIsolated<[URL]>([])
        let store = makeStore(stats: Self.stats(strava: Self.synced),
                              account: Self.account(scopes: StravaConfig.requestedScopes.filter { $0 != StravaConfig.privateActivitiesScope })) {
            var strava = StravaClient.mock()
            strava.activityExists = { _ in Issue.record("checked the activity"); return false }
            $0.strava = strava
            $0.openURL = OpenURLEffect { url in opened.withValue { $0.append(url) }; return true }
        }
        await store.send(.syncedToTapped(.service(.strava)))
        await store.finish()
        #expect(opened.value == [URL(string: "strava://activities/987")!])
    }

    @Test("Offline, the check fails and the activity opens as it stands")
    func offlineOpens() async {
        let opened = LockIsolated<[URL]>([])
        let store = makeStore(stats: Self.stats(strava: Self.synced)) {
            var strava = StravaClient.mock()
            strava.activityExists = { _ in throw URLError(.notConnectedToInternet) }
            $0.strava = strava
            $0.openURL = OpenURLEffect { url in opened.withValue { $0.append(url) }; return true }
        }
        await store.send(.syncedToTapped(.service(.strava)))
        await store.finish()
        #expect(opened.value == [URL(string: "strava://activities/987")!])
    }

    @Test("A grey Apple Health capsule marks the ride owed and asks for its workout")
    func greyHealthAdds() async {
        let store = makeStore()
        await store.send(.syncedToTapped(.appleHealth)) { $0.stats?.isHealthWorkoutOwed = true }
        await store.receive(.delegate(.addToAppleHealth(rideId: Self.summary.id)))
        #expect(store.state.syncedTo?.capsules.first == Capsule(destination: .appleHealth, isSent: true))
    }

    @Test("A filled Apple Health capsule opens Health")
    func filledHealthOpens() async {
        let opened = LockIsolated<[URL]>([])
        let store = makeStore(healthPresence: .ours) {
            $0.openURL = OpenURLEffect { url in opened.withValue { $0.append(url) }; return true }
        }
        await store.send(.syncedToTapped(.appleHealth))
        await store.finish()
        #expect(opened.value == [RideDetailFeature.healthAppURL])
    }

    // MARK: - Loading

    @Test("The Health read follows the stats, over the ride's start to its end")
    func healthPresenceLoads() async {
        let asked = LockIsolated<[(UUID, Date, Date)]>([])
        let stats = Self.stats()
        let store = makeStore(stats: nil, healthPresence: nil) {
            $0.persistenceClient = .mock(rideStats: [Self.summary.id: stats])
            var health = HealthKitClient.testValue
            health.workoutPresence = { id, start, end in
                asked.withValue { $0.append((id, start, end)) }
                return .otherSource
            }
            $0.healthKitClient = health
            // `.task`'s heart-rate profile read takes the 220 − age estimate from it.
            $0.date = .constant(Date(timeIntervalSince1970: 1_750_000_000))
        }
        store.exhaustivity = .off
        await store.send(.task)
        await store.finish()
        await store.skipReceivedActions()
        #expect(store.state.healthPresence == .otherSource)
        #expect(asked.value.count == 1)
        #expect(asked.value.first?.0 == Self.summary.id)
        #expect(asked.value.first?.1 == Self.summary.startedAt)
        #expect(asked.value.first?.2 == stats.endedAt)
    }
}
