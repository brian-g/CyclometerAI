import Foundation
import Testing
@testable import Cyclometer

/// The gate's thresholds, each tested on both sides (#540). The reducer wiring, with ride-shaped
/// sequences, is in `ActiveRideFeatureTimerTests`.
@Suite("MaxSpeedGate")
struct MaxSpeedGateTests {

    private static let now = Date(timeIntervalSince1970: 1_000_000)

    private static func sample(_ mps: Double, secondsAgo: TimeInterval) -> SpeedSample {
        SpeedSample(time: now.addingTimeInterval(-secondsAgo), mps: mps)
    }

    // MARK: - GPS speedAccuracy

    @Test("A GPS speed CoreLocation marks invalid is never trustworthy")
    func invalidAccuracyIsNotTrustworthy() {
        #expect(!MaxSpeedGate.isTrustworthy(speedAccuracy: nil))
        // `LocationUpdate` turns CoreLocation's −1 into nil; a negative that got through anyway
        // means the same.
        #expect(!MaxSpeedGate.isTrustworthy(speedAccuracy: -1))
    }

    @Test("A GPS speed is trustworthy up to maxGPSSpeedAccuracyMPS, and not past it")
    func accuracyThreshold() {
        #expect(MaxSpeedGate.isTrustworthy(speedAccuracy: 0))
        #expect(MaxSpeedGate.isTrustworthy(speedAccuracy: 0.4))
        #expect(MaxSpeedGate.isTrustworthy(speedAccuracy: MaxSpeedGate.maxGPSSpeedAccuracyMPS))
        #expect(!MaxSpeedGate.isTrustworthy(speedAccuracy: MaxSpeedGate.maxGPSSpeedAccuracyMPS + 0.01))
    }

    // MARK: - Acceleration bound

    @Test("One second after 8 m/s, 14.5 m/s is reachable and anything faster is not")
    func oneSecondBound() {
        let before = [Self.sample(8, secondsAgo: 1)]
        let bound = 8 + MaxSpeedGate.maxAccelerationMPS2 * 1 + MaxSpeedGate.readingSlackMPS
        #expect(bound == 14.5)
        #expect(MaxSpeedGate.isReachable(bound, at: Self.now, priorReadings: before))
        #expect(!MaxSpeedGate.isReachable(bound + 0.01, at: Self.now, priorReadings: before))
    }

    @Test("The bound grows with the time since the reading")
    func boundGrowsWithElapsedTime() {
        let before = [Self.sample(8, secondsAgo: 3)]
        #expect(MaxSpeedGate.isReachable(22.5, at: Self.now, priorReadings: before))
        #expect(!MaxSpeedGate.isReachable(22.51, at: Self.now, priorReadings: before))
    }

    @Test("Every reading of the window constrains, not only the latest")
    func everyReadingConstrains() {
        // A spike's second second: reachable from the spike's first, not from the 8 m/s before it.
        let before = [Self.sample(8, secondsAgo: 2), Self.sample(33, secondsAgo: 1)]
        #expect(!MaxSpeedGate.isReachable(33, at: Self.now, priorReadings: before))
    }

    @Test("A reading at the window's edge still constrains; one older than it doesn't")
    func windowEdge() {
        let window = MaxSpeedGate.window
        let recent = Self.sample(30, secondsAgo: 1)
        // 8 + 4 × 5 + 2.5 = 30.5; the recent 30 m/s allows 31 on its own.
        let atEdge = [Self.sample(8, secondsAgo: window), recent]
        let pastEdge = [Self.sample(8, secondsAgo: window + 0.01), recent]
        #expect(!MaxSpeedGate.isReachable(31, at: Self.now, priorReadings: atEdge))
        #expect(MaxSpeedGate.isReachable(31, at: Self.now, priorReadings: pastEdge))
    }

    @Test("With no reading in the window, a reading can't become the max, however slow")
    func emptyWindow() {
        #expect(MaxSpeedGate.verdict(33, from: .bleWheel, speedAccuracy: nil, at: Self.now, priorReadings: [SpeedSample]()) == .noRecentReading)
        #expect(!MaxSpeedGate.isReachable(5, at: Self.now, priorReadings: [SpeedSample]()))
        // Readings older than the window count as none: the first reading after a 20 s dropout.
        let beforeDropout = [Self.sample(8, secondsAgo: 21), Self.sample(8, secondsAgo: 20)]
        #expect(!MaxSpeedGate.isReachable(8, at: Self.now, priorReadings: beforeDropout))
        // One reading at the edge is enough.
        #expect(MaxSpeedGate.isReachable(8, at: Self.now, priorReadings: [Self.sample(8, secondsAgo: MaxSpeedGate.window)]))
    }

    /// Only a frozen test clock produces one: in the app no two readings share an instant, and a
    /// reading's own sample is never among its prior readings (#540 review).
    @Test("A prior reading at the same instant neither constrains nor counts as a reference")
    func sameInstantIgnored() {
        // If the 8 m/s at the same instant counted, 14 would exceed its 8 + 2.5.
        let samples = [Self.sample(13, secondsAgo: 1), Self.sample(8, secondsAgo: 0)]
        #expect(MaxSpeedGate.isReachable(14, at: Self.now, priorReadings: samples))
        #expect(!MaxSpeedGate.isReachable(14, at: Self.now, priorReadings: [Self.sample(14, secondsAgo: 0)]))
    }

    @Test("A slower reading is always reachable")
    func slowerAlwaysReachable() {
        #expect(MaxSpeedGate.isReachable(3, at: Self.now, priorReadings: [Self.sample(33, secondsAgo: 1)]))
    }

    // MARK: - Both together

    @Test("A wheel-sensor reading has no accuracy, so only the bound applies to it")
    func wheelIgnoresAccuracy() {
        let before = [Self.sample(8, secondsAgo: 1)]
        #expect(MaxSpeedGate.verdict(9, from: .bleWheel, speedAccuracy: nil, at: Self.now, priorReadings: before) == .admitted)
        #expect(MaxSpeedGate.verdict(30, from: .bleWheel, speedAccuracy: nil, at: Self.now, priorReadings: before) != .admitted)
    }

    @Test("A GPS reading needs both: a good accuracy and a reachable speed")
    func gpsNeedsBoth() {
        let before = [Self.sample(8, secondsAgo: 1)]
        #expect(MaxSpeedGate.verdict(9, from: .gps, speedAccuracy: 0.3, at: Self.now, priorReadings: before) == .admitted)
        #expect(MaxSpeedGate.verdict(9, from: .gps, speedAccuracy: nil, at: Self.now, priorReadings: before) != .admitted)
        #expect(MaxSpeedGate.verdict(33, from: .gps, speedAccuracy: 0.3, at: Self.now, priorReadings: before) != .admitted)
    }

    @Test("The verdict names the check that refused")
    func verdictNamesTheCheck() {
        let before = [Self.sample(8, secondsAgo: 1)]
        func verdict(_ mps: Double, _ source: SensorSource, _ accuracy: Double?, _ samples: [SpeedSample]) -> MaxSpeedGate.Verdict {
            MaxSpeedGate.verdict(mps, from: source, speedAccuracy: accuracy, at: Self.now, priorReadings: samples)
        }
        #expect(verdict(9, .gps, 0.3, before) == .admitted)
        #expect(verdict(9, .gps, nil, before) == .untrustworthyGPSAccuracy)
        #expect(verdict(9, .gps, 3, before) == .untrustworthyGPSAccuracy)
        #expect(verdict(33, .bleWheel, nil, before) == .tooFast)
        #expect(verdict(9, .bleWheel, nil, []) == .noRecentReading)
    }
}
