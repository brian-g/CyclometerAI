import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// #206: the rider is told a store failed to open, and can reset it, never under a ride.
@MainActor
@Suite("AppFeature — store recovery")
struct AppStoreRecoveryTests {
    private static let historyFailed = PersistentStoreStatus(
        history: StoreFailure(storeURL: URL(filePath: "/tmp/default.store"), reason: "corrupt")
    )

    private static let preserved = URL(filePath: "/tmp/Preserved Stores/default-failed-20261117-101500.store")

    /// Seeds the status into the store's own in-memory storage, as `unsavedTrack(in:)` does:
    /// a value written before the `TestStore` exists lands in the test's, not the store's.
    private static func seed(_ status: PersistentStoreStatus, in store: TestStoreOf<AppFeature>) {
        withDependencies {
            $0.defaultInMemoryStorage = store.dependencies.defaultInMemoryStorage
        } operation: {
            @Shared(.persistentStoreStatus) var shared
            $shared.withLock { $0 = status }
        }
    }

    @Test("launch publishes the stores' status for S14 and S19")
    func launchReadsStatus() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.persistenceClient = .mock(storeStatus: Self.historyFailed)
        }
        store.exhaustivity = .off

        await store.send(.task)

        #expect(store.state.storeStatus == Self.historyFailed)
        #expect(store.state.rides.storeStatus == Self.historyFailed)
        #expect(store.state.routes.storeStatus == Self.historyFailed)
    }

    @Test("Reset asks first, then resets, says where the old store went and reloads both tabs")
    func resetConfirmedAndRun() async {
        let reset = PersistentStoreReset(preservedStores: [Self.preserved], status: .available)
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.persistenceClient = .mock(storeStatus: Self.historyFailed, storeReset: reset)
        }
        Self.seed(Self.historyFailed, in: store)

        await store.send(.rides(.resetStoreButtonTapped))
        await store.receive(\.rides.delegate.resetHistoryRequested) {
            $0.storeReset = .confirmReset(Self.historyFailed)
        }
        // Non-exhaustive from here: the mock's reset returns at once, and the shared status it
        // writes is a reference, so it can land before `send` checks the confirm's own state.
        store.exhaustivity = .off
        await store.send(.storeReset(.presented(.confirm)))
        await store.receive(\.storeResetFinished.success)
        await store.receive(\.rides.reloadRides)
        await store.receive(\.routes.reloadRoutes)
        #expect(store.state.storeStatus == .available)
        #expect(store.state.rides.storeStatus == .available)
        #expect(store.state.storeReset == .resetFinished(reset))
    }

    @Test("S19's Reset button reaches the same confirmation")
    func resetFromRoutes() async {
        let store = TestStore(initialState: AppFeature.State()) { AppFeature() }
        Self.seed(Self.historyFailed, in: store)

        await store.send(.routes(.resetStoreButtonTapped))
        await store.receive(\.routes.delegate.resetHistoryRequested) {
            $0.storeReset = .confirmReset(Self.historyFailed)
        }
    }

    @Test("no reset while a ride is recording")
    func noResetDuringRide() async {
        let store = TestStore(
            initialState: AppFeature.State(activeRide: ActiveRideFeature.State(recordingState: .active))
        ) { AppFeature() }
        Self.seed(Self.historyFailed, in: store)

        await store.send(.rides(.resetStoreButtonTapped))
        await store.receive(\.rides.delegate.resetHistoryRequested)
    }

    @Test("a ride started while the confirmation was up stops the reset")
    func rideStartedDuringConfirmation() async {
        var state = AppFeature.State(activeRide: ActiveRideFeature.State(recordingState: .active))
        state.storeReset = .confirmReset(Self.historyFailed)
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.persistenceClient.resetUnavailableStores = {
                Issue.record("reset ran under a ride")
                return PersistentStoreReset(preservedStores: [], status: .available)
            }
        }

        await store.send(.storeReset(.presented(.confirm))) {
            $0.storeReset = nil
        }
    }

    @Test("a reset that fails says nothing changed")
    func resetFails() async {
        var state = AppFeature.State()
        state.storeReset = .confirmReset(Self.historyFailed)
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.persistenceClient.resetUnavailableStores = { throw WriteFailed() }
        }

        await store.send(.storeReset(.presented(.confirm))) {
            $0.storeReset = nil
        }
        await store.receive(\.storeResetFinished.failure) {
            $0.storeReset = .resetFailed(nothingChanged: true)
        }
    }

    @Test("a reset that fails part-way shows the stores as they now stand")
    func resetFailsPartWay() async {
        var state = AppFeature.State()
        state.storeReset = .confirmReset(Self.historyFailed)
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            // History was reset before the throw, so the stores now report it open.
            $0.persistenceClient.storeStatus = { .available }
            $0.persistenceClient.resetUnavailableStores = { throw WriteFailed() }
        }
        Self.seed(Self.historyFailed, in: store)
        store.exhaustivity = .off

        await store.send(.storeReset(.presented(.confirm)))
        await store.receive(\.storeResetFinished.failure)
        await store.receive(\.rides.reloadRides)
        await store.receive(\.routes.reloadRoutes)
        #expect(store.state.storeStatus == .available)
        #expect(store.state.rides.storeStatus == .available)
        #expect(store.state.storeReset == .resetFailed(nothingChanged: false))
    }

    @Test("nothing to reset when both stores opened")
    func noResetWhenAvailable() async {
        let store = TestStore(initialState: AppFeature.State()) { AppFeature() }

        await store.send(.rides(.resetStoreButtonTapped))
        await store.receive(\.rides.delegate.resetHistoryRequested)
    }
}
