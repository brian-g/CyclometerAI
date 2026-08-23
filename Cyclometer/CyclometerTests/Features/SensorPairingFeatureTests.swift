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
        await store.receive(\.delegate.next)
    }

    @Test("An unpair on the embedded device list writes through to shared preferences")
    func embeddedDeviceManagementActionReachesSharedState() async {
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let storage = FileStorage.inMemory
        let store = await withDependencies {
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
