import ComposableArchitecture
import CoreBluetooth
import Testing
@testable import Cyclometer

@Suite("ScanCallSequence")
struct ScanCallSequenceTests {

    private enum Call: Equatable { case start, stop }

    /// The guarantee #586 needs: a call enqueued second can't reach the transport first, however
    /// long the first takes to land.
    @Test("A call waits for the one enqueued before it, even while that one is held")
    func callsLandInEnqueueOrder() async {
        let gate = CallGate()
        let landed = LockIsolated<[Call]>([])
        var sequence = ScanCallSequence(
            bleClient: BLEClient(
                startScanning: { _ in landed.withValue { $0.append(.start) } },
                stopScanning: { _ in
                    await gate.pass()
                    landed.withValue { $0.append(.stop) }
                },
                connect: { _, _ in },
                disconnect: { _, _ in },
                discoverServices: { _, _ in },
                discoverCharacteristics: { _, _, _ in },
                setNotifyValue: { _, _, _, _ in },
                readValue: { _, _, _ in },
                events: { AsyncStream { $0.finish() } },
                authorization: { .allowedAlways },
                requestAuthorization: { .allowedAlways }
            ),
            serviceUUID: CBUUID(string: "1816")
        )

        gate.arm()
        var reached = gate.reached.makeAsyncIterator()
        let stop = sequence.enqueue(.stop)
        await reached.next()
        let start = sequence.enqueue(.start)

        // Unchained, the start would land here.
        await allowStrayCallsToLand()
        #expect(landed.value.isEmpty)

        gate.open()
        await stop.value
        await start.value
        #expect(landed.value == [.stop, .start])
    }
}
