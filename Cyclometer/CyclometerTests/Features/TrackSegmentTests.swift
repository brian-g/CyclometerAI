import Foundation
import Testing
import ComposableArchitecture
@testable import Cyclometer

/// #263 — a pause is a break in the recorded track, not a straight line across it.
///
/// The reducer half: that a resume opens a new segment, that the points recorded after
/// one carry its index, and that the index survives the app being killed mid-ride. The
/// exported half is `GPXExporterTests`' "Track segments" section.
@MainActor
@Suite("Track segments across a pause")
struct TrackSegmentTests {
    private static let segmentTestDate = Date(timeIntervalSince1970: 1_000_000)

    private static func update(
        latitude: Double, longitude: Double, speed: Double = 8.0
    ) -> LocationUpdate {
        LocationUpdate(
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            altitude: 280.0,
            speed: speed,
            horizontalAccuracy: 5.0,
            heading: 0,
            timestamp: segmentTestDate
        )
    }

    private func makeStore(
        _ state: ActiveRideFeature.State
    ) -> TestStoreOf<ActiveRideFeature> {
        let store = TestStore(initialState: state) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(Self.segmentTestDate)
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = .testValue
        }
        // These tests are about the track, not about the effects every pause and resume
        // already fans out — `ActiveRideFeatureTests` asserts those exhaustively.
        store.exhaustivity = .off
        return store
    }

    @Test("A manual resume opens a new segment rather than extending the last one")
    func manualResumeOpensANewSegment() async {
        let store = makeStore(ActiveRideFeature.State(recordingState: .active))
        await store.send(.locationUpdated(Self.update(latitude: 36.0909331, longitude: -79.5237360)))
        await store.send(.pauseTapped)
        await store.send(.resumeTapped)
        // 338 m from the last point, 26½ minutes later — the ride of 2026-09-20.
        await store.send(.locationUpdated(Self.update(latitude: 36.0939602, longitude: -79.5233471)))

        #expect(store.state.trackSegmentIndex == 1)
        #expect(store.state.trackSegments.count == 2)
        #expect(store.state.trackSegments[0].map(\.latitude) == [36.0909331])
        #expect(store.state.trackSegments[1].map(\.latitude) == [36.0939602])
    }

    @Test("An auto-resume opens a new segment too — the bike stood at the light either way")
    func autoResumeOpensANewSegment() async {
        var state = ActiveRideFeature.State(recordingState: .paused)
        state.isAutoPaused = true
        let store = makeStore(state)

        await store.send(.speed(.gpsSpeedReceived(ActiveRideFeature.movingSpeedMPS)))

        #expect(store.state.recordingState == .active)
        #expect(store.state.trackSegmentIndex == 1)
        #expect(store.state.trackSegments.count == 2)
    }

    @Test("A ride that is never paused stays on one segment")
    func unpausedRideStaysOnOneSegment() async {
        let store = makeStore(ActiveRideFeature.State(recordingState: .active))
        await store.send(.locationUpdated(Self.update(latitude: 36.0909331, longitude: -79.5237360)))
        await store.send(.locationUpdated(Self.update(latitude: 36.0909400, longitude: -79.5237100)))

        #expect(store.state.trackSegmentIndex == 0)
        #expect(store.state.trackSegments.count == 1)
        #expect(store.state.trackSegments[0].count == 2)
    }

    @Test("Track points recorded after a resume are stamped with the new segment")
    func recordedPointsCarryTheSegmentIndex() async {
        let store = makeStore(ActiveRideFeature.State(recordingState: .active))
        await store.send(.locationUpdated(Self.update(latitude: 36.0909331, longitude: -79.5237360)))

        // The `.timerTick` payload is exactly what `TrackPointRecorderFeature` buffers and
        // flushes, so this is the value that reaches CoreData and then the export.
        await store.send(.elapsedTick)
        let beforePause = await Self.recordedPoint(from: store)

        await store.send(.pauseTapped)
        await store.send(.resumeTapped)
        await store.send(.locationUpdated(Self.update(latitude: 36.0939602, longitude: -79.5233471)))
        await store.send(.elapsedTick)
        let afterResume = await Self.recordedPoint(from: store)

        #expect(beforePause?.segmentIndex == 0)
        #expect(afterResume?.segmentIndex == 1)
    }

    /// Receives the next `.trackRecorder(.timerTick)` and hands back the point it carried —
    /// matching on the case rather than on an expected value, since `TrackPointDTO.id` is a
    /// fresh UUID per point and no equality assertion could name it.
    private static func recordedPoint(
        from store: TestStoreOf<ActiveRideFeature>
    ) async -> TrackPointDTO? {
        let captured = LockIsolated<TrackPointDTO?>(nil)
        await store.receive {
            guard case .trackRecorder(.timerTick(let point)) = $0 else { return false }
            captured.setValue(point)
            return true
        }
        return captured.value
    }

    private static func persistedRide(recordingState: Ride.RecordingState) -> RideSummaryUpdate {
        RideSummaryUpdate(
            rideId: UUID(),
            recordingState: recordingState,
            durationSeconds: 600,
            distanceMeters: 4000,
            averageSpeedMPS: 6,
            maxSpeedMPS: 12,
            averageHeartRateBPM: nil,
            maxHeartRateBPM: nil,
            averageCadenceRPM: nil,
            maxCadenceRPM: nil,
            vehiclePassCount: 0
        )
    }

    @Test("A ride killed while recording comes back in a new segment, not the one it died in")
    func aKillWhileActiveOpensANewSegment() async {
        var persisted = Self.persistedRide(recordingState: .active)
        persisted.trackSegmentIndex = 2
        let restored = ActiveRideFeature.State(resuming: persisted)

        // 3, not 2. Nothing was recorded while the app was dead, so the points from here
        // do not belong to the stretch that was being recorded when it died — joining them
        // would draw a chord across however far the rider got in the meantime.
        #expect(restored.recordingState == .active)
        #expect(restored.trackSegmentIndex == 3)

        let store = makeStore(restored)
        await store.send(.locationUpdated(Self.update(latitude: 36.0939602, longitude: -79.5233471)))
        await store.send(.elapsedTick)
        let recorded = await Self.recordedPoint(from: store)

        #expect(recorded?.segmentIndex == 3)
    }

    @Test("A resume after an app kill continues the numbering instead of restarting it")
    func resumeAfterAKillDoesNotMergeSegments() async {
        var persisted = Self.persistedRide(recordingState: .paused)
        persisted.trackSegmentIndex = 2

        let restored = ActiveRideFeature.State(resuming: persisted)
        // Unbumped, unlike the `.active` case above: a paused ride records nothing until
        // the resume below, which opens its own segment.
        #expect(restored.trackSegmentIndex == 2)

        let store = makeStore(restored)
        await store.send(.resumeTapped)

        // 3, not 1: the two stretches the rider already recorded keep their own indices,
        // so the export still splits them instead of folding this one back into the first.
        #expect(store.state.trackSegmentIndex == 3)
    }

    @Test("The checkpoint a resume writes already carries the new segment index")
    func theResumeCheckpointCarriesTheNewIndex() async {
        let written = LockIsolated<RideSummaryUpdate?>(nil)
        let store = TestStore(
            initialState: ActiveRideFeature.State(recordingState: .paused)
        ) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(Self.segmentTestDate)
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = .mock(onUpdateRideSummary: { written.setValue($0) })
        }
        store.exhaustivity = .off

        await store.send(.resumeTapped)
        await store.finish()

        #expect(written.value?.trackSegmentIndex == 1)
    }
}
