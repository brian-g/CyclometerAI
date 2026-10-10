import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// #387: the barometer is the ride's altitude where there is one, and ascent, descent and grade
/// accumulate once a recorded second.
@MainActor
@Suite("ActiveRideFeature — elevation")
struct ActiveRideElevationTests {

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static let gpsFix = LocationUpdate(
        coordinate: Coordinate(latitude: 43.0731, longitude: -89.4012),
        altitude: 280,
        verticalAccuracy: 6,
        speed: 10,
        horizontalAccuracy: 5,
        heading: 192,
        timestamp: now
    )

    private func makeStore(
        _ state: ActiveRideFeature.State = ActiveRideFeature.State(recordingState: .active),
        persistenceClient: PersistenceClient = .testValue
    ) -> TestStoreOf<ActiveRideFeature> {
        let store = TestStore(initialState: state) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(Self.now)
            $0.uuid = .incrementing
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = persistenceClient
        }
        store.exhaustivity = .off
        return store
    }

    @Test("the barometer's altitude is the one shown, sampled and recorded — not GPS's")
    func barometerIsRecorded() async {
        let store = makeStore()

        await store.send(.trackRecorder(.startRecording))
        await store.send(.altimeterReading(.absolute(meters: 274.5, accuracy: 2)))
        await store.send(.locationUpdated(Self.gpsFix))
        #expect(store.state.altitude == 274.5)
        await store.send(.elapsedTick)
        await store.skipInFlightEffects(strict: false)

        #expect(store.state.altitudeSamples == [AltitudeSample(time: Self.now, meters: 274.5)])
        let recorded = await store.dependencies.rideDataBuffer.drainForFlush()
        #expect(recorded.map(\.altitudeMeters) == [274.5])
    }

    @Test("when the altimeter stream ends, GPS altitude takes over")
    func altimeterEndHandsBackToGPS() async {
        let store = makeStore()

        await store.send(.altimeterReading(.absolute(meters: 274.5, accuracy: 2)))
        await store.send(.altimeterEnded)
        await store.send(.locationUpdated(Self.gpsFix))

        #expect(store.state.altitude == 280)
        #expect(store.state.altitudeResolver.source == .gps)
    }

    @Test("ascent and grade build up over recorded seconds, and not while paused")
    func ascentAndGradeAccumulate() async throws {
        var state = ActiveRideFeature.State(recordingState: .active)
        state.speed = SpeedFeature.State(speedMPS: 10, activeSpeedSource: .gps)
        let store = makeStore(state)

        // 10 m a second, 0.5 m up a second: a 5% climb, for 120 m.
        for second in 0...12 {
            await store.send(.altimeterReading(.absolute(meters: 200 + Double(second) * 0.5, accuracy: 1)))
            await store.send(.elapsedTick)
        }
        #expect(store.state.elevation.ascentMeters == 6)
        #expect(abs(try #require(store.state.elevation.gradePercent) - 5) < 1e-9)

        await store.send(.pauseTapped)
        await store.send(.altimeterReading(.absolute(meters: 230, accuracy: 1)))
        await store.send(.elapsedTick)
        #expect(store.state.elevation.ascentMeters == 6)
        await store.skipInFlightEffects(strict: false)
    }

    @Test("a resumed ride's ascent and descent pick up from its saved track")
    func resumeSeedsFromTheSavedTrack() async {
        let rideId = UUID()
        let summary = RideSummaryUpdate(
            rideId: rideId, recordingState: .active,
            durationSeconds: 600, distanceMeters: 4_000, averageSpeedMPS: 6.5, maxSpeedMPS: 11
        )
        let saved = [250.0, 262, 255, 300].map { altitude in
            TrackPointDTO(
                rideId: rideId, timestamp: Self.now, latitude: 43, longitude: -89, altitudeMeters: altitude,
                horizontalAccuracyMeters: 5, speedMPS: 6, speedSource: .gps, heartRateBPM: nil,
                heartRateSource: .none, cadenceRPM: nil, powerWatts: nil
            )
        }
        let store = makeStore(
            ActiveRideFeature.State(resuming: summary),
            persistenceClient: .mock(trackPoints: [rideId: saved])
        )

        await store.send(.task)
        await store.receive(\.elevationSeeded)
        await store.skipInFlightEffects(strict: false)

        #expect(store.state.elevation.ascentMeters == 12 + 45)
        #expect(store.state.elevation.descentMeters == 7)
        #expect(store.state.elevation.highestMeters == 300)
    }
}
