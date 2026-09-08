import Foundation
import Testing

@testable import Cyclometer

/// `admit` is `mutating`, and `#expect` expands its expression into a closure that captures
/// immutably — so every call is hoisted into a `let` and the macro only ever sees a `Bool`.
@Suite("LogSampleGate")
struct LogSampleGateTests {
    @Test("The first sample is always admitted")
    func firstSampleAdmitted() {
        var gate = LogSampleGate()
        let first = gate.admit(uptime: 1234.5)
        #expect(first)
    }

    @Test("A second sample inside the same bucket is suppressed")
    func secondSampleInSameBucketSuppressed() {
        var gate = LogSampleGate()
        let admitted = [10.0, 10.4, 10.99].map { gate.admit(uptime: $0) }
        #expect(admitted == [true, false, false])
    }

    @Test("Crossing a bucket boundary admits again")
    func boundaryAdmits() {
        var gate = LogSampleGate()
        let admitted = [10.9, 11.0].map { gate.admit(uptime: $0) }
        #expect(admitted == [true, true])
    }

    /// The reason for bucketing rather than measuring the interval since the last admitted
    /// line. A CSC sensor or HR strap nominally at 1 Hz drifts either side of a one-second
    /// spacing. A gate demanding a full second since the last emission rejects every sample
    /// that arrives early — on this sequence it emits at 0.5, 2.55, 4.6, 6.45 and 8.5 and
    /// drops the other five, halving the telemetry the ride is being logged for. Bucketing
    /// admits all ten, because each lands in a second of its own.
    @Test("A jittering 1 Hz stream is not halved")
    func jitteringOneHertzStreamSurvives() {
        var gate = LogSampleGate()
        let jitter = [0.5, 1.45, 2.55, 3.5, 4.6, 5.5, 6.45, 7.55, 8.5, 9.6]
        let admitted = jitter.map { gate.admit(uptime: $0) }
        #expect(admitted.allSatisfy { $0 })
    }

    /// The guarantee is one line per bucket, not one line per sample: a sensor running
    /// faster than the bucket still loses samples, which is the entire point.
    @Test("Two samples inside one second still yield one line")
    func twoSamplesInOneSecondYieldOneLine() {
        var gate = LogSampleGate()
        let admitted = [0.02, 0.98, 1.05].map { gate.admit(uptime: $0) }
        #expect(admitted == [true, false, true])
    }

    @Test("A 4 Hz sensor is cut to one line a second")
    func fastSensorIsThrottled() {
        var gate = LogSampleGate()
        let admitted = stride(from: 0.0, to: 10.0, by: 0.25).map { gate.admit(uptime: $0) }
        #expect(admitted.count == 40)
        #expect(admitted.filter { $0 }.count == 10)
    }

    @Test("A 60s bucket admits once a minute — the radar liveness summary")
    func minuteBucket() {
        var gate = LogSampleGate(bucketSeconds: 60)
        let admitted = [0.0, 30.0, 59.9, 60.0, 119.0, 120.0].map { gate.admit(uptime: $0) }
        #expect(admitted == [true, false, false, true, false, true])
    }

    /// Bucketing compares bucket identity, not ordering, so a clock that moves backwards
    /// admits rather than locking the gate shut until it catches up.
    @Test("A backwards clock jump admits rather than stalling the gate")
    func backwardsJumpAdmits() {
        var gate = LogSampleGate()
        let admitted = [100.0, 40.0, 40.5].map { gate.admit(uptime: $0) }
        #expect(admitted == [true, true, false])
    }
}

@Suite("Data.loggableHex")
struct LoggableHexTests {
    @Test("Bytes render as space-separated uppercase pairs")
    func rendersUppercasePairs() {
        #expect(Data([0x00, 0x0A, 0xFF, 0x82]).loggableHex == "00 0A FF 82")
    }

    @Test("An empty payload renders as an empty string")
    func emptyIsEmpty() {
        #expect(Data().loggableHex.isEmpty)
    }
}
