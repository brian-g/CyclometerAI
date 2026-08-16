import Testing
import ComposableArchitecture
import CoreBluetooth
@testable import Cyclometer

private let cscServiceUUID     = CBUUID(string: "1816")
private let cscMeasurementUUID = CBUUID(string: "2A5B")
private let cscFeatureUUID     = CBUUID(string: "2A5C")
private let batteryServiceUUID = CBUUID(string: "180F")
private let batteryLevelUUID   = CBUUID(string: "2A19")

/// Builds a CSC Measurement (0x2A5B) payload. Wheel and/or crank blocks are
/// included based on which arguments are supplied; little-endian per BLE.md §5.2.
private func cscPayload(
    wheelRevs: UInt32? = nil, wheelTime: UInt16? = nil,
    crankRevs: UInt16? = nil, crankTime: UInt16? = nil
) -> Data {
    var flags: UInt8 = 0
    var bytes: [UInt8] = []
    if let wheelRevs, let wheelTime {
        flags |= 0x01
        bytes += [UInt8(wheelRevs & 0xFF), UInt8((wheelRevs >> 8) & 0xFF),
                  UInt8((wheelRevs >> 16) & 0xFF), UInt8((wheelRevs >> 24) & 0xFF)]
        bytes += [UInt8(wheelTime & 0xFF), UInt8((wheelTime >> 8) & 0xFF)]
    }
    if let crankRevs, let crankTime {
        flags |= 0x02
        bytes += [UInt8(crankRevs & 0xFF), UInt8((crankRevs >> 8) & 0xFF)]
        bytes += [UInt8(crankTime & 0xFF), UInt8((crankTime >> 8) & 0xFF)]
    }
    return Data([flags] + bytes)
}

// MARK: - Payload parsing

@Suite("BLECSCClient — measurement parsing")
struct BLECSCParseTests {

    @Test("Combined payload decodes wheel and crank fields (little-endian)")
    func combined() throws {
        let data = Data([0x03, 0x44, 0x33, 0x22, 0x11, 0xBB, 0xAA, 0x66, 0x55, 0xDD, 0xCC])
        let m = try #require(BLECSCClient.Measurement(data: data))
        #expect(m.cumulativeWheelRevolutions == 0x1122_3344)
        #expect(m.lastWheelEventTime == 0xAABB)
        #expect(m.cumulativeCrankRevolutions == 0x5566)
        #expect(m.lastCrankEventTime == 0xCCDD)
    }

    @Test("Wheel-only payload leaves crank fields nil")
    func wheelOnly() throws {
        let m = try #require(BLECSCClient.Measurement(data: cscPayload(wheelRevs: 100, wheelTime: 1024)))
        #expect(m.cumulativeWheelRevolutions == 100)
        #expect(m.lastWheelEventTime == 1024)
        #expect(m.cumulativeCrankRevolutions == nil)
        #expect(m.lastCrankEventTime == nil)
    }

    @Test("Crank-only payload leaves wheel fields nil")
    func crankOnly() throws {
        let m = try #require(BLECSCClient.Measurement(data: cscPayload(crankRevs: 50, crankTime: 2048)))
        #expect(m.cumulativeCrankRevolutions == 50)
        #expect(m.lastCrankEventTime == 2048)
        #expect(m.cumulativeWheelRevolutions == nil)
        #expect(m.lastWheelEventTime == nil)
    }

    @Test("Flags with no data bits set decodes to all-nil")
    func noData() throws {
        let m = try #require(BLECSCClient.Measurement(data: Data([0x00])))
        #expect(m.cumulativeWheelRevolutions == nil)
        #expect(m.cumulativeCrankRevolutions == nil)
    }

    @Test("Empty payload returns nil")
    func empty() {
        #expect(BLECSCClient.Measurement(data: Data()) == nil)
    }

    @Test("Truncated wheel block returns nil")
    func truncatedWheel() {
        // Flags claim wheel data but only 4 of the 6 required bytes follow.
        #expect(BLECSCClient.Measurement(data: Data([0x01, 0x10, 0x00, 0x00, 0x00])) == nil)
    }

    @Test("Truncated crank block returns nil")
    func truncatedCrank() {
        // Flags claim both; wheel block complete, crank block 2 of 4 bytes.
        #expect(BLECSCClient.Measurement(data: Data([0x03, 0x10, 0, 0, 0, 0x00, 0x04, 0x05, 0x00])) == nil)
    }

    @Test("Trailing extra bytes are ignored")
    func trailingBytes() throws {
        var data = cscPayload(wheelRevs: 100, wheelTime: 1024)
        data.append(contentsOf: [0x99, 0x99])
        let m = try #require(BLECSCClient.Measurement(data: data))
        #expect(m.cumulativeWheelRevolutions == 100)
    }
}

// MARK: - Calculator

@Suite("BLECSCClient — calculator")
struct BLECSCCalculatorTests {

    @Test("First sample primes and emits nothing")
    func priming() {
        var calc = CSCCalculator<UInt32>(maxRevsPerSecond: 15)
        #expect(calc.update(revs: 100, eventTime: 0) == nil)
    }

    @Test("Wheel rate: 2 revs over 1s is 2 rev/s")
    func wheelRate() {
        var calc = CSCCalculator<UInt32>(maxRevsPerSecond: 15)
        _ = calc.update(revs: 100, eventTime: 0)
        #expect(calc.update(revs: 102, eventTime: 1024) == 2.0)
    }

    @Test("Crank rate: 2 revs over 2s is 1 rev/s (= 60 rpm)")
    func crankRate() {
        var calc = CSCCalculator<UInt16>(maxRevsPerSecond: 5)
        _ = calc.update(revs: 50, eventTime: 0)
        #expect(calc.update(revs: 52, eventTime: 2048) == 1.0)
    }

    @Test("Wheel revolution counter rollover (UInt32.max → 1) computes positive delta")
    func wheelRollover() {
        var calc = CSCCalculator<UInt32>(maxRevsPerSecond: 15)
        _ = calc.update(revs: .max, eventTime: 0)
        #expect(calc.update(revs: 1, eventTime: 1024) == 2.0)   // (1 - UInt32.max) wraps to 2
    }

    @Test("Crank revolution counter rollover (UInt16.max → 1) computes positive delta")
    func crankRollover() {
        var calc = CSCCalculator<UInt16>(maxRevsPerSecond: 5)
        _ = calc.update(revs: .max, eventTime: 0)
        #expect(calc.update(revs: 1, eventTime: 1024) == 2.0)
    }

    @Test("Event time rollover (65000 → 488) computes positive 1s delta")
    func timeRollover() {
        var calc = CSCCalculator<UInt32>(maxRevsPerSecond: 15)
        _ = calc.update(revs: 100, eventTime: 65000)
        #expect(calc.update(revs: 102, eventTime: 488) == 2.0)  // (488 - 65000) wraps to 1024 ticks
    }

    @Test("Zero time delta is dropped and the gap averages into the next sample")
    func staleTime() {
        var calc = CSCCalculator<UInt32>(maxRevsPerSecond: 15)
        _ = calc.update(revs: 100, eventTime: 1024)
        #expect(calc.update(revs: 102, eventTime: 1024) == nil)  // revs moved, time didn't
        // State not advanced, so 4 revs over the next 1s reflects the full gap.
        #expect(calc.update(revs: 104, eventTime: 2048) == 4.0)
    }

