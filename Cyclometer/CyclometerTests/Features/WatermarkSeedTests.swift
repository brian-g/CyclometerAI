import Foundation
import Testing
import ComposableArchitecture
@testable import Cyclometer

/// The dashboard's chart series after an app kill. They are kept in memory only, so a resumed ride
/// rebuilds them from its saved track; without that, the 2026-11-03 ride's W2 covered only the
/// minutes since the relaunch. All of them at once, because they share one time window.
@MainActor
@Suite("Chart history from a resumed ride's saved track")
struct WatermarkSeedTests {
    private static let resumedAt = Date(timeIntervalSince1970: 1_000_000)
    private static let rideId = UUID()

    private static func point(
        _ secondsBeforeResume: TimeInterval, speed: Double?,
        cadence: Int? = nil, heartRate: Int? = nil, altitude: Double? = nil
    ) -> TrackPointDTO {
        TrackPointDTO(
            rideId: rideId, timestamp: time(secondsBeforeResume),
            latitude: 36.08, longitude: -79.54, altitudeMeters: altitude, horizontalAccuracyMeters: 5,
            speedMPS: speed, speedSource: .gps, heartRateBPM: heartRate,
            heartRateSource: heartRate == nil ? .none : .bleHR,
            cadenceRPM: cadence, powerWatts: nil
        )
    }

    private static func time(_ secondsBeforeResume: TimeInterval) -> Date {
        resumedAt.addingTimeInterval(-secondsBeforeResume)
    }

    private static func sample(_ secondsBeforeResume: TimeInterval, _ mps: Double) -> SpeedSample {
        SpeedSample(time: time(secondsBeforeResume), mps: mps)
    }

