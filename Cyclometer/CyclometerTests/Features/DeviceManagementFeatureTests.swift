import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

@MainActor
@Suite("DeviceManagementFeature")
struct DeviceManagementFeatureTests {

    private static let pairedID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private static let availableID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!

    private static func sensor(
        id: UUID,
        name: String?,
        roles: Set<BLECSCClient.SensorRole> = [],
        state: BLECSCClient.ConnectionState? = nil
    ) -> BLECSCClient.DiscoveredSensor {
        .init(id: id, name: name, roles: roles, connectionState: state)
    }

    private func makeStore(
        initialState: DeviceManagementFeature.State = DeviceManagementFeature.State(),
        bleCSCClient: BLECSCClient = .testValue
    ) -> TestStoreOf<DeviceManagementFeature> {
        TestStore(initialState: initialState) {
            DeviceManagementFeature()
        } withDependencies: {
            $0.bleCSCClient = bleCSCClient
        }
    }

    @Test("Appearing starts a pairing scan and pipes the device stream into state")
    func taskStartsScanAndSubscribes() async {
        let (stream, continuation) = AsyncStream<[BLECSCClient.DiscoveredSensor]>.makeStream()
        let scansStarted = LockIsolated(0)
        var ble = BLECSCClient.testValue
        ble.beginPairingScan = { scansStarted.withValue { $0 += 1 } }
        ble.discoveredSensors = { stream }

        let store = makeStore(bleCSCClient: ble)
        await store.send(.task)
        #expect(scansStarted.value == 1)

        let found = [Self.sensor(id: Self.availableID, name: "GSC-10")]
        continuation.yield(found)
        await store.receive(\.devicesUpdated) {
            $0.devices = found
        }

        continuation.finish()
        await store.finish()
    }

    @Test("Leaving the screen ends the pairing scan")
    func onDisappearEndsScan() async {
        let scansEnded = LockIsolated(0)
        var ble = BLECSCClient.testValue
        ble.endPairingScan = { scansEnded.withValue { $0 += 1 } }

        let store = makeStore(bleCSCClient: ble)
        await store.send(.onDisappear)
        await store.finish()

        #expect(scansEnded.value == 1)
    }

    @Test("Pair and unpair forward the tapped peripheral to the client")
    func pairAndUnpairForwardIDs() async {
        let paired = LockIsolated<[UUID]>([])
        let unpaired = LockIsolated<[UUID]>([])
        var ble = BLECSCClient.testValue
        ble.pair = { id in paired.withValue { $0.append(id) } }
        ble.unpair = { id in unpaired.withValue { $0.append(id) } }

        let store = makeStore(bleCSCClient: ble)
        await store.send(.pairButtonTapped(Self.availableID))
        await store.send(.unpairButtonTapped(Self.pairedID))
        await store.finish()

        #expect(paired.value == [Self.availableID])
        #expect(unpaired.value == [Self.pairedID])
    }

    @Test("Devices split into paired and available sections")
    func devicesSplitBySection() {
        let store = makeStore(
            initialState: DeviceManagementFeature.State(
                devices: [
                    Self.sensor(id: Self.pairedID, name: "Wahoo RPM", roles: [.speed, .cadence], state: .active),
                    Self.sensor(id: Self.availableID, name: "GSC-10")
                ]
            )
        )

        #expect(store.state.pairedDevices.map(\.id) == [Self.pairedID])
        #expect(store.state.availableDevices.map(\.id) == [Self.availableID])
    }

    /// A sensor that has been unpaired keeps its row so it can be paired again —
    /// it just moves from Paired to Available.
    @Test("An unpaired sensor moves to the available section rather than vanishing")
    func unpairedSensorStaysListed() async {
        let (stream, continuation) = AsyncStream<[BLECSCClient.DiscoveredSensor]>.makeStream()
        var ble = BLECSCClient.testValue
        ble.discoveredSensors = { stream }

        let store = makeStore(bleCSCClient: ble)
        await store.send(.task)

        let whilePaired = [Self.sensor(id: Self.pairedID, name: "Wahoo RPM", roles: [.speed], state: .active)]
        continuation.yield(whilePaired)
        await store.receive(\.devicesUpdated) { $0.devices = whilePaired }
        #expect(store.state.pairedDevices.count == 1)

        let afterUnpair = [Self.sensor(id: Self.pairedID, name: "Wahoo RPM")]
        continuation.yield(afterUnpair)
        await store.receive(\.devicesUpdated) { $0.devices = afterUnpair }
        #expect(store.state.pairedDevices.isEmpty)
        #expect(store.state.availableDevices.map(\.id) == [Self.pairedID])

        continuation.finish()
        await store.finish()
    }
}