    @Test("Stopped wheel emits 0 only after three duplicate samples")
    func stoppedEmitsZeroAfterThreshold() {
        var calc = CSCCalculator<UInt32>(maxRevsPerSecond: 15)
        _ = calc.update(revs: 100, eventTime: 1024)
        #expect(calc.update(revs: 100, eventTime: 1024) == nil)   // duplicate 1
        #expect(calc.update(revs: 100, eventTime: 1024) == nil)   // duplicate 2
        #expect(calc.update(revs: 100, eventTime: 1024) == 0.0)   // duplicate 3 → stopped
    }

    @Test("Resuming after a stop re-primes (skips one sample) then resumes correct rate")
    func resumeAfterStop() {
        var calc = CSCCalculator<UInt32>(maxRevsPerSecond: 15)
        _ = calc.update(revs: 100, eventTime: 1024)
        _ = calc.update(revs: 100, eventTime: 1024)
        _ = calc.update(revs: 100, eventTime: 1024)
        #expect(calc.update(revs: 100, eventTime: 1024) == 0.0)   // confirmed stopped
        #expect(calc.update(revs: 105, eventTime: 5120) == nil)   // moving again → re-prime
        #expect(calc.update(revs: 107, eventTime: 6144) == 2.0)
    }

    @Test("Backwards counter (sensor reset) is rejected, then re-primes for correct values")
    func resetSpike() {
        var calc = CSCCalculator<UInt32>(maxRevsPerSecond: 15)
        _ = calc.update(revs: 50_000, eventTime: 0)
        #expect(calc.update(revs: 5, eventTime: 1024) == nil)     // huge wrapped delta > cap
        #expect(calc.update(revs: 7, eventTime: 2048) == 2.0)     // re-primed from (5, 1024)
    }

    @Test("reset() clears state so the next sample primes")
    func resetClearsState() {
        var calc = CSCCalculator<UInt32>(maxRevsPerSecond: 15)
        _ = calc.update(revs: 100, eventTime: 0)
        calc.reset()
        #expect(calc.update(revs: 102, eventTime: 1024) == nil)   // primes again, no rate
        #expect(calc.update(revs: 104, eventTime: 2048) == 2.0)
    }
}

// MARK: - Distance accounting
//
// `lastCountedRevolutions` feeds GPS auto-calibration (#70), which divides GPS
// distance by revolutions. It deliberately does not track the emitted rate: some
// samples carry real travel but no usable interval to derive a rate from.

@Suite("BLECSCClient — revolution counting")
struct BLECSCRevolutionCountingTests {

    @Test("A normal sample counts its revolutions")
    func normalSampleCounts() {
        var calc = CSCCalculator<UInt32>(maxRevsPerSecond: 15)
        _ = calc.update(revs: 100, eventTime: 0)
        #expect(calc.lastCountedRevolutions == 0)      // priming is not travel
        _ = calc.update(revs: 102, eventTime: 1024)
        #expect(calc.lastCountedRevolutions == 2)
    }

    @Test("Resuming after a stop counts the revolutions ridden, though it emits no rate")
    func rePrimeAfterStopCounts() {
        var calc = CSCCalculator<UInt32>(maxRevsPerSecond: 15)
        _ = calc.update(revs: 100, eventTime: 1024)
        _ = calc.update(revs: 100, eventTime: 1024)
        _ = calc.update(revs: 100, eventTime: 1024)
        _ = calc.update(revs: 100, eventTime: 1024)               // confirmed stopped

        // Rider pulls away from the light: no rate (the event time wrapped), but
        // five revolutions of ground really did pass under the wheel. Losing these
        // is what would fabricate a discrepancy in stop-start riding.
        #expect(calc.update(revs: 105, eventTime: 5120) == nil)
        #expect(calc.lastCountedRevolutions == 5)
    }

    @Test("A stopped wheel counts nothing")
    func stoppedCountsNothing() {
        var calc = CSCCalculator<UInt32>(maxRevsPerSecond: 15)
        _ = calc.update(revs: 100, eventTime: 1024)
        for _ in 0..<3 {
            _ = calc.update(revs: 100, eventTime: 1024)
            #expect(calc.lastCountedRevolutions == 0)
        }
    }

    @Test("A rejected reset spike counts nothing on either path")
    func resetSpikeCountsNothing() {
        var calc = CSCCalculator<UInt32>(maxRevsPerSecond: 15)
        _ = calc.update(revs: 50_000, eventTime: 0)
        #expect(calc.update(revs: 5, eventTime: 1024) == nil)      // wrapped delta over cap
        #expect(calc.lastCountedRevolutions == 0)

        // Same spike arriving on the re-prime path, where no interval exists to
        // sanity-check against, is rejected by the 64 s event-time-wrap bound.
        var afterStop = CSCCalculator<UInt32>(maxRevsPerSecond: 15)
        _ = afterStop.update(revs: 100, eventTime: 1024)
        for _ in 0..<3 { _ = afterStop.update(revs: 100, eventTime: 1024) }
        _ = afterStop.update(revs: 50_000, eventTime: 5120)
        #expect(afterStop.lastCountedRevolutions == 0)
    }

    @Test("A zero-time-delta glitch counts nothing, then the next pair counts the full span")
    func glitchDefersCount() {
        var calc = CSCCalculator<UInt32>(maxRevsPerSecond: 15)
        _ = calc.update(revs: 100, eventTime: 1024)
        _ = calc.update(revs: 102, eventTime: 1024)               // revs moved, time didn't
        #expect(calc.lastCountedRevolutions == 0)
        _ = calc.update(revs: 104, eventTime: 2048)
        #expect(calc.lastCountedRevolutions == 4)                 // both revolutions recovered
    }

    @Test("Counter rollover counts the wrapped delta, not the raw difference")
    func rolloverCounts() {
        var calc = CSCCalculator<UInt32>(maxRevsPerSecond: 15)
        _ = calc.update(revs: .max, eventTime: 0)
        _ = calc.update(revs: 1, eventTime: 1024)
        #expect(calc.lastCountedRevolutions == 2)
    }

    @Test("reset() clears the counter")
    func resetClearsCounter() {
        var calc = CSCCalculator<UInt32>(maxRevsPerSecond: 15)
        _ = calc.update(revs: 100, eventTime: 0)
        _ = calc.update(revs: 102, eventTime: 1024)
        #expect(calc.lastCountedRevolutions == 2)
        calc.reset()
        #expect(calc.lastCountedRevolutions == 0)
    }
}

// MARK: - Reconnect backoff

@Suite("BLECSCClient — reconnect backoff")
struct BLECSCBackoffTests {

    @Test("Backoff ladder is 1, 2, 4, 8, 16 then capped at 30 seconds")
    func backoffLadder() {
        let expected: [Duration] = [
            .seconds(1), .seconds(2), .seconds(4), .seconds(8),
            .seconds(16), .seconds(30), .seconds(30),
        ]
        for (attempt, delay) in expected.enumerated() {
            #expect(BLECSCClient.reconnectDelay(attempt: attempt) == delay)
        }
    }
}

// MARK: - Integration (controllable BLEClient + TestClock)

