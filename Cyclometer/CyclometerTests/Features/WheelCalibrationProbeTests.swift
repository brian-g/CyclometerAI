import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

/// #419's instrumentation: the window's positional distance, measured over exactly the
/// intervals whose Doppler distance the window counts, and the revolutions that entered
/// the window with no GPS interval to pair with.
///
/// An extension of `WheelCalibrationFeatureTests` rather than a suite of its own, so these
/// run inside that suite's `.serialized` trait: they write `@Shared(.appPreferences)` too.
/// The coordinates are synthetic.
extension WheelCalibrationFeatureTests {

    private static let probeStart = Date(timeIntervalSince1970: 2_000_000)
    private static let probeStoredMM = 2096
    private static let origin = RouteCoordinate(latitude: 45.0, longitude: 7.0, elevationMeters: nil)

    private func makeProbeStore(bleCSCClient: BLECSCClient = .testValue) -> TestStoreOf<WheelCalibrationFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.wheelCircumferenceMM = Self.probeStoredMM }
            return TestStore(initialState: WheelCalibrationFeature.State()) {
                WheelCalibrationFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
                $0.continuousClock = ImmediateClock()
                $0.date = .constant(Self.probeStart)
                $0.bleCSCClient = bleCSCClient
            }
        }
    }

    /// A curve whose corner tightens: each 1 s step turns a degree more than the last, on a
    /// 60 m radius, so every interval has its own length. A straight line would let a probe
    /// that measured the wrong interval still pass.
    private func curve(points: Int) -> [Coordinate] {
        var angle = 0.0
        return (0..<points).map { i in
            angle += Double(6 + i) * .pi / 180
            let c = RouteGeometry.coordinate(
                offsetFrom: Self.origin, north: 60 * cos(angle), east: 60 * sin(angle)
            )
            return Coordinate(latitude: c.latitude, longitude: c.longitude)
        }
    }

    private func meters(_ a: Coordinate, _ b: Coordinate) -> Double {
        RouteGeometry.distanceMeters([
            RouteCoordinate(latitude: a.latitude, longitude: a.longitude, elevationMeters: nil),
            RouteCoordinate(latitude: b.latitude, longitude: b.longitude, elevationMeters: nil),
        ])
    }

    private func probeFix(
        _ coordinate: Coordinate, at offset: TimeInterval, speed: Double, accuracy: Double = 5
    ) -> LocationUpdate {
        LocationUpdate(
            coordinate: coordinate,
            altitude: 30,
            speed: speed,
            horizontalAccuracy: accuracy,
            heading: 90,
            timestamp: Self.probeStart.addingTimeInterval(offset)
        )
    }

    /// Rides `path` at 1 Hz with a revolution delta before each fix. Each fix's Doppler
    /// speed is the length of the interval it closes, so the Doppler integral and the
    /// positional distance agree exactly when, and only when, they cover the same
    /// intervals. `rejecting` names fix indices sent with 12 m accuracy.
    private func ride(
        _ store: TestStoreOf<WheelCalibrationFeature>,
        _ path: [Coordinate],
        revolutionsPerSecond: Double = 2.5,
        rejecting rejected: Set<Int> = []
    ) async {
        for (i, coordinate) in path.enumerated() {
            if i > 0 { await store.send(.wheelRevolutionsReceived(revolutionsPerSecond)) }
            let speed = i > 0 ? meters(path[i - 1], coordinate) : 5
            await store.send(.locationUpdated(probeFix(
                coordinate, at: TimeInterval(i), speed: speed, accuracy: rejected.contains(i) ? 12 : 5
            )))
        }
    }

    @Test("The probe's positional distance is RouteGeometry's, over the Doppler side's intervals, on a curve")
    func probePositionalMatchesRouteGeometryOnACurve() async {
        let store = makeProbeStore()
        store.exhaustivity = .off
        await store.send(.bleConnectionChanged(.active))

        let path = curve(points: 20)
        await ride(store, path)

        let expected = zip(path, path.dropFirst()).reduce(0) { $0 + meters($1.0, $1.1) }
        let probe = store.state.probe
        #expect(abs(probe.positionalMeters - expected) < 1e-9)
        #expect(abs(store.state.gpsMeters - expected) < 1e-9)
        #expect(probe.usedIntervals == path.count - 1)
        #expect(probe.integratedSeconds == TimeInterval(path.count - 1))
        #expect(probe.rejectedFixes == 0)
        #expect(probe.unpairedRevolutionsAtGPSGate == 0)
        // The curve is real: the chord across it is well short of the distance along it.
        #expect(meters(path[0], path[path.count - 1]) < expected * 0.8)
    }

    @Test("A rejected fix drops the same intervals from the Doppler and positional sides")
    func probeRejectedIntervalDroppedFromBoth() async {
        let store = makeProbeStore()
        store.exhaustivity = .off
        await store.send(.bleConnectionChanged(.active))

        let path = curve(points: 20)
        let rejected = 8
        await ride(store, path, revolutionsPerSecond: 2.5, rejecting: [rejected])

        // Lost: the interval into the rejected fix, and the one out of it (the next fix
        // only re-seeds).
        let expected = zip(path, path.dropFirst()).enumerated()
            .filter { $0.offset != rejected - 1 && $0.offset != rejected }
            .reduce(0) { $0 + meters($1.element.0, $1.element.1) }
        let probe = store.state.probe
        #expect(abs(probe.positionalMeters - expected) < 1e-9)
        #expect(abs(store.state.gpsMeters - expected) < 1e-9)
        #expect(probe.usedIntervals == path.count - 3)
        #expect(probe.rejectedFixes == 1)
        #expect(probe.gpsGateShuts == 1)
        #expect(probe.skippedFixes == 2)   // the first fix's seed, and the re-seed after the rejection

        // The asymmetry #419 names, pinned as the code behaves today: the revolutions of
        // the interval the GPS gate rejected stay in the window. The gate decides only
        // when the next fix lands, after those revolutions have been counted.
        #expect(probe.unpairedRevolutionsAtGPSGate == 2.5)
        #expect(store.state.revolutions == 2.5 * Double(path.count - 1 - 1))
    }

    /// What a window decided, field by field — everything but the probe.
    private struct Decisions: Equatable {
        var commitCount: Int
        var storedMM: Int
        var pushedMM: [Int]
        var pendingMeasurements: [Double]
        var pendingOverReading: Bool?
        var gpsMeters: Double
        var revolutions: Double
        var lastFixTimestamp: Date?
        var lastCalibrationAt: Date?
    }

    /// Two windows at a 6% over-read against the stored 2096 mm (enough to commit), with
    /// the fixes' coordinates `stepMeters` apart against a 10 m/s Doppler speed. Returns
    /// what was decided, and the probe's positional distance one fix before the second
    /// window closed.
    private func rideTwoWindows(stepMeters: Double) async -> (Decisions, Double) {
        let pushed = LockIsolated<[Int]>([])
        var ble = BLECSCClient.testValue
        ble.setWheelCircumference = { mm in pushed.withValue { $0.append(mm) } }
        let store = makeProbeStore(bleCSCClient: ble)
        store.exhaustivity = .off
        await store.send(.bleConnectionChanged(.active))

        let seconds = Int(WheelCalibration.windowThresholdMeters / 10)
        let rate = WheelCalibration.windowThresholdMeters * 1.06 * 1000
            / Double(Self.probeStoredMM) / Double(seconds)
        var positionalBeforeClose = 0.0
        for i in 0...(2 * seconds) {
            let c = RouteGeometry.coordinate(offsetFrom: Self.origin, north: stepMeters * Double(i), east: 0)
            if i > 0 { await store.send(.wheelRevolutionsReceived(rate)) }
            await store.send(.locationUpdated(probeFix(
                Coordinate(latitude: c.latitude, longitude: c.longitude), at: TimeInterval(i), speed: 10
            )))
            if i == 2 * seconds - 1 { positionalBeforeClose = store.state.probe.positionalMeters }
        }
        await store.finish(timeout: effectDrainTimeout)
        let s = store.state
        return (Decisions(
            commitCount: s.commitCount, storedMM: s.preferences.wheelCircumferenceMM, pushedMM: pushed.value,
            pendingMeasurements: s.pendingMeasurements, pendingOverReading: s.pendingOverReading,
            gpsMeters: s.gpsMeters, revolutions: s.revolutions,
            lastFixTimestamp: s.lastFixTimestamp, lastCalibrationAt: s.lastCalibrationAt
        ), positionalBeforeClose)
    }

    @Test("Window decisions don't depend on the probe: positions 5% long, or standing still, decide the same")
    func probeDoesNotChangeDecisions() async {
        // Run one after the other: each store re-seeds the shared circumference, which is
        // cached process-wide, so interleaving would let the first commit leak into the second.
        let (still, stillPositional) = await rideTwoWindows(stepMeters: 0)
        let (long, longPositional) = await rideTwoWindows(stepMeters: 10.5)

        #expect(stillPositional == 0)
        #expect(abs(longPositional - 149 * 10.5) < 0.01)   // the probe did see the difference
        #expect(still == long)

        // And what was decided is the Doppler measurement's commit.
        let seconds = Double(Int(WheelCalibration.windowThresholdMeters / 10))
        let rate = WheelCalibration.windowThresholdMeters * 1.06 * 1000 / Double(Self.probeStoredMM) / seconds
        let committed = Int((WheelCalibration.windowThresholdMeters * 1000 / (rate * seconds)).rounded())
        #expect(still.commitCount == 1)
        #expect(still.storedMM == committed)
        #expect(still.pushedMM == [committed])
    }

    @Test("The probe resets with the window")
    func probeResetsWithWindow() async {
        let store = makeProbeStore()
        store.exhaustivity = .off
        await store.send(.bleConnectionChanged(.active))
        await ride(store, curve(points: 6))
        #expect(store.state.probe.usedIntervals == 5)

        // Leaving `.active` voids the window, and the probe with it.
        await store.send(.bleConnectionChanged(.reconnecting))
        #expect(store.state.probe.usedIntervals == 0)
        #expect(store.state.probe.positionalMeters == 0)
        #expect(store.state.probe.lastFixCoordinate == nil)
    }

    @Test("The probe's log summary carries its numbers and no coordinates")
    func probeSummaryHasNoCoordinates() {
        var probe = CalibrationWindowProbe()
        let a = Coordinate(latitude: 45.123456, longitude: 7.654321)
        let b = Coordinate(latitude: 45.123546, longitude: 7.654321)   // ~10 m north
        probe.revolutionsCounted(5)
        probe.intervalUsed(from: a, at: Self.probeStart, to: b, at: Self.probeStart.addingTimeInterval(1))
        probe.revolutionsCounted(1)
        probe.fixRejected(gateWasOpen: true)

        let line = probe.summary(dopplerMeters: 9.8, revolutions: 6, storedMM: 2096)
        #expect(line.contains("doppler 9.8 m"))
        #expect(line.contains("positional 10.0 m"))
        #expect(line.contains("doppler/positional \(String(format: "%.4f", 9.8 / meters(a, b)))"))
        #expect(line.contains("unpaired rev 1.0 at gps gate (1 shuts, 1 fixes rejected)"))
        #expect(line.contains("doppler without gps-gate-unpaired rev 1960 mm"))
        #expect(!line.contains("45.1"))
        #expect(!line.contains("7.65"))
    }
}