    @Test("The average is replayed as the tick computes it: distance over moving seconds")
    func averageReplaysTheTick() throws {
        let seed = try #require(WatermarkSeed(savedTrack: [
            Self.point(4, speed: 4),
            Self.point(3, speed: 8),
            Self.point(2, speed: 0.2),  // stationary: no distance, no moving second, no average sample
            Self.point(1, speed: 6),
        ], resumedAt: Self.resumedAt))

        #expect(seed.averageSpeed == [Self.sample(4, 4), Self.sample(3, 6), Self.sample(1, 6)])
        // The watermark is the speed itself, stops included.
        #expect(seed.speed == [Self.sample(4, 4), Self.sample(3, 8), Self.sample(2, 0.2), Self.sample(1, 6)])
    }

    @Test("Cadence, heart rate and altitude come back as their live series keep them")
    func otherSeriesFollowTheirLiveRules() throws {
        let seed = try #require(WatermarkSeed(savedTrack: [
            Self.point(3, speed: 5, cadence: 85, heartRate: 140, altitude: 190),
            // Coasting: cadence 0 is a reading; heart rate 0 is no reading, as the live series drops it.
            Self.point(2, speed: 6, cadence: 0, heartRate: 0, altitude: nil),
            Self.point(1, speed: 6, cadence: nil, heartRate: nil, altitude: 191),
        ], resumedAt: Self.resumedAt))

        #expect(seed.cadence == [CadenceSample(time: Self.time(3), rpm: 85), CadenceSample(time: Self.time(2), rpm: 0)])
        #expect(seed.heartRate == [HeartRateSample(time: Self.time(3), bpm: 140)])
        #expect(seed.altitude == [AltitudeSample(time: Self.time(3), meters: 190), AltitudeSample(time: Self.time(1), meters: 191)])
    }

    @Test("Only the last history window comes back, but the average counts the whole ride")
    func windowCutsTheSamplesNotTheAverage() throws {
        let window = SpeedFeature.historyWindow
        let seed = try #require(WatermarkSeed(savedTrack: [
            Self.point(window + 10, speed: 2, cadence: 70, heartRate: 120, altitude: 180),
            Self.point(10, speed: 10, cadence: 90, heartRate: 150, altitude: 200),
        ], resumedAt: Self.resumedAt))

        #expect(seed.speed == [Self.sample(10, 10)])
        #expect(seed.averageSpeed == [Self.sample(10, 6)])
        #expect(seed.cadence == [CadenceSample(time: Self.time(10), rpm: 90)])
        #expect(seed.heartRate == [HeartRateSample(time: Self.time(10), bpm: 150)])
        #expect(seed.altitude == [AltitudeSample(time: Self.time(10), meters: 200)])
    }

    @Test("Points from after the resume are left to the live series")
    func pointsAfterTheResumeAreSkipped() throws {
        let seed = try #require(WatermarkSeed(savedTrack: [
            Self.point(5, speed: 5),
            Self.point(0, speed: 9, cadence: 90),
            Self.point(-5, speed: 9, heartRate: 150),
        ], resumedAt: Self.resumedAt))

        #expect(seed.speed == [Self.sample(5, 5)])
        #expect(seed.averageSpeed == [Self.sample(5, 5)])
        #expect(seed.cadence.isEmpty)
        #expect(seed.heartRate.isEmpty)
    }

    @Test("A track with no readings gives no seed")
    func noReadingsNoSeed() {
        #expect(WatermarkSeed(savedTrack: [], resumedAt: Self.resumedAt) == nil)
        #expect(WatermarkSeed(savedTrack: [Self.point(3, speed: nil)], resumedAt: Self.resumedAt) == nil)
    }

    @Test("A resumed ride gets every series back, in front of what was sampled since the resume")
    func resumeSeedsEverySeriesInFront() async {
        let persisted = RideSummaryUpdate(
            rideId: Self.rideId, recordingState: .active, durationSeconds: 600, distanceMeters: 4000,
            averageSpeedMPS: 6, maxSpeedMPS: 12, averageHeartRateBPM: nil, maxHeartRateBPM: nil,
            averageCadenceRPM: nil, maxCadenceRPM: nil, vehiclePassCount: 0
        )
        let track = [
            Self.point(20, speed: 4, cadence: 80, heartRate: 130, altitude: 190),
            Self.point(10, speed: 8, cadence: 90, heartRate: 140, altitude: 192),
        ]
        // Sampled after the resume, before the saved track's fetch came back.
        let liveTime = Self.resumedAt.addingTimeInterval(1)
        var state = ActiveRideFeature.State(resuming: persisted)
        state.speed.speedSamples = [SpeedSample(time: liveTime, mps: 7)]
        state.averageSpeedSamples = [SpeedSample(time: liveTime, mps: 6.5)]
        state.cadence.cadenceSamples = [CadenceSample(time: liveTime, rpm: 88)]
        state.hrSamples = [HeartRateSample(time: liveTime, bpm: 145)]
        state.altitudeSamples = [AltitudeSample(time: liveTime, meters: 193)]
        let store = TestStore(initialState: state) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(Self.resumedAt)
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = .mock(trackPoints: [Self.rideId: track])
        }
        // About the chart series, not the effects every resume fans out.
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.watermarksSeeded)
        #expect(store.state.speed.speedSamples == [Self.sample(20, 4), Self.sample(10, 8), SpeedSample(time: liveTime, mps: 7)])
        #expect(store.state.averageSpeedSamples == [Self.sample(20, 4), Self.sample(10, 6), SpeedSample(time: liveTime, mps: 6.5)])
        #expect(store.state.cadence.cadenceSamples.map(\.rpm) == [80, 90, 88])
        #expect(store.state.hrSamples.map(\.bpm) == [130, 140, 145])
        #expect(store.state.altitudeSamples.map(\.meters) == [190, 192, 193])
        // The point of seeding them together: one window, starting at the saved track's first point.
        #expect(store.state.watermarkWindow?.lowerBound == Self.time(20))
        await store.skipInFlightEffects(strict: false)
    }
}