@Suite("BLECSCClient — live state machine")
struct BLECSCIntegrationTests {

    /// Controllable transport: events are injected by the test; every operation is
    /// recorded. `connectCalls` is a stream so reconnect-backoff tests can await
    /// each attempt deterministically.
    private struct Harness {
        let client: BLECSCClient
        let events: AsyncStream<BLEEvent>.Continuation
        let connectCalls: AsyncStream<UUID>
        let connectCount: LockIsolated<Int>
        let scanned: LockIsolated<[[CBUUID]]>
        /// Service UUIDs passed to `stopScanning` — the pairing-scan refcount tests
        /// assert on whether the hardware scan was released at all.
        let scanStopped: LockIsolated<[[CBUUID]]>
        /// (peripheral, owner) pairs passed to `disconnect`, so per-device unpair can
        /// be told apart from the all-devices teardown.
        let disconnected: LockIsolated<[(UUID, String)]>
        let notified: LockIsolated<[(Bool, CBUUID)]>
        let servicesDiscovered: LockIsolated<[[CBUUID]?]>
        /// Characteristic UUIDs passed to `discoverCharacteristics`, so the 0x2A5C
        /// request can be asserted at the point it is made rather than inferred.
        let characteristicsDiscovered: LockIsolated<[[CBUUID]?]>
        /// (peripheral, service, characteristic) triples passed to `readValue`. The
        /// service is retained so a read can be pinned to the service it belongs to.
        let reads: LockIsolated<[(UUID, CBUUID, CBUUID)]>
        let clock: TestClock<Duration>

        init() {
            let (eventStream, eventContinuation) = AsyncStream<BLEEvent>.makeStream()
            let (connectStream, connectContinuation) = AsyncStream<UUID>.makeStream()
            let connectCount = LockIsolated(0)
            let scanned = LockIsolated<[[CBUUID]]>([])
            let scanStopped = LockIsolated<[[CBUUID]]>([])
            let disconnected = LockIsolated<[(UUID, String)]>([])
            let notified = LockIsolated<[(Bool, CBUUID)]>([])
            let servicesDiscovered = LockIsolated<[[CBUUID]?]>([])
            let characteristicsDiscovered = LockIsolated<[[CBUUID]?]>([])
            let reads = LockIsolated<[(UUID, CBUUID, CBUUID)]>([])
            let clock = TestClock()

            let bleClient = BLEClient(
                startScanning: { uuids in scanned.withValue { $0.append(uuids) } },
                stopScanning: { uuids in scanStopped.withValue { $0.append(uuids) } },
                connect: { id, _ in
                    connectCount.withValue { $0 += 1 }
                    connectContinuation.yield(id)
                },
                disconnect: { id, owner in disconnected.withValue { $0.append((id, owner)) } },
                discoverServices: { _, uuids in
                    servicesDiscovered.withValue { $0.append(uuids) }
                },
                discoverCharacteristics: { _, _, uuids in
                    characteristicsDiscovered.withValue { $0.append(uuids) }
                },
                setNotifyValue: { enabled, _, _, charUUID in
                    notified.withValue { $0.append((enabled, charUUID)) }
                },
                readValue: { id, serviceUUID, charUUID in
                    reads.withValue { $0.append((id, serviceUUID, charUUID)) }
                },
                events: { eventStream }
            )

            self.client = BLECSCClient.live(bleClient: bleClient, clock: clock)
            self.events = eventContinuation
            self.connectCalls = connectStream
            self.connectCount = connectCount
            self.scanned = scanned
            self.scanStopped = scanStopped
            self.disconnected = disconnected
            self.notified = notified
            self.servicesDiscovered = servicesDiscovered
            self.characteristicsDiscovered = characteristicsDiscovered
            self.reads = reads
            self.clock = clock
        }

        /// Drive a peripheral through the discovery handshake to `.active`. Reports
        /// both CSC characteristics, as a compliant sensor does — `includeFeature:
        /// false` stands in for one that doesn't expose 0x2A5C.
        func bringToActive(_ id: UUID, includeFeature: Bool = true) {
            events.yield(.connected(id: id))
            events.yield(.servicesDiscovered(peripheralID: id, serviceUUIDs: [cscServiceUUID]))
            events.yield(.characteristicsDiscovered(
                peripheralID: id, serviceUUID: cscServiceUUID,
                characteristicUUIDs: includeFeature
                    ? [cscMeasurementUUID, cscFeatureUUID]
                    : [cscMeasurementUUID]
            ))
        }

        /// Answer this peripheral's 0x2A5C read. Flags are 16-bit little-endian:
        /// bit 0 wheel, bit 1 crank.
        func reportCapabilities(wheel: Bool, crank: Bool, from id: UUID) {
            var flags: UInt16 = 0
            if wheel { flags |= 0x0001 }
            if crank { flags |= 0x0002 }
            events.yield(.characteristicValueUpdated(
                peripheralID: id, characteristicUUID: cscFeatureUUID,
                value: Data([UInt8(flags & 0xFF), UInt8(flags >> 8)])
            ))
        }

        /// Tell the client this peripheral is paired, the way the feature layer does.
        func pair(_ id: UUID, roles: Set<SensorRole>) async {
            await client.setPairedSensors([id: roles])
        }

        /// Wait until the device list satisfies `predicate`, and return it.
        ///
        /// Events are handled on the client's own task, so yielding one and reading
        /// the list on the next line is a race. Tests that assert on connection state
        /// get a sync point for free from the state stream; device-list assertions
        /// need this instead.
        func devices(
            matching predicate: @Sendable ([BLECSCClient.DiscoveredSensor]) -> Bool
        ) async -> [BLECSCClient.DiscoveredSensor] {
            for await list in client.discoveredSensors() where predicate(list) { return list }
            return []
        }

        /// Answer this peripheral's battery read with `percent`.
        func reportBattery(_ percent: UInt8, from id: UUID) {
            events.yield(.characteristicValueUpdated(
                peripheralID: id, characteristicUUID: batteryLevelUUID, value: Data([percent])
            ))
        }
    }

    @Test("Combined sensor: discovery drives both roles to active and enables notifications")
    func combinedToActive() async {
        let harness = Harness()
        let id = UUID()
        await harness.pair(id, roles: [.speed, .cadence])

        var speedStates = harness.client.connectionState(.speed).makeAsyncIterator()
        var cadenceStates = harness.client.connectionState(.cadence).makeAsyncIterator()
        #expect(await speedStates.next() == .disconnected)
        #expect(await cadenceStates.next() == .disconnected)

        await harness.client.startScanning()
        #expect(await speedStates.next() == .scanning)
        #expect(await cadenceStates.next() == .scanning)
        #expect(harness.scanned.value == [[cscServiceUUID]])

        harness.events.yield(.discovered(id: id, name: "GSC-10", rssi: -55, services: [cscServiceUUID]))
        #expect(await speedStates.next() == .connecting)
        #expect(await cadenceStates.next() == .connecting)

        harness.bringToActive(id)
        #expect(await speedStates.next() == .connected)
        #expect(await cadenceStates.next() == .connected)
        #expect(await speedStates.next() == .active)
        #expect(await cadenceStates.next() == .active)

        #expect(harness.connectCount.value == 1)
        #expect(harness.notified.value.count == 1)
        #expect(harness.notified.value[0].0 == true)
        #expect(harness.notified.value[0].1 == cscMeasurementUUID)
    }

