import Foundation
import Testing
import ComposableArchitecture
@testable import Cyclometer

/// W2's speed watermark and average line after an app kill. Both are kept in memory only, so a
/// resumed ride rebuilds them from its saved track; without that, the 2026-11-03 ride's chart
/// covered only the minutes since the relaunch.
@MainActor
@Suite("Speed history from a resumed ride's saved track")
struct SpeedHistorySeedTests {
    private static let resumedAt = Date(timeIntervalSince1970: 1_000_000)
    private static let rideId = UUID()

    private static func point(_ secondsBeforeResume: TimeInterval, speed: Double?) -> TrackPointDTO {
        TrackPointDTO(
            rideId: rideId, timestamp: resumedAt.addingTimeInterval(-secondsBeforeResume),
            latitude: 36.08, longitude: -79.54, altitudeMeters: nil, horizontalAccuracyMeters: 5,
            speedMPS: speed, speedSource: .gps, heartRateBPM: nil, heartRateSource: .none,
            cadenceRPM: nil, powerWatts: nil
        )
    }

    private static func sample(_ secondsBeforeResume: TimeInterval, _ mps: Double) -> SpeedSample {
        SpeedSample(time: resumedAt.addingTimeInterval(-secondsBeforeResume), mps: mps)
    }

    @Test("The average is replayed as the tick computes it: distance over moving seconds")
    func averageReplaysTheTick() throws {
        let seed = try #require(SpeedHistorySeed(savedTrack: [
            Self.point(4, speed: 4),
            Self.point(3, speed: 8),
            Self.point(2, speed: 0.2),  // stationary: no distance, no moving second, no average sample
            Self.point(1, speed: 6),
        ], resumedAt: Self.resumedAt))

        #expect(seed.average == [Self.sample(4, 4), Self.sample(3, 6), Self.sample(1, 6)])
        // The watermark is the speed itself, stops included.
        #expect(seed.speed == [Self.sample(4, 4), Self.sample(3, 8), Self.sample(2, 0.2), Self.sample(1, 6)])
    }

    @Test("Only the last history window comes back, but the average counts the whole ride")
    func windowCutsTheSamplesNotTheAverage() throws {
        let window = SpeedFeature.historyWindow
        let seed = try #require(SpeedHistorySeed(savedTrack: [
            Self.point(window + 10, speed: 2),
            Self.point(10, speed: 10),
        ], resumedAt: Self.resumedAt))

        #expect(seed.speed == [Self.sample(10, 10)])
        #expect(seed.average == [Self.sample(10, 6)])
    }

    @Test("Points from after the resume are left to the live series")
    func pointsAfterTheResumeAreSkipped() throws {
        let seed = try #require(SpeedHistorySeed(savedTrack: [
            Self.point(5, speed: 5),
            Self.point(0, speed: 9),
            Self.point(-5, speed: 9),
        ], resumedAt: Self.resumedAt))

        #expect(seed.speed == [Self.sample(5, 5)])
        #expect(seed.average == [Self.sample(5, 5)])
    }

    @Test("A track with no speeds gives no seed")
    func noSpeedsNoSeed() {
        #expect(SpeedHistorySeed(savedTrack: [], resumedAt: Self.resumedAt) == nil)
        #expect(SpeedHistorySeed(savedTrack: [Self.point(3, speed: nil)], resumedAt: Self.resumedAt) == nil)
    }

    @Test("A resumed ride gets both series back, in front of what was sampled since the resume")
    func resumeSeedsBothSeriesInFront() async {
        let persisted = RideSummaryUpdate(
            rideId: Self.rideId, recordingState: .active, durationSeconds: 600, distanceMeters: 4000,
            averageSpeedMPS: 6, maxSpeedMPS: 12, averageHeartRateBPM: nil, maxHeartRateBPM: nil,
            averageCadenceRPM: nil, maxCadenceRPM: nil, vehiclePassCount: 0
        )
        let track = [Self.point(20, speed: 4), Self.point(10, speed: 8)]
        // Sampled after the resume, before the saved track's fetch came back.
        let live = SpeedSample(time: Self.resumedAt.addingTimeInterval(1), mps: 7)
        var state = ActiveRideFeature.State(resuming: persisted)
        state.speed.speedSamples = [live]
        state.averageSpeedSamples = [live]
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
        // About the two series, not the effects every resume fans out.
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.speedHistorySeeded)
        #expect(store.state.speed.speedSamples == [Self.sample(20, 4), Self.sample(10, 8), live])
        #expect(store.state.averageSpeedSamples == [Self.sample(20, 4), Self.sample(10, 6), live])
        await store.skipInFlightEffects(strict: false)
    }
}
