import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

/// The Start sheet's pairing scan, exercised through the presentation that owns it.
///
/// `StartSheetFeatureTests` drives the reducer directly and so cannot see this: the sheet
/// is a `@Presents` child, and every dismissal path clears `AppFeature.State.startSheet`
/// *before* SwiftUI runs `onDisappear` — so an action sent from there reaches an absent
/// destination and TCA drops it. A scan balanced from `.onDisappear` therefore never was,
/// leaking a reference on all three clients per sheet open and leaving the radio on for
/// the rest of the process. The release is tied to the effect's own cancellation instead,
/// and only a test at this level proves it.
@MainActor
@Suite("AppFeature — Start sheet pairing scan")
struct StartSheetPresentationTests {

    /// One log across all three clients, so the *balance* between them is what is
    /// asserted rather than three counters that each look plausible alone.
    enum ScanCall: Equatable {
        case begin(SensorKind)
        case end(SensorKind)
    }

    /// `initialState` is a closure so the state — and the `@Shared` preferences inside it — is
    /// built inside the in-memory storage scope below rather than at the call site.
    /// `AppRouteSelectionTests` uses it to start from a ride already on screen.
    static func makeStore(
        into log: LockIsolated<[ScanCall]>,
        initialState: () -> AppFeature.State = { AppFeature.State() }
    ) -> TestStoreOf<AppFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            var csc = BLECSCClient.testValue
            csc.beginPairingScan = { log.withValue { $0.append(.begin(.speedCadence)) } }
            csc.endPairingScan = { log.withValue { $0.append(.end(.speedCadence)) } }
            var radar = VariaRadarClient.testValue
            radar.beginPairingScan = { log.withValue { $0.append(.begin(.radar)) } }
            radar.endPairingScan = { log.withValue { $0.append(.end(.radar)) } }
            var hr = BLEHRClient.testValue
            hr.beginPairingScan = { log.withValue { $0.append(.begin(.heartRate)) } }
            hr.endPairingScan = { log.withValue { $0.append(.end(.heartRate)) } }

