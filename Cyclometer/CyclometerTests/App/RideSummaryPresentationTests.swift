import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// S10 at the ride-end seam (#249): Finish presents it for the ride just ended, and dismissing it
/// — by its button or a swipe — saves the name.
@MainActor
@Suite("Ride Summary presentation")
struct RideSummaryPresentationTests {

    private static let rideId = UUID(uuidString: "00000000-0000-0000-0000-000000000249")!

    private func makeStore(
        _ state: AppFeature.State = AppFeature.State(),
        persistenceClient: PersistenceClient
    ) -> TestStoreOf<AppFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            TestStore(initialState: state) {
                AppFeature()
            } withDependencies: {
                $0.continuousClock = TestClock()
                $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
                $0.uuid = .incrementing
                $0.bleHRClient = .testValue
                $0.variaRadarClient = .testValue
                $0.locationClient = .testValue
                $0.hapticsClient = .testValue
                $0.persistenceClient = persistenceClient
                $0.defaultFileStorage = storage
            }
        }
    }

    /// App state with S10 up for a loaded, unnamed ride whose default is "Morning Loop".
    private func presenting(title: String, persistedTitle: String = "") -> AppFeature.State {
        var summary = RideSummaryFeature.State(rideId: Self.rideId)
        summary.load = .loaded
        summary.defaultTitle = "Morning Loop"
        summary.persistedTitle = persistedTitle
        summary.title = title
        var state = AppFeature.State()
        state.rideSummary = summary
        return state
    }

    @Test("confirming Finish presents S10 for the ride just ended, not the bare dashboard")
    func finishPresentsSummary() async {
        let store = makeStore(persistenceClient: .mock())
        store.exhaustivity = .off

        await store.send(.startRideButtonTapped)
        await store.send(.startSheet(.presented(.delegate(.startRide(nil)))))
        await store.receive(\.activeRide.task)
        let rideId = store.state.activeRide?.rideId

        await store.send(.activeRide(.pauseTapped))
        await store.send(.activeRide(.finishTapped))
        await store.send(.activeRide(.finishAlert(.presented(.confirmFinish))))

        #expect(store.state.activeRide == nil)
        #expect(store.state.isDashboardPresented == false)
        #expect(store.state.rideSummary?.rideId == rideId)
        #expect(store.state.rideSummary?.load == .waiting)
        await store.skipInFlightEffects()
    }

    @Test("the Finish Ride button dismisses S10 and saves the rider's name, refreshes S14, then rewrites the GPX")
    func finishButtonSavesRename() async {
        let renamed = LockIsolated<[(UUID, String)]>([])
        let replaced = LockIsolated<[(UUID, String)]>([])
        let store = makeStore(presenting(title: "Hill Repeats"), persistenceClient: .mock(
            // What the rewrite reads back once the rename has landed.
            rideExportMetadata: [Self.rideId: RideExportMetadata(title: "Hill Repeats", startedAt: Date(timeIntervalSince1970: 1_000_000))],
            onRenameRide: { id, title in renamed.withValue { $0.append((id, title)) } },
            onReplaceRideGPX: { id, data in replaced.withValue { $0.append((id, String(decoding: data, as: UTF8.self))) } }
        ))
        store.exhaustivity = .off

        await store.send(.rideSummary(.presented(.finishTapped)))
        await store.receive(\.rideSummary.dismiss)
        await store.receive(\.rides.reloadRides)
        await store.finish()

        #expect(store.state.rideSummary == nil)
        #expect(renamed.value.map(\.0) == [Self.rideId])
        #expect(renamed.value.map(\.1) == ["Hill Repeats"])
        #expect(replaced.value.map(\.0) == [Self.rideId])
        #expect(replaced.value.first?.1.contains("<trk>\n    <name>Hill Repeats</name>") == true)
    }

    @Test("a rename that fails leaves the GPX alone")
    func failedRenameSkipsRewrite() async {
        let replaced = LockIsolated(0)
        var client = PersistenceClient.mock(onReplaceRideGPX: { _, _ in replaced.withValue { $0 += 1 } })
        client.renameRide = { _, _ in throw PersistenceError.rideNotFound }
        let store = makeStore(presenting(title: "Hill Repeats"), persistenceClient: client)

        await store.send(.rideSummary(.dismiss)) {
            $0.rideSummary = nil
        }
        await store.finish()
        #expect(replaced.value == 0)
    }

    /// A swipe-down arrives as a bare `.dismiss`, with no child action before it.
    @Test("swiping S10 away saves the name too — the default, when the rider didn't type one")
    func swipeSavesDefault() async {
        let renamed = LockIsolated<[String]>([])
        let store = makeStore(presenting(title: "Morning Loop"), persistenceClient: .mock(
            onRenameRide: { _, title in renamed.withValue { $0.append(title) } }
        ))
        store.exhaustivity = .off

        await store.send(.rideSummary(.dismiss))
        await store.receive(\.rides.reloadRides)

        #expect(store.state.rideSummary == nil)
        #expect(renamed.value == ["Morning Loop"])
    }

    @Test("dismissing a ride whose name didn't change writes nothing")
    func unchangedNameNoWrite() async {
        let renamed = LockIsolated(0)
        let store = makeStore(presenting(title: "Coffee Run", persistedTitle: "Coffee Run"), persistenceClient: .mock(
            onRenameRide: { _, _ in renamed.withValue { $0 += 1 } }
        ))

        await store.send(.rideSummary(.dismiss)) {
            $0.rideSummary = nil
        }
        #expect(renamed.value == 0)
    }
}