    @Test("Combined sensor produces both speed and cadence from one notification stream")
    func combinedSpeedAndCadence() async {
        let harness = Harness()
        let id = UUID()
        await harness.client.setRoles(id, [.speed, .cadence])

        var speeds = harness.client.speed().makeAsyncIterator()
        var cadences = harness.client.cadence().makeAsyncIterator()

        // Prime, then a sample 2 wheel revs / 1s and 2 crank revs / 2s later.
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 100, wheelTime: 0, crankRevs: 50, crankTime: 0)
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 102, wheelTime: 1024, crankRevs: 52, crankTime: 2048)
        ))

        let speed = await speeds.next()
        let cadence = await cadences.next()
        #expect(abs((speed ?? 0) - 4.192) < 0.0001)   // 2 rev/s × 2096mm
        #expect(cadence == 60.0)                       // 1 rev/s × 60
    }

    @Test("Speed-only sensor emits speed from wheel data")
    func speedOnly() async {
        let harness = Harness()
        let id = UUID()
        await harness.client.setRoles(id, [.speed])

        var speeds = harness.client.speed().makeAsyncIterator()
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 100, wheelTime: 0)
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 102, wheelTime: 1024)
        ))
        let speed = await speeds.next()
        #expect(abs((speed ?? 0) - 4.192) < 0.0001)
    }

    @Test("Wheel revolutions are published alongside speed, unscaled by circumference")
    func wheelRevolutionsPublished() async {
        let harness = Harness()
        let id = UUID()
        await harness.client.setRoles(id, [.speed])

        var revolutions = harness.client.wheelRevolutions().makeAsyncIterator()
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 100, wheelTime: 0)
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 102, wheelTime: 1024)
        ))
        #expect(await revolutions.next() == 2.0)
    }

    @Test("A cadence-only sensor publishes no wheel revolutions")
    func cadenceOnlySensorPublishesNoRevolutions() async {
        let harness = Harness()
        let cadenceID = UUID()
        let speedID = UUID()
        await harness.client.setRoles(cadenceID, [.cadence])
        await harness.client.setRoles(speedID, [.speed])

        var revolutions = harness.client.wheelRevolutions().makeAsyncIterator()

        // A combo device assigned cadence only still reports wheel data; it must not
        // reach calibration, or a wheel the rider didn't nominate would drive their
        // circumference.
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: cadenceID, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 500, wheelTime: 0, crankRevs: 50, crankTime: 0)
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: cadenceID, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 900, wheelTime: 1024, crankRevs: 52, crankTime: 2048)
        ))
        // The speed-role sensor's much smaller delta is what should come through.
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: speedID, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 100, wheelTime: 0)
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: speedID, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 103, wheelTime: 1024)
        ))
        #expect(await revolutions.next() == 3.0)
    }

    @Test("Cadence-only sensor emits cadence from crank data")
    func cadenceOnly() async {
        let harness = Harness()
        let id = UUID()
        await harness.client.setRoles(id, [.cadence])

        var cadences = harness.client.cadence().makeAsyncIterator()
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(crankRevs: 50, crankTime: 0)
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(crankRevs: 52, crankTime: 2048)
        ))
        #expect(await cadences.next() == 60.0)
    }

    @Test("Multi-sensor: dedicated speed sensor + combo-as-cadence gate by assigned role")
    func multiSensorRoleGating() async {
        let harness = Harness()
        let speedID = UUID()
        let comboID = UUID()
        await harness.client.setRoles(speedID, [.speed])
        await harness.client.setRoles(comboID, [.cadence])

        var speeds = harness.client.speed().makeAsyncIterator()
        var cadences = harness.client.cadence().makeAsyncIterator()

        // The combo reports BOTH wheel and crank fields, but only holds the cadence
        // role — its wheel data must be ignored. The dedicated speed sensor supplies
        // speed with a distinct value (3 rev/s) so the source is unambiguous.
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: comboID, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 100, wheelTime: 0, crankRevs: 50, crankTime: 0)
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: speedID, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 200, wheelTime: 0)
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: comboID, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 999, wheelTime: 9999, crankRevs: 52, crankTime: 2048)
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: speedID, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 203, wheelTime: 1024)
        ))

        // First speed emission is from the dedicated sensor (3 rev/s × 2096mm), not
        // the combo's wheel field (which would have been 2 rev/s if not gated out).
        let speed = await speeds.next()
        #expect(abs((speed ?? 0) - 6.288) < 0.0001)
        #expect(await cadences.next() == 60.0)   // cadence from the combo
    }

    @Test("Unexpected disconnect of one peripheral reconnects it while the other stays active")
    func independentReconnect() async {
        let harness = Harness()
        let speedID = UUID()
        let cadenceID = UUID()
        await harness.client.setRoles(speedID, [.speed])
        await harness.client.setRoles(cadenceID, [.cadence])

        var speedStates = harness.client.connectionState(.speed).makeAsyncIterator()
        #expect(await speedStates.next() == .connecting)   // replay
        harness.bringToActive(speedID)
        harness.bringToActive(cadenceID)
        #expect(await speedStates.next() == .connected)
        #expect(await speedStates.next() == .active)

        var connects = harness.connectCalls.makeAsyncIterator()
        #expect(await connects.next() == speedID)          // initial connects
        #expect(await connects.next() == cadenceID)

        harness.events.yield(.disconnected(id: speedID, error: nil))
        #expect(await speedStates.next() == .reconnecting)

        await harness.clock.advance(by: .seconds(1))
        #expect(await connects.next() == speedID)          // attempt 1 after 1s
        await harness.clock.advance(by: .seconds(2))
        #expect(await connects.next() == speedID)          // attempt 2 after 2s

        // Cadence peripheral was untouched: it still emits.
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: cadenceID, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(crankRevs: 50, crankTime: 0)
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: cadenceID, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(crankRevs: 52, crankTime: 2048)
        ))
        var cadences = harness.client.cadence().makeAsyncIterator()
        #expect(await cadences.next() == 60.0)

        // Reconnection succeeds — backoff stops.
        harness.events.yield(.connected(id: speedID))
        #expect(await speedStates.next() == .connected)
        let countAfter = harness.connectCount.value
        await harness.clock.advance(by: .seconds(120))
        await Task.yield()
        #expect(harness.connectCount.value == countAfter)
    }

    @Test("Calculator resets across an unexpected disconnect")
    func calculatorResetsOnReconnect() async {
        let harness = Harness()
        let id = UUID()
        await harness.client.setRoles(id, [.speed])
        var speeds = harness.client.speed().makeAsyncIterator()

        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 100, wheelTime: 0)
        ))
        harness.events.yield(.disconnected(id: id, error: nil))
        harness.events.yield(.connected(id: id))

        // First post-reconnect sample must re-prime (no emission), proving the stale
        // pre-disconnect sample (100 @ t0) was cleared. Were it retained, this sample
        // would emit a plausible-but-wrong 1 rev/s across the gap (105−100 over 5s).
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 105, wheelTime: 5120)
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 107, wheelTime: 6144)
        ))
        let speed = await speeds.next()
        #expect(abs((speed ?? 0) - 4.192) < 0.0001)   // 2 rev/s from (105,107), not the gap value
    }

    @Test("Reassigning a role away resets that role's calculator on the losing peripheral")
    func roleReassignmentResetsCalculator() async {
        let harness = Harness()
        let a = UUID()
        let b = UUID()
        await harness.client.setRoles(a, [.speed, .cadence])
        var speeds = harness.client.speed().makeAsyncIterator()

        // Prime + emit a speed from A so its wheel calculator holds a sample.
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: a, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 100, wheelTime: 0)
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: a, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 102, wheelTime: 1024)
        ))
        #expect(abs((await speeds.next() ?? 0) - 4.192) < 0.0001)

        // Move speed to B, then back to A. A keeps cadence throughout so its slot
        // survives — but its wheel calculator must have been reset on the strip.
        await harness.client.setRoles(b, [.speed])
        await harness.client.setRoles(a, [.speed])

        // First sample after the role returns must re-prime (no emission). Were the
        // stale (102 @ t1024) sample retained, this would emit a plausible-but-wrong
        // 0.75 rev/s across the gap (105−102 over 4s) instead of priming.
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: a, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 105, wheelTime: 5120)
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: a, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 107, wheelTime: 6144)
        ))
        #expect(abs((await speeds.next() ?? 0) - 4.192) < 0.0001)   // 2 rev/s from (105,107)
    }

    @Test("Reconnection gives up after the max attempt ladder and releases the role")
    func reconnectGivesUp() async {
        let harness = Harness()
        let id = UUID()
        await harness.client.setRoles(id, [.speed])

        var speedStates = harness.client.connectionState(.speed).makeAsyncIterator()
        #expect(await speedStates.next() == .connecting)   // replay

        var connects = harness.connectCalls.makeAsyncIterator()
        #expect(await connects.next() == id)               // initial connect

        harness.events.yield(.disconnected(id: id, error: nil))
        #expect(await speedStates.next() == .reconnecting)

        // Walk the full backoff ladder; each advance releases one reconnect attempt.
        for delay in [1, 2, 4, 8, 16, 30, 30, 30, 30, 30] {
            await harness.clock.advance(by: .seconds(delay))
            #expect(await connects.next() == id)
        }
        // Ladder exhausted → sensor considered lost, role released to disconnected.
        #expect(await speedStates.next() == .disconnected)
    }

    @Test("User-initiated disconnect does not trigger reconnection")
    func userDisconnectNoReconnect() async {
        let harness = Harness()
        let id = UUID()
        await harness.client.setRoles(id, [.speed, .cadence])

        var speedStates = harness.client.connectionState(.speed).makeAsyncIterator()
        #expect(await speedStates.next() == .connecting)

        await harness.client.disconnect()
        #expect(await speedStates.next() == .disconnected)

        harness.events.yield(.disconnected(id: id, error: nil))   // arrives after slot cleared
        let countBefore = harness.connectCount.value
        await harness.clock.advance(by: .seconds(120))
        await Task.yield()
        #expect(harness.connectCount.value == countBefore)
    }

    @Test("setWheelCircumference scales subsequent speed")
    func wheelCircumferenceScalesSpeed() async {
        let harness = Harness()
        let id = UUID()
        await harness.client.setRoles(id, [.speed])
        var speeds = harness.client.speed().makeAsyncIterator()

        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 100, wheelTime: 0)
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 102, wheelTime: 1024)
        ))
        #expect(abs((await speeds.next() ?? 0) - 4.192) < 0.0001)   // default 2096mm

        await harness.client.setWheelCircumference(2200)
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 104, wheelTime: 2048)
        ))
        #expect(abs((await speeds.next() ?? 0) - 4.4) < 0.0001)     // 2 rev/s × 2200mm
    }

    @Test("Discovery of a non-CSC peripheral is ignored")
    func nonCSCDiscoveryIgnored() async {
        let harness = Harness()
        let hrID = UUID()
        let cscID = UUID()
        let hrServiceUUID = CBUUID(string: "180D")
        await harness.pair(cscID, roles: [.speed, .cadence])

        var speedStates = harness.client.connectionState(.speed).makeAsyncIterator()
        _ = await speedStates.next()   // .disconnected
        await harness.client.startScanning()
        _ = await speedStates.next()   // .scanning

        var connects = harness.connectCalls.makeAsyncIterator()
        harness.events.yield(.discovered(id: hrID, name: "Polar H10", rssi: -50, services: [hrServiceUUID]))
        harness.events.yield(.discovered(id: cscID, name: "GSC-10", rssi: -60, services: [cscServiceUUID]))

        #expect(await speedStates.next() == .connecting)
        #expect(await connects.next() == cscID)   // first connect is the CSC sensor, not the strap
        #expect(harness.connectCount.value == 1)
    }

    /// The rule the whole of #67 turns on: an unpaired sensor advertising nearby is
    /// listed and otherwise left alone. Nothing the rider did not choose can take a
    /// role — which is what makes wheel auto-calibration (#70) safe to build on.
    @Test("A discovered sensor the rider never paired is not connected")
    func unpairedDiscoveryIsNotConnected() async {
        let harness = Harness()
        let paired = UUID()
        let stranger = UUID()
        await harness.pair(paired, roles: [.speed, .cadence])

        var speedStates = harness.client.connectionState(.speed).makeAsyncIterator()
        _ = await speedStates.next()   // .disconnected
        await harness.client.startScanning()
        _ = await speedStates.next()   // .scanning

        var connects = harness.connectCalls.makeAsyncIterator()
        harness.events.yield(.discovered(id: paired, name: "GSC-10", rssi: -55, services: [cscServiceUUID]))
        #expect(await connects.next() == paired)
        #expect(await speedStates.next() == .connecting)

        harness.events.yield(.discovered(id: stranger, name: "Someone Else's RPM", rssi: -50, services: [cscServiceUUID]))
        await Task.yield()
        #expect(harness.connectCount.value == 1)

        // It is still listed, so the rider can choose to pair it.
        let listed = await harness.devices { $0.contains { $0.id == stranger } }
        #expect(listed.first { $0.id == stranger }?.isPaired == false)
    }

    @Test("A dedicated speed sensor + a dedicated cadence sensor both end up active")
    func twoDedicatedSensorsFillOneRoleEach() async {
        let harness = Harness()
        let speedSensor = UUID()
        let cadenceSensor = UUID()
        await harness.client.setPairedSensors([speedSensor: [.speed], cadenceSensor: [.cadence]])

        await harness.client.startScanning()

        var connects = harness.connectCalls.makeAsyncIterator()
        harness.events.yield(.discovered(id: speedSensor, name: "Wahoo Speed", rssi: -55, services: [cscServiceUUID]))
        #expect(await connects.next() == speedSensor)

        harness.events.yield(.discovered(id: cadenceSensor, name: "Wahoo Cadence", rssi: -50, services: [cscServiceUUID]))
        #expect(await connects.next() == cadenceSensor)
        #expect(harness.connectCount.value == 2)

        harness.bringToActive(speedSensor)
        harness.bringToActive(cadenceSensor)

        // Each sensor now supplies its own metric independently.
        var speeds = harness.client.speed().makeAsyncIterator()
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: speedSensor, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 100, wheelTime: 0)
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: speedSensor, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 102, wheelTime: 1024)
        ))
        #expect(abs((await speeds.next() ?? 0) - 4.192) < 0.0001)

        var cadences = harness.client.cadence().makeAsyncIterator()
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: cadenceSensor, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(crankRevs: 50, crankTime: 0)
        ))
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: cadenceSensor, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(crankRevs: 52, crankTime: 2048)
        ))
        #expect(await cadences.next() == 60.0)
    }

    @Test("Connecting discovers the battery service alongside the CSC service")
    func connectDiscoversBatteryService() async {
        let harness = Harness()
        let id = UUID()

        var states = harness.client.connectionState(.speed).makeAsyncIterator()
        #expect(await states.next() == .disconnected)

        await harness.client.setRoles(id, [.speed, .cadence])
        #expect(await states.next() == .connecting)

        harness.events.yield(.connected(id: id))
        #expect(await states.next() == .connected)   // sync point: discoverServices has run

        #expect(harness.servicesDiscovered.value.count == 1)
        #expect(harness.servicesDiscovered.value[0]?.contains(cscServiceUUID) == true)
        #expect(harness.servicesDiscovered.value[0]?.contains(batteryServiceUUID) == true)
    }

    @Test("Battery level is read on connect, published per role, and cleared on disconnect")
    func batteryLevelReadAndCleared() async {
        let harness = Harness()
        let id = UUID()

        await harness.client.setRoles(id, [.speed, .cadence])
        var battery = harness.client.batteryLevel(.speed).makeAsyncIterator()
        #expect(await battery.next() == Int?.none)   // replayed: nothing read yet

        harness.bringToActive(id)
        harness.events.yield(.characteristicsDiscovered(
            peripheralID: id, serviceUUID: batteryServiceUUID,
            characteristicUUIDs: [batteryLevelUUID]
        ))
        harness.reportBattery(64, from: id)

        #expect(await battery.next() == 64)
        // Two reads, each against its own service: capabilities when the CSC
        // characteristics are discovered, then the battery level.
        #expect(harness.reads.value.map(\.2) == [cscFeatureUUID, batteryLevelUUID])
        #expect(harness.reads.value.map(\.1) == [cscServiceUUID, batteryServiceUUID])

        // A stale level next to a reconnecting sensor would read as current.
        harness.events.yield(.disconnected(id: id, error: nil))
        #expect(await battery.next() == Int?.none)
    }

    /// The case only CSC has: speed and cadence can be two physical devices, so one
    /// battery level per client would be wrong for at least one of the two rows.
    @Test("Two peripherals report their own battery to their own role")
    func batteryIsPerRoleNotPerClient() async {
        let harness = Harness()
        let speedSensor = UUID()
        let cadenceSensor = UUID()

        await harness.client.setRoles(speedSensor, [.speed])
        await harness.client.setRoles(cadenceSensor, [.cadence])

        var speedBattery = harness.client.batteryLevel(.speed).makeAsyncIterator()
        var cadenceBattery = harness.client.batteryLevel(.cadence).makeAsyncIterator()
        _ = await speedBattery.next()    // replayed nil
        _ = await cadenceBattery.next()

        harness.reportBattery(90, from: speedSensor)
        harness.reportBattery(15, from: cadenceSensor)

        #expect(await speedBattery.next() == 90)
        #expect(await cadenceBattery.next() == 15)

        // And the device list carries each peripheral's own level for the S11 rows.
        var devices = harness.client.discoveredSensors().makeAsyncIterator()
        let listed = await devices.next() ?? []
        #expect(listed.first { $0.id == speedSensor }?.batteryPercent == 90)
        #expect(listed.first { $0.id == cadenceSensor }?.batteryPercent == 15)
    }

    @Test("Bluetooth permission denied stands down without crashing")
    func permissionDenied() async {
        let harness = Harness()
        let id = UUID()
        await harness.client.setRoles(id, [.speed, .cadence])

        var speedStates = harness.client.connectionState(.speed).makeAsyncIterator()
        #expect(await speedStates.next() == .connecting)

        harness.events.yield(.stateChanged(.unauthorized))
        #expect(await speedStates.next() == .disconnected)

        await harness.client.startScanning()
        #expect(await speedStates.next() == .scanning)
    }

    // MARK: - Pairing UI (S11 subset, #68)

    @Test("Pairing scan runs even with a sensor already connected")
    func pairingScanBypassesColdStateGuard() async {
        let harness = Harness()
        let connected = UUID()
        await harness.client.setRoles(connected, [.speed, .cadence])
        harness.bringToActive(connected)

        // The ambient scan refuses once a slot exists — that guard is deliberate.
        await harness.client.startScanning()
        #expect(harness.scanned.value.isEmpty)

        await harness.client.beginPairingScan()
        #expect(harness.scanned.value == [[cscServiceUUID]])
    }

    @Test("A pairing scan does not make dashboard role tiles read .scanning")
    func pairingScanDoesNotAffectRoleState() async {
        let harness = Harness()
        let id = UUID()
        await harness.pair(id, roles: [.speed, .cadence])

        var speedStates = harness.client.connectionState(.speed).makeAsyncIterator()
        #expect(await speedStates.next() == .disconnected)

        await harness.client.beginPairingScan()
        harness.events.yield(.discovered(id: id, name: "GSC-10", rssi: -55, services: [cscServiceUUID]))

        // The paired sensor is reconnected, so the next state is .connecting — never
        // .scanning, which would falsely show "Searching" behind a settings screen.
        #expect(await speedStates.next() == .connecting)
    }

    @Test("Ending a pairing scan leaves the ambient dashboard scan running")
    func endPairingScanRespectsAmbientScan() async {
        let harness = Harness()
        await harness.client.startScanning()      // ambient, from a cold state
        await harness.client.beginPairingScan()

        await harness.client.endPairingScan()
        #expect(harness.scanStopped.value.isEmpty)

        // ...and the ambient stop is likewise deferred while a pairing scan is open.
        await harness.client.beginPairingScan()
        await harness.client.stopScanning()
        #expect(harness.scanStopped.value.isEmpty)

        await harness.client.endPairingScan()
        #expect(harness.scanStopped.value == [[cscServiceUUID]])
    }

    /// Unpair no longer needs a session exclusion set: nothing is adopted without a
    /// persisted record, so dropping the record is the whole of "stays unpaired".
    @Test("Unpair releases only that peripheral, and it is not re-adopted")
    func unpairSticks() async {
        let harness = Harness()
        let id = UUID()
        await harness.pair(id, roles: [.speed, .cadence])

        harness.events.yield(.discovered(id: id, name: "GSC-10", rssi: -55, services: [cscServiceUUID]))
        var speedStates = harness.client.connectionState(.speed).makeAsyncIterator()
        #expect(await speedStates.next() == .disconnected)
        #expect(await speedStates.next() == .connecting)

        // The feature layer drops the records and pushes the reduced set; unpair
        // tears the connection down.
        await harness.client.setPairedSensors([:])
        await harness.client.unpair(id)
        #expect(await speedStates.next() == .disconnected)
        #expect(harness.disconnected.value.map(\.0) == [id])
        #expect(harness.disconnected.value.map(\.1) == ["csc"])
        // Unpair must not tear the scan down, unlike the all-devices disconnect().
        #expect(harness.scanStopped.value.isEmpty)

        let connectsBefore = harness.connectCount.value
        harness.events.yield(.discovered(id: id, name: "GSC-10", rssi: -55, services: [cscServiceUUID]))
        harness.events.yield(.discovered(id: id, name: "GSC-10", rssi: -55, services: [cscServiceUUID]))
        #expect(harness.connectCount.value == connectsBefore)
    }

    @Test("Pairing connects to interrogate, without taking a role from anything")
    func pairInterrogatesWithoutClaimingRoles() async {
        let harness = Harness()
        let incumbent = UUID()
        let candidate = UUID()
        var speedStates = harness.client.connectionState(.speed).makeAsyncIterator()
        #expect(await speedStates.next() == .disconnected)

        await harness.client.setPairedSensors([incumbent: [.speed, .cadence]])
        await harness.client.setRoles(incumbent, [.speed, .cadence])
        #expect(await speedStates.next() == .connecting)
        harness.bringToActive(incumbent)
        #expect(await speedStates.next() == .connected)
        #expect(await speedStates.next() == .active)

        // Pairing a second sensor must not knock the first off its roles before the
        // rider has chosen anything — the incumbent stays active throughout.
        await harness.client.pair(candidate)
        harness.bringToActive(candidate)
        harness.reportCapabilities(wheel: true, crank: true, from: candidate)

        let listed = await harness.devices {
            $0.first { $0.id == candidate }?.capabilities != nil
        }
        #expect(listed.first { $0.id == candidate }?.capabilities?.requiresRoleSelection == true)
        #expect(listed.first { $0.id == candidate }?.roles.isEmpty == true)
        #expect(listed.first { $0.id == incumbent }?.roles == [.speed, .cadence])
        #expect(harness.disconnected.value.isEmpty)
    }

    @Test("Committing the rider's choice takes the role off the incumbent")
    func settingRolesReassignsFromIncumbent() async {
        let harness = Harness()
        let incumbent = UUID()
        let candidate = UUID()
        await harness.client.setRoles(incumbent, [.speed, .cadence])
        await harness.client.pair(candidate)

        await harness.client.setRoles(candidate, [.cadence])

        let listed = await harness.devices { $0.first { $0.id == candidate }?.roles == [.cadence] }
        #expect(listed.first { $0.id == incumbent }?.roles == [.speed])
        #expect(listed.first { $0.id == candidate }?.roles == [.cadence])
    }

    /// Assignment, not union — the mechanism behind "role reassignable without
    /// re-pairing" (BLE.md §5.0). A combo device moved to Cadence must release Speed.
    @Test("setRoles replaces the previous role set rather than adding to it")
    func setRolesReplacesRatherThanUnions() async {
        let harness = Harness()
        let id = UUID()
        await harness.client.setRoles(id, [.speed, .cadence])

        await harness.client.setRoles(id, [.cadence])

        var devices = harness.client.discoveredSensors().makeAsyncIterator()
        let listed = await devices.next() ?? []
        #expect(listed.first { $0.id == id }?.roles == [.cadence])
    }

    @Test("An empty role set is refused — releasing a sensor is unpair's job")
    func setRolesRefusesEmptySet() async {
        let harness = Harness()
        let id = UUID()
        await harness.client.setRoles(id, [.speed])

        await harness.client.setRoles(id, [])

        var devices = harness.client.discoveredSensors().makeAsyncIterator()
        let listed = await devices.next() ?? []
        #expect(listed.first { $0.id == id }?.roles == [.speed])
        #expect(harness.disconnected.value.isEmpty)
    }

    // MARK: - Capabilities (0x2A5C, #67)

    @Test("Discovering the CSC characteristics reads the feature characteristic")
    func capabilitiesAreReadOnDiscovery() async {
        let harness = Harness()
        let id = UUID()
        await harness.client.setRoles(id, [.speed, .cadence])

        var states = harness.client.connectionState(.speed).makeAsyncIterator()
        #expect(await states.next() == .connecting)
        harness.bringToActive(id)
        #expect(await states.next() == .connected)
        #expect(await states.next() == .active)   // sync point: the read has been issued

        #expect(harness.characteristicsDiscovered.value.first??.contains(cscFeatureUUID) == true)
        #expect(harness.reads.value.map(\.2) == [cscFeatureUUID])
        #expect(harness.reads.value.map(\.1) == [cscServiceUUID])
    }

    /// The read is issued independently of the measurement subscription: a discovery
    /// result missing 0x2A5B must not also swallow the capability read, since the
    /// pairing UI is waiting on it.
    @Test("The feature read survives a discovery result with no measurement characteristic")
    func capabilitiesReadWithoutMeasurementCharacteristic() async {
        let harness = Harness()
        let id = UUID()
        await harness.client.setRoles(id, [.speed])

        harness.events.yield(.connected(id: id))
        harness.events.yield(.servicesDiscovered(peripheralID: id, serviceUUIDs: [cscServiceUUID]))
        harness.events.yield(.characteristicsDiscovered(
            peripheralID: id, serviceUUID: cscServiceUUID, characteristicUUIDs: [cscFeatureUUID]
        ))
        harness.reportCapabilities(wheel: true, crank: false, from: id)

        let listed = await harness.devices { $0.first { $0.id == id }?.capabilities != nil }
        #expect(listed.first { $0.id == id }?.capabilities?.supportsWheelRevolutions == true)
        #expect(harness.notified.value.isEmpty)   // never subscribed: 0x2A5B wasn't there
    }

    @Test("Capabilities surface on the device list for the pairing UI")
    func capabilitiesSurfaceOnDeviceList() async {
        let harness = Harness()
        let id = UUID()
        await harness.client.pair(id)
        harness.bringToActive(id)
        harness.reportCapabilities(wheel: false, crank: true, from: id)

        let listed = await harness.devices { $0.first { $0.id == id }?.capabilities != nil }
        let capabilities = listed.first { $0.id == id }?.capabilities
        #expect(capabilities?.supportsWheelRevolutions == false)
        #expect(capabilities?.supportsCrankRevolutions == true)
        #expect(capabilities?.requiresRoleSelection == false)
    }

    /// A persisted pairing that outlived a firmware change shouldn't keep a role the
    /// hardware can't fill.
    @Test("Capabilities narrow the roles of an already-assigned sensor")
    func capabilitiesNarrowAssignedRoles() async {
        let harness = Harness()
        let id = UUID()
        await harness.client.setRoles(id, [.speed, .cadence])

        var cadenceStates = harness.client.connectionState(.cadence).makeAsyncIterator()
        #expect(await cadenceStates.next() == .connecting)

        harness.bringToActive(id)
        harness.reportCapabilities(wheel: true, crank: false, from: id)
        #expect(await cadenceStates.next() == .connected)
        #expect(await cadenceStates.next() == .active)
        #expect(await cadenceStates.next() == .disconnected)   // cadence released
    }

    /// The fallback for a non-compliant sensor that never answers the read: the
    /// measurement's flags still reveal what it reports, one pedal stroke later.
    @Test("Measurement flags narrow roles when the sensor exposes no feature characteristic")
    func measurementFlagsNarrowWhenNoFeatureCharacteristic() async {
        let harness = Harness()
        let id = UUID()
        await harness.client.setRoles(id, [.speed, .cadence])

        var cadenceStates = harness.client.connectionState(.cadence).makeAsyncIterator()
        #expect(await cadenceStates.next() == .connecting)

        harness.bringToActive(id, includeFeature: false)
        #expect(harness.reads.value.isEmpty)
        #expect(await cadenceStates.next() == .connected)
        #expect(await cadenceStates.next() == .active)

        // First measurement carries wheel data only.
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 100, wheelTime: 0)
        ))
        #expect(await cadenceStates.next() == .disconnected)
    }

    @Test("A malformed feature payload is ignored rather than stripping every role")
    func malformedCapabilitiesIgnored() async {
        let harness = Harness()
        let id = UUID()
        let other = UUID()
        await harness.client.setRoles(id, [.speed, .cadence])
        harness.bringToActive(id)

        harness.events.yield(.characteristicValueUpdated(
            peripheralID: id, characteristicUUID: cscFeatureUUID, value: Data()
        ))
        // A well-formed report from a second peripheral is the sync point: once it
        // lands, the malformed one ahead of it in the queue has been processed.
        harness.events.yield(.discovered(id: other, name: "GSC-10", rssi: -55, services: [cscServiceUUID]))
        harness.reportCapabilities(wheel: true, crank: false, from: other)

        let listed = await harness.devices { $0.first { $0.id == other }?.capabilities != nil }
        #expect(listed.first { $0.id == id }?.capabilities == nil)
        #expect(listed.first { $0.id == id }?.roles == [.speed, .cadence])
    }

    @Test("Discovered-sensors replays a discovery that happened before subscribing")
    func discoveredSensorsReplaysPriorDiscovery() async {
        let harness = Harness()
        let id = UUID()
        await harness.pair(id, roles: [.speed, .cadence])

        // CoreBluetooth won't redeliver `.discovered` for a peripheral already seen,
        // so the replay is what populates a sheet opened after discovery.
        var speedStates = harness.client.connectionState(.speed).makeAsyncIterator()
        #expect(await speedStates.next() == .disconnected)
        harness.events.yield(.discovered(id: id, name: "GSC-10", rssi: -55, services: [cscServiceUUID]))
        // Sync point: the event has been fully processed once the role reacts to it.
        #expect(await speedStates.next() == .connecting)

        var devices = harness.client.discoveredSensors().makeAsyncIterator()
        let list = await devices.next()
        #expect(list?.count == 1)
        #expect(list?.first?.id == id)
        #expect(list?.first?.name == "GSC-10")
        #expect(list?.first?.isPaired == true)
    }

    @Test("Discovered-sensors reports a sensor as holding no roles after unpair")
    func discoveredSensorsTracksUnpair() async {
        let harness = Harness()
        let id = UUID()
        await harness.pair(id, roles: [.speed, .cadence])

        var devices = harness.client.discoveredSensors().makeAsyncIterator()
        #expect(await devices.next()?.isEmpty == true)

        harness.events.yield(.discovered(id: id, name: "GSC-10", rssi: -55, services: [cscServiceUUID]))
        var list = await devices.next()
        while list?.first?.isPaired != true { list = await devices.next() }

        await harness.client.setPairedSensors([:])
        await harness.client.unpair(id)
        var afterUnpair = await devices.next()
        while afterUnpair?.first?.isPaired != false { afterUnpair = await devices.next() }
        #expect(afterUnpair?.count == 1)
        #expect(afterUnpair?.first?.roles.isEmpty == true)
        #expect(afterUnpair?.first?.connectionState == nil)
        // The peripheral stays listed after unpair — it is still in range and
        // pairable, it just holds no roles.
        #expect(afterUnpair?.first?.id == id)
    }
}

