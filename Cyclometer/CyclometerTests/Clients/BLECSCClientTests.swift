import Testing
import ComposableArchitecture
import CoreBluetooth
@testable import Cyclometer

private let cscServiceUUID     = CBUUID(string: "1816")
private let cscMeasurementUUID = CBUUID(string: "2A5B")

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
        let notified: LockIsolated<[(Bool, CBUUID)]>
        let clock: TestClock<Duration>

        init() {
            let (eventStream, eventContinuation) = AsyncStream<BLEEvent>.makeStream()
            let (connectStream, connectContinuation) = AsyncStream<UUID>.makeStream()
            let connectCount = LockIsolated(0)
            let scanned = LockIsolated<[[CBUUID]]>([])
            let notified = LockIsolated<[(Bool, CBUUID)]>([])
            let clock = TestClock()

            let bleClient = BLEClient(
                startScanning: { uuids in scanned.withValue { $0.append(uuids) } },
                stopScanning: { _ in },
                connect: { id, _ in
                    connectCount.withValue { $0 += 1 }
                    connectContinuation.yield(id)
                },
                disconnect: { _, _ in },
                discoverServices: { _, _ in },
                discoverCharacteristics: { _, _, _ in },
                setNotifyValue: { enabled, _, _, charUUID in
                    notified.withValue { $0.append((enabled, charUUID)) }
                },
                readValue: { _, _, _ in },
                events: { eventStream }
            )

            self.client = BLECSCClient.live(bleClient: bleClient, clock: clock)
            self.events = eventContinuation
            self.connectCalls = connectStream
            self.connectCount = connectCount
            self.scanned = scanned
            self.notified = notified
            self.clock = clock
        }

        /// Drive a peripheral through the discovery handshake to `.active`.
        func bringToActive(_ id: UUID) {
            events.yield(.connected(id: id))
            events.yield(.servicesDiscovered(peripheralID: id, serviceUUIDs: [cscServiceUUID]))
            events.yield(.characteristicsDiscovered(
                peripheralID: id, serviceUUID: cscServiceUUID, characteristicUUIDs: [cscMeasurementUUID]
            ))
        }
    }

    @Test("Combined sensor: discovery drives both roles to active and enables notifications")
    func combinedToActive() async {
        let harness = Harness()
        let id = UUID()

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
        await harness.client.connect(id, [.speed, .cadence])

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
        await harness.client.connect(id, [.speed])

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

    @Test("Cadence-only sensor emits cadence from crank data")
    func cadenceOnly() async {
        let harness = Harness()
        let id = UUID()
        await harness.client.connect(id, [.cadence])

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
        await harness.client.connect(speedID, [.speed])
        await harness.client.connect(comboID, [.cadence])

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
        await harness.client.connect(speedID, [.speed])
        await harness.client.connect(cadenceID, [.cadence])

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
        await harness.client.connect(id, [.speed])
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
        await harness.client.connect(a, [.speed, .cadence])
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
        await harness.client.connect(b, [.speed])
        await harness.client.connect(a, [.speed])

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
        await harness.client.connect(id, [.speed])

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
        await harness.client.connect(id, [.speed, .cadence])

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
        await harness.client.connect(id, [.speed])
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

    @Test("Second discovery is not auto-connected once a peripheral is held")
    func secondDiscoveryNotAutoConnected() async {
        let harness = Harness()
        let first = UUID()
        let second = UUID()

        var speedStates = harness.client.connectionState(.speed).makeAsyncIterator()
        _ = await speedStates.next()   // .disconnected
        await harness.client.startScanning()
        _ = await speedStates.next()   // .scanning

        var connects = harness.connectCalls.makeAsyncIterator()
        harness.events.yield(.discovered(id: first, name: "GSC-10", rssi: -55, services: [cscServiceUUID]))
        #expect(await connects.next() == first)
        #expect(await speedStates.next() == .connecting)

        harness.events.yield(.discovered(id: second, name: "Wahoo RPM", rssi: -50, services: [cscServiceUUID]))
        await Task.yield()
        #expect(harness.connectCount.value == 1)   // second device not grabbed
    }

    @Test("A dedicated speed sensor + a dedicated cadence sensor both end up active")
    func queuedDiscoveryClaimsRoleFreedByCapabilityNarrowing() async {
        let harness = Harness()
        let speedSensor = UUID()
        let cadenceSensor = UUID()

        await harness.client.startScanning()

        var connects = harness.connectCalls.makeAsyncIterator()
        harness.events.yield(.discovered(id: speedSensor, name: "Wahoo Speed", rssi: -55, services: [cscServiceUUID]))
        #expect(await connects.next() == speedSensor)   // optimistically grabs both roles

        // A second sensor shows up before the first's real capability is known —
        // both roles are still nominally held, so it must not be grabbed yet.
        harness.events.yield(.discovered(id: cadenceSensor, name: "Wahoo Cadence", rssi: -50, services: [cscServiceUUID]))
        await Task.yield()
        #expect(harness.connectCount.value == 1)

        harness.bringToActive(speedSensor)

        // First measurement from the speed sensor is wheel-only — reveals it
        // doesn't support cadence, freeing the role for the queued sensor to claim.
        harness.events.yield(.characteristicValueUpdated(
            peripheralID: speedSensor, characteristicUUID: cscMeasurementUUID,
            value: cscPayload(wheelRevs: 100, wheelTime: 0)
        ))
        #expect(await connects.next() == cadenceSensor)
        #expect(harness.connectCount.value == 2)

        harness.bringToActive(cadenceSensor)

        // Each sensor now supplies its own metric independently.
        var speeds = harness.client.speed().makeAsyncIterator()
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

    @Test("Bluetooth permission denied stands down without crashing")
    func permissionDenied() async {
        let harness = Harness()
        let id = UUID()
        await harness.client.connect(id, [.speed, .cadence])

        var speedStates = harness.client.connectionState(.speed).makeAsyncIterator()
        #expect(await speedStates.next() == .connecting)

        harness.events.yield(.stateChanged(.unauthorized))
        #expect(await speedStates.next() == .disconnected)

        await harness.client.startScanning()
        #expect(await speedStates.next() == .scanning)
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
        await client.connect(UUID(), [.speed, .cadence])
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
