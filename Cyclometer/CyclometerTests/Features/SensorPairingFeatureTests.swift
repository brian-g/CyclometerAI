import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

/// S02 — Add Sensors (#107). `DeviceManagementFeature`'s own exhaustive suite
/// (`DeviceManagementFeatureTests`) already covers scanning, pairing, role selection
/// and replace-or-cancel — this only exercises the composition: that `nextButtonTapped`
/// still delegates `.next`, and that an embedded `deviceManagement` action reaches the
/// child reducer and its durable state unchanged.
@MainActor
@Suite("SensorPairingFeature")
struct SensorPairingFeatureTests {

    private static func makeStore() -> TestStoreOf<SensorPairingFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            TestStore(initialState: SensorPairingFeature.State()) {
                SensorPairingFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
                $0.bleCSCClient = .testValue
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
            }
        }
    }

    @Test("Next delegates .next")
    func nextDelegates() async {
        let store = Self.makeStore()

        await store.send(.nextButtonTapped)
        // The device list's pairing scan ends first, while this state still exists (#585).
        await store.receive(\.deviceManagement.onDisappear)
        await store.receive(\.delegate.next)
    }

    /// Nothing outlives S02 to receive the capabilities of a pairing still in flight. Left
    /// alone, the sensor sits connected holding no role, and that slot's later release can
    /// end a Pair the rider starts in Settings (#593).
    @Test("Next releases a pairing still waiting on its capabilities")
    func nextReleasesAnInFlightPairing() async {
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
        let unpaired = LockIsolated<[UUID]>([])
        var ble = BLECSCClient.testValue
        ble.unpair = { id in unpaired.withValue { $0.append(id) } }
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            var state = SensorPairingFeature.State()
            state.deviceManagement.pendingPairing = id
            return TestStore(initialState: state) {
                SensorPairingFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
                $0.bleCSCClient = ble
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
            }
        }

        await store.send(.nextButtonTapped) {
            $0.deviceManagement.pendingPairing = nil
        }
        await store.receive(\.deviceManagement.onDisappear)
        await store.receive(\.delegate.next)
        #expect(unpaired.value == [id])
    }

    @Test("An unpair on the embedded device list writes through to shared preferences")
    func embeddedDeviceManagementActionReachesSharedState() async {
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: { () -> TestStoreOf<SensorPairingFeature> in
            @Shared(.appPreferences) var preferences
            $preferences.withLock {
                $0.pairedSensors = [PairedSensor(peripheralID: id, role: .heartRate, displayName: "Polar H10")]
            }
            return TestStore(initialState: SensorPairingFeature.State()) {
                SensorPairingFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
                $0.bleCSCClient = .testValue
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
            }
        }

        await store.send(.deviceManagement(.unpairButtonTapped(id))) {
            $0.deviceManagement.$preferences.withLock { $0.pairedSensors = [] }
        }
    }
}