// MARK: - Capability parsing (0x2A5C)

@Suite("BLECSCClient.Capabilities")
struct CSCCapabilitiesTests {

    @Test("Wheel-only flags fill the Speed role and ask nothing")
    func wheelOnly() throws {
        let capabilities = try #require(BLECSCClient.Capabilities(featureData: Data([0x01, 0x00])))
        #expect(capabilities.supportsWheelRevolutions)
        #expect(!capabilities.supportsCrankRevolutions)
        #expect(capabilities.supportedRoles == [.speed])
        #expect(!capabilities.requiresRoleSelection)
    }

    @Test("Crank-only flags fill the Cadence role and ask nothing")
    func crankOnly() throws {
        let capabilities = try #require(BLECSCClient.Capabilities(featureData: Data([0x02, 0x00])))
        #expect(!capabilities.supportsWheelRevolutions)
        #expect(capabilities.supportsCrankRevolutions)
        #expect(capabilities.supportedRoles == [.cadence])
        #expect(!capabilities.requiresRoleSelection)
    }

    @Test("Both bits set is the only case that needs the rider's answer")
    func comboRequiresSelection() throws {
        let capabilities = try #require(BLECSCClient.Capabilities(featureData: Data([0x03, 0x00])))
        #expect(capabilities.supportedRoles == [.speed, .cadence])
        #expect(capabilities.requiresRoleSelection)
    }