            return TestStore(initialState: initialState()) {
                AppFeature()
            } withDependencies: {
                $0.bleCSCClient = csc
                $0.variaRadarClient = radar
                $0.bleHRClient = hr
                $0.defaultFileStorage = storage
                // The ride-start path runs `activeRide(.task)` on its way past. Its own
                // behaviour is `ActiveRideFeatureTests`' business; here it only has to
                // not fail on an unimplemented dependency while the scan is released.
                $0.continuousClock = TestClock()
                $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
                $0.uuid = .incrementing
                $0.hapticsClient = .testValue
                $0.locationClient = .testValue
                $0.permissionsClient = .testValue
            }
        }
    }

    private static let begun: [ScanCall] = [.begin(.speedCadence), .begin(.radar), .begin(.heartRate)]
    private static let ended: [ScanCall] = [.end(.speedCadence), .end(.radar), .end(.heartRate)]

    /// Cancel, and the swipe-to-dismiss gesture, both arrive as `.dismiss`.
    @Test("Dismissing the sheet releases every scan it took")
    func dismissReleasesTheScan() async {
        let log = LockIsolated<[ScanCall]>([])
        let store = Self.makeStore(into: log)
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.startRideButtonTapped)
        await store.send(.startSheet(.presented(.task)))
        #expect(log.value == Self.begun)

        await store.send(.startSheet(.dismiss))
        await store.finish()

        #expect(log.value == Self.begun + Self.ended)
    }

    /// The other path: the parent nils the presented state itself when the ride starts.
    @Test("Starting the ride releases every scan the sheet took")
    func startingTheRideReleasesTheScan() async {
        let log = LockIsolated<[ScanCall]>([])
        let store = Self.makeStore(into: log)
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.startRideButtonTapped)
        await store.send(.startSheet(.presented(.task)))
        #expect(log.value == Self.begun)

        await store.send(.startSheet(.presented(.delegate(.startRide(nil)))))
        await store.finish()

        #expect(log.value == Self.begun + Self.ended)
    }

    /// Opening the sheet twice must not leave the radio holding two references.
    @Test("Two sheet openings balance to zero")
    func repeatedOpeningsBalance() async {
        let log = LockIsolated<[ScanCall]>([])
        let store = Self.makeStore(into: log)
        store.exhaustivity = .off(showSkippedAssertions: false)

        for _ in 0..<2 {
            await store.send(.startRideButtonTapped)
            await store.send(.startSheet(.presented(.task)))
            await store.send(.startSheet(.dismiss))
        }
        await store.finish()

        let begins = log.value.filter { if case .begin = $0 { return true } else { return false } }
        let ends = log.value.filter { if case .end = $0 { return true } else { return false } }
        #expect(begins.count == 6)
        #expect(ends.count == 6)
    }

    /// A ride a kill left behind, as `fetchResumableRide` hands it back.
    private static func resumable(_ rideId: UUID) -> RideSummaryUpdate {
        RideSummaryUpdate(
            rideId: rideId, recordingState: .active,
            durationSeconds: 300, distanceMeters: 2_000, averageSpeedMPS: 5, maxSpeedMPS: 9
        )
    }

    /// #231, order one: the resumed ride lands *while* S05.1 is open.
    ///
    /// `.task`'s resume fetch races the UI, so the rider can be looking at the Start sheet when
    /// the ride they were already on comes back. The sheet has to go — left up, its Start Ride
    /// would replace the resumed ride without finalizing it, and that orphaned Ride row would be
    /// the only non-`.ended` one at the next launch, resuming stale as if it were live.
    @Test("A resumed ride arriving while the sheet is up dismisses it and survives")
    func resumedRideArrivingWhileTheSheetIsUpDismissesIt() async {
        let log = LockIsolated<[ScanCall]>([])
        let finalized = LockIsolated<[UUID]>([])
        let resumedRideId = UUID()
        let store = Self.makeStore(into: log)
        store.dependencies.persistenceClient = .mock(
            onFinalizeRide: { id, _, _, _ in finalized.withValue { $0.append(id) } }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.startRideButtonTapped)
        await store.send(.startSheet(.presented(.task)))
        #expect(log.value == Self.begun)

        await store.send(.resumableRideFetched(Self.resumable(resumedRideId)))

        // The sheet is gone, so its Start Ride can no longer reach the reducer at all: TCA drops
        // a presented action aimed at an absent destination.
        #expect(store.state.startSheet == nil)
        #expect(store.state.activeRide?.rideId == resumedRideId)
        #expect(store.state.isDashboardPresented == true)

        // The resumed ride is live, not orphaned — finalizing it here is exactly the bug.
        #expect(finalized.value.isEmpty)

        await store.finish()
        #expect(log.value == Self.begun + Self.ended)
    }

    /// #231, order two: the rider gets a brand-new ride started before the fetch resolves.
    ///
    /// The #175 finalize path, now asserted with a sheet in the picture. The started ride must
    /// survive and the orphan must still be closed out — and the scan must *not* be released a
    /// second time, which is what would drive the clients' refcount below zero.
    @Test("A resumed ride arriving after Start Ride finalizes the orphan and leaves the new ride")
    func resumedRideArrivingAfterStartRideFinalizesTheOrphan() async {
        let log = LockIsolated<[ScanCall]>([])
        let finalized = LockIsolated<[UUID]>([])
        let orphanedRideId = UUID()
        let store = Self.makeStore(into: log)
        store.dependencies.persistenceClient = .mock(
            onFinalizeRide: { id, _, _, _ in finalized.withValue { $0.append(id) } }
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.startRideButtonTapped)
        await store.send(.startSheet(.presented(.task)))
        await store.send(.startSheet(.presented(.delegate(.startRide(nil)))))
        #expect(store.state.activeRide != nil)
        #expect(log.value == Self.begun + Self.ended)

        await store.send(.resumableRideFetched(Self.resumable(orphanedRideId)))

        // The rider's ride is untouched, and the stale one is closed out rather than left a
        // phantom row.
        //
        // Asserted against the *orphan's* id rather than one captured before the send: a fresh
        // ride's `rideId` starts as a placeholder that `activeRide(.task)` replaces with the
        // deterministic `@Dependency(\.uuid)` value (`ActiveRideFeature.State.rideId`), so a
        // captured id goes stale for reasons that have nothing to do with this bug. Replacement
        // is what the test is actually about, and only the orphan could have done it.
        #expect(store.state.activeRide != nil)
        #expect(store.state.activeRide?.rideId != orphanedRideId)
        #expect(finalized.value == [orphanedRideId])

        await store.finish()
        // Still exactly one release: the sheet was already gone, so nothing was released twice.
        #expect(log.value == Self.begun + Self.ended)
    }

    /// A double tap on Start Ride before the sheet covers the button. The second must not take a scan
    /// the one dismissal cannot release, nor replace the sheet the first opened.
    @Test("A second Start Ride while the sheet is up takes no second scan")
    func secondStartRideWhileTheSheetIsUpIsIgnored() async {
        let log = LockIsolated<[ScanCall]>([])
        let store = Self.makeStore(into: log)
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.startRideButtonTapped)
        await store.send(.startRideButtonTapped)
        await store.send(.startSheet(.dismiss))
        await store.finish()

        #expect(log.value == Self.begun + Self.ended)
    }
}
