import Foundation
import Testing
import ComposableArchitecture
@testable import Cyclometer

/// #537 — every pause is recorded with the ride, for S15's stops.
///
/// Recorded rather than read from the track's `segmentIndex`, which also goes up when a ride
/// killed while recording comes back, where nobody paused (`TrackSegmentTests`).
@MainActor
@Suite("Pause recording")
struct RidePauseRecordingTests {
    private static let start = Date(timeIntervalSince1970: 1_000_000)

    /// The store, and the clock its `date` reads, moved by the test between actions.
    private func makeStore(
        _ state: ActiveRideFeature.State,
        persistenceClient: PersistenceClient = .testValue
    ) -> (TestStoreOf<ActiveRideFeature>, LockIsolated<Date>) {
        let now = LockIsolated(Self.start)
        let store = TestStore(initialState: state) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = DateGenerator { now.value }
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = persistenceClient
        }
        // About the pauses, not the effects a pause and resume fan out, which
        // `ActiveRideFeatureTests` asserts exhaustively.
        store.exhaustivity = .off
        return (store, now)
    }

    private static func persisted(_ recordingState: Ride.RecordingState, pauses: [RidePause]) -> RideSummaryUpdate {
        var summary = RideSummaryUpdate(rideId: UUID(), recordingState: recordingState, durationSeconds: 600,
                                        distanceMeters: 4_000, averageSpeedMPS: 6, maxSpeedMPS: 12)
        summary.pauses = pauses
        return summary
    }

    @Test("Pause opens a manual pause and Resume closes it")
    func manualPauseIsRecorded() async {
        let (store, now) = makeStore(ActiveRideFeature.State(recordingState: .active))
        await store.send(.pauseTapped)
        #expect(store.state.pauses == [RidePause(startedAt: Self.start, endedAt: nil, isAuto: false)])

        now.setValue(Self.start.addingTimeInterval(180))
        await store.send(.resumeTapped)
        #expect(store.state.pauses == [
            RidePause(startedAt: Self.start, endedAt: Self.start.addingTimeInterval(180), isAuto: false),
        ])
    }

    @Test("Auto-pause is recorded as auto, and moving again closes it")
    func autoPauseIsRecorded() async {
        let (store, now) = makeStore(ActiveRideFeature.State(recordingState: .active))
        await store.send(.autoPauseTriggered)
        now.setValue(Self.start.addingTimeInterval(45))
        await store.send(.speed(.gpsSpeedReceived(ActiveRideFeature.movingSpeedMPS)))

        #expect(store.state.recordingState == .active)
        #expect(store.state.pauses == [
            RidePause(startedAt: Self.start, endedAt: Self.start.addingTimeInterval(45), isAuto: true),
        ])
    }

    @Test("Each pause of a ride is kept, in order")
    func everyPauseIsKept() async {
        let (store, now) = makeStore(ActiveRideFeature.State(recordingState: .active))
        await store.send(.pauseTapped)
        now.setValue(Self.start.addingTimeInterval(60))
        await store.send(.resumeTapped)
        now.setValue(Self.start.addingTimeInterval(600))
        await store.send(.autoPauseTriggered)
        now.setValue(Self.start.addingTimeInterval(630))
        await store.send(.resumeTapped)

        #expect(store.state.pauses.map(\.isAuto) == [false, true])
        #expect(store.state.pauses.map(\.startedAt) == [Self.start, Self.start.addingTimeInterval(600)])
        #expect(store.state.pauses.allSatisfy { $0.endedAt != nil })
    }

    @Test("The checkpoint a pause writes carries it open, so a kill while paused keeps it")
    func pauseCheckpointCarriesThePause() async {
        let written = LockIsolated<RideSummaryUpdate?>(nil)
        let (store, _) = makeStore(ActiveRideFeature.State(recordingState: .active),
                                   persistenceClient: .mock(onUpdateRideSummary: { written.setValue($0) }))
        await store.send(.pauseTapped)
        await store.finish()

        #expect(written.value?.pauses == [RidePause(startedAt: Self.start, endedAt: nil, isAuto: false)])
    }

    @Test("A ride killed while paused comes back with its pause open, and Resume closes it")
    func killWhilePausedThenResume() async {
        let open = RidePause(startedAt: Self.start.addingTimeInterval(-300), endedAt: nil, isAuto: true)
        let restored = ActiveRideFeature.State(resuming: Self.persisted(.paused, pauses: [open]))
        #expect(restored.pauses == [open])

        let (store, _) = makeStore(restored)
        await store.send(.resumeTapped)

        #expect(store.state.pauses == [
            RidePause(startedAt: open.startedAt, endedAt: Self.start, isAuto: true),
        ])
    }

    /// The app wasn't running for the gap, so nobody paused: the gap isn't a stop.
    @Test("A ride killed while recording comes back with no pause for the gap")
    func killWhileActiveRecordsNothing() async {
        let earlier = RidePause(startedAt: Self.start.addingTimeInterval(-900),
                                endedAt: Self.start.addingTimeInterval(-840), isAuto: false)
        let restored = ActiveRideFeature.State(resuming: Self.persisted(.active, pauses: [earlier]))

        #expect(restored.recordingState == .active)
        #expect(restored.pauses == [earlier])
    }

    /// Every finish comes from a pause, and that one is the end of the ride, not a stop.
    @Test("A ride finished while paused keeps its last pause open")
    func finishLeavesTheLastPauseOpen() async {
        let (store, _) = makeStore(ActiveRideFeature.State(recordingState: .active))
        await store.send(.pauseTapped)
        await store.send(.finishTapped)

        #expect(store.state.pauses.count == 1)
        #expect(store.state.pauses.last?.endedAt == nil)
    }

    @Test("Opening a pause while one is open, or closing with none open, changes nothing")
    func openAndCloseAreIdempotent() {
        var pauses: [RidePause] = []
        pauses.close(at: Self.start)
        #expect(pauses.isEmpty)

        pauses.open(at: Self.start, isAuto: true)
        pauses.open(at: Self.start.addingTimeInterval(10), isAuto: false)
        #expect(pauses == [RidePause(startedAt: Self.start, endedAt: nil, isAuto: true)])

        pauses.close(at: Self.start.addingTimeInterval(20))
        pauses.close(at: Self.start.addingTimeInterval(30))
        #expect(pauses == [RidePause(startedAt: Self.start, endedAt: Self.start.addingTimeInterval(20), isAuto: true)])
    }
}