    /// Bits 2–15 carry unrelated features (multiple sensor locations, and so on).
    /// Reading the field as 16-bit little-endian must not let them leak into roles.
    @Test("High bits in the 16-bit field do not affect role support")
    func highBitsIgnored() throws {
        let capabilities = try #require(BLECSCClient.Capabilities(featureData: Data([0x01, 0xFF])))
        #expect(capabilities.supportedRoles == [.speed])
    }

    @Test("A sensor reporting neither supports no role")
    func neitherBitSet() throws {
        let capabilities = try #require(BLECSCClient.Capabilities(featureData: Data([0x00, 0x00])))
        #expect(capabilities.supportedRoles.isEmpty)
        #expect(!capabilities.requiresRoleSelection)
    }

    /// Failable rather than defaulting to "supports nothing": treating a broken frame
    /// as a real answer would strip both roles off a working sensor.
    @Test("An empty payload returns nil")
    func emptyPayloadIsNil() {
        #expect(BLECSCClient.Capabilities(featureData: Data()) == nil)
    }

    /// The spec's field is 16-bit, but a sensor sending only the low byte still
    /// carries both bits that matter.
    @Test("A single-byte payload is read rather than rejected")
    func singleBytePayload() throws {
        let capabilities = try #require(BLECSCClient.Capabilities(featureData: Data([0x03])))
        #expect(capabilities.requiresRoleSelection)
    }
}

// MARK: - Test value

@Suite("BLECSCClient — test value")
struct BLECSCTestValueTests {

    @Test("Test value methods do not crash")
    func methodsNoOp() async {
        let client = BLECSCClient.testValue
        await client.startScanning()
        await client.stopScanning()
        await client.setRoles(UUID(), [.speed, .cadence])
        await client.setWheelCircumference(2100)
        await client.disconnect()
    }

    @Test("Test value streams complete immediately")
    func streamsComplete() async {
        let client = BLECSCClient.testValue
        var speedCount = 0
        for await _ in client.speed() { speedCount += 1 }
        #expect(speedCount == 0)
        var cadenceCount = 0
        for await _ in client.cadence() { cadenceCount += 1 }
        #expect(cadenceCount == 0)
        var stateCount = 0
        for await _ in client.connectionState(.speed) { stateCount += 1 }
        #expect(stateCount == 0)
    }
}
