import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

/// The launch push (#97). None of the three BLE clients holds persistence, so the
/// rider's pairings have to be handed to them before any scan can act on them —
/// and from `AppFeature`, not `DeviceManagementFeature`, so sensors reconnect on
/// launch rather than only while the Sensors screen is open.
///
/// Note this arms the gates rather than connecting anything: `BLECentral.connect`
/// is a no-op for a peripheral CoreBluetooth hasn't discovered yet, and there is no
/// retrieve-by-identifier or state restoration (BLE.md §13). The reconnect happens
/// on the next scan.
@MainActor
@Suite("AppFeature — launch pairing push")
struct AppPairingTests {

    /// One log across all three clients. The point is *which client gets which
    /// record* and in what order — a separate `LockIsolated` per client can only show
    /// that each was called, which is what let two ordering races through review on #67.
    enum ClientCall: Equatable {
        case csc([UUID: Set<SensorRole>])
        case radar(UUID?)
        case hr(UUID?)
    }

    static func makeStore(
        pairedSensors: [PairedSensor],
        into log: LockIsolated<[ClientCall]>
    ) -> TestStoreOf<AppFeature> {
        // Each store gets its own in-memory file system so the rider's real
        // app-preferences.json is neither read nor written, and seeded records cannot
        // leak between tests. Seeding happens in the same scope as the store, otherwise
        // the two would read different storage.
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.pairedSensors = pairedSensors }

            var csc = BLECSCClient.testValue
            csc.setPairedSensors = { map in log.withValue { $0.append(.csc(map)) } }
            var radar = VariaRadarClient.testValue
            radar.setPairedSensor = { id in log.withValue { $0.append(.radar(id)) } }
            var hr = BLEHRClient.testValue
            hr.setPairedSensor = { id in log.withValue { $0.append(.hr(id)) } }

            return TestStore(initialState: AppFeature.State()) {
                AppFeature()
            } withDependencies: {
                $0.bleCSCClient = csc
                $0.variaRadarClient = radar
                $0.bleHRClient = hr
                $0.defaultFileStorage = storage
            }
        }
    }

    @Test("Launch hands each client its own paired records")
    func launchPushesEveryPairedRecordToItsClient() async {
        let radarID = UUID()
        let hrID = UUID()
        let comboID = UUID()
        let log = LockIsolated<[ClientCall]>([])

        let store = Self.makeStore(
            pairedSensors: [
                PairedSensor(peripheralID: radarID, role: .radar, displayName: "Varia RTL515"),
                PairedSensor(peripheralID: hrID, role: .heartRate, displayName: "HRM-Dual"),
                PairedSensor(peripheralID: comboID, role: .speed, displayName: "Wahoo RPM"),
                PairedSensor(peripheralID: comboID, role: .cadence, displayName: "Wahoo RPM"),
            ],
            into: log
        )

        await store.send(.task).finish()

        #expect(log.value == [
            .csc([comboID: [.speed, .cadence]]),
            .radar(radarID),
            .hr(hrID),
        ])
    }

    /// Pushing nil is not a skippable no-op: the client state objects are
    /// process-global, so nil is how a gate left open by an earlier state gets closed.
    @Test("Launch with nothing paired still closes every gate")
    func launchWithNothingPairedStillClosesEveryGate() async {
        let log = LockIsolated<[ClientCall]>([])
        let store = Self.makeStore(pairedSensors: [], into: log)

        await store.send(.task).finish()

        #expect(log.value == [.csc([:]), .radar(nil), .hr(nil)])
    }

    /// `BLECSCClient` only speaks 0x1816, so a radar or strap in its map would be a
    /// peripheral it can never talk to. `AppPreferences.cscAssignments` filters on
    /// `isCSC`; this pins the behaviour from the AppFeature side, where the mistake
    /// would actually be made.
    @Test("A radar record never reaches the CSC client")
    func radarRecordDoesNotReachTheCSCClient() async {
        let radarID = UUID()
        let log = LockIsolated<[ClientCall]>([])

        let store = Self.makeStore(
            pairedSensors: [
                PairedSensor(peripheralID: radarID, role: .radar, displayName: "Varia RTL515")
            ],
            into: log
        )

        await store.send(.task).finish()

        #expect(log.value == [.csc([:]), .radar(radarID), .hr(nil)])
    }
}
