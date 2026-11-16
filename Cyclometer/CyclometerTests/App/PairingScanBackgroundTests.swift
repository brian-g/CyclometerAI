import Testing
import Foundation
import CoreBluetooth
import ComposableArchitecture
import SwiftUI
@testable import Cyclometer

/// The transport's call log, and what it adds up to. At file scope, outside the suite's
/// `@MainActor`, the same way the client suites build their transports.
private final class Radio: Sendable {
    enum Call: Equatable {
        case start(CBUUID)
        case stop(CBUUID)
    }

    let calls: LockIsolated<[Call]>
    let transport: BLEClient

    init() {
        let calls = LockIsolated<[Call]>([])
        self.calls = calls
        self.transport = BLEClient(
            startScanning: { uuids in calls.withValue { $0 += uuids.map(Call.start) } },
            stopScanning: { uuids in calls.withValue { $0 += uuids.map(Call.stop) } },
            connect: { _, _ in },
            disconnect: { _, _ in },
            discoverServices: { _, _ in },
            discoverCharacteristics: { _, _, _ in },
            setNotifyValue: { _, _, _, _ in },
            readValue: { _, _, _ in },
            events: { AsyncStream { _ in } },
            authorization: { .allowedAlways },
            requestAuthorization: { .allowedAlways }
        )
    }

    /// The service UUIDs currently being scanned for, replaying the log the way
    /// `BLECentral`'s requested-services set applies it.
    var scanning: Set<CBUUID> {
        calls.value.reduce(into: Set<CBUUID>()) { on, call in
            switch call {
            case .start(let uuid): on.insert(uuid)
            case .stop(let uuid): on.remove(uuid)
            }
        }
    }

    var starts: Int { calls.value.filter { if case .start = $0 { true } else { false } }.count }
}

/// #418: a pairing scan left open as the app went to the background kept all three clients
/// scanning — and the app awake — until the rider came back.
///
/// Driven through `AppFeature` with the three **live** clients over one fake transport, so
/// what is asserted is the radio itself: which service UUIDs are being scanned for after each
/// step. A mocked client could only show that `setPairingScansSuspended` was called, not that
/// the holders' begin/end pairs and the suspension add up to a radio that is off. The holders
/// are the real ones too — the Start sheet's presentation in `AppFeature`, and S11's `.task` /
/// `.onDisappear` reached through `SettingsFeature` — because presentation wiring is only
/// visible from the parent (`StartSheetPresentationTests`).
@MainActor
@Suite("AppFeature — pairing scans in the background")
struct PairingScanBackgroundTests {

    private static let allKinds: Set<CBUUID> = Set(SensorKind.allCases.map(\.serviceUUID))

    private static func makeStore(radio: Radio) -> TestStoreOf<AppFeature> {
        let storage = FileStorage.inMemory
        let transport = radio.transport
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            let store = TestStore(initialState: AppFeature.State()) {
                AppFeature()
            } withDependencies: {
                $0.bleCSCClient = .live(bleClient: transport, clock: TestClock())
                $0.variaRadarClient = .live(bleClient: transport, clock: TestClock())
                $0.bleHRClient = .live(bleClient: transport)
                $0.defaultFileStorage = storage
                // S11's sweep timer: never advanced, so only the screen's own begin/end run.
                $0.continuousClock = TestClock()
            }
            // The rest of `scenePhaseChanged` (S12's dim preview, its Live Activities reread)
            // is covered elsewhere; here only the radio is under test.
            store.exhaustivity = .off(showSkippedAssertions: false)
            return store
        }
    }

    // MARK: - Start sheet

    @Test("Start sheet up: backgrounding stops every pairing scan, returning restarts it")
    func startSheetBackgroundForegroundDismiss() async {
        let radio = Radio()
        let store = Self.makeStore(radio: radio)

        await store.send(.startRideButtonTapped)
        #expect(radio.scanning == Self.allKinds)

        await store.send(.scenePhaseChanged(.inactive))
        await store.send(.scenePhaseChanged(.background))
        #expect(radio.scanning.isEmpty)

        await store.send(.scenePhaseChanged(.inactive))
        await store.send(.scenePhaseChanged(.active))
        #expect(radio.scanning == Self.allKinds)

        await store.send(.startSheet(.dismiss))
        await store.finish()
        #expect(radio.scanning.isEmpty)
    }

    /// The rider can't touch the sheet while backgrounded, but the parent can close it — a
    /// resumed ride does (`resumableRideFetched`). The release lands on a suspended client and
    /// must leave nothing to be restarted on return.
    @Test("Start sheet closed while backgrounded: nothing restarts on return")
    func startSheetDismissedWhileBackgrounded() async {
        let radio = Radio()
        let store = Self.makeStore(radio: radio)

        await store.send(.startRideButtonTapped)
        await store.send(.scenePhaseChanged(.background))
        await store.send(.startSheet(.dismiss))
        let startsBeforeReturn = radio.starts

        await store.send(.scenePhaseChanged(.active))
        await store.finish()
        #expect(radio.scanning.isEmpty)
        #expect(radio.starts == startsBeforeReturn)
    }

    // MARK: - Sensors list (S11)

    @Test("Sensors list open: backgrounding stops every pairing scan, returning restarts it")
    func sensorsBackgroundForegroundLeave() async {
        let radio = Radio()
        let store = Self.makeStore(radio: radio)

        await store.send(.settings(.deviceManagement(.task)))
        #expect(radio.scanning == Self.allKinds)

        await store.send(.scenePhaseChanged(.background))
        #expect(radio.scanning.isEmpty)

        await store.send(.scenePhaseChanged(.active))
        #expect(radio.scanning == Self.allKinds)

        await store.send(.settings(.deviceManagement(.onDisappear)))
        await store.finish()
        #expect(radio.scanning.isEmpty)
    }

    // MARK: - Nothing held, transient phases, a ride

    @Test("Nothing holding a scan: a round trip to the background touches the radio not at all")
    func nothingHeldIsSilent() async {
        let radio = Radio()
        let store = Self.makeStore(radio: radio)

        await store.send(.scenePhaseChanged(.inactive))
        await store.send(.scenePhaseChanged(.background))
        await store.send(.scenePhaseChanged(.inactive))
        await store.send(.scenePhaseChanged(.active))
        await store.finish()

        #expect(radio.calls.value.isEmpty)
    }

    /// Notification Centre, the app switcher and an incoming call go to `.inactive` and back
    /// without leaving the app. Restarting every scan on each would be churn for nothing.
    @Test("Inactive and back, repeatedly, leaves an open pairing scan running untouched")
    func transientInactiveLeavesTheScan() async {
        let radio = Radio()
        let store = Self.makeStore(radio: radio)

        await store.send(.startRideButtonTapped)
        let callsWithSheetUp = radio.calls.value

        for _ in 0..<3 {
            await store.send(.scenePhaseChanged(.inactive))
            await store.send(.scenePhaseChanged(.active))
        }
        #expect(radio.calls.value == callsWithSheetUp)

        await store.send(.startSheet(.dismiss))
        await store.finish()
        #expect(radio.scanning.isEmpty)
    }

    /// BLE.md §13.3: the ride scans in the background on purpose. The Sensors list is the one
    /// pairing-scan holder reachable mid-ride (the Start sheet refuses to open over one), and
    /// suspending it must not take the ride's scan down with it — nor may the ride's scan be
    /// left held up once the list is gone.
    @Test("A ride's scan survives backgrounding with the Sensors list open")
    func rideScanSurvivesBackgrounding() async {
        let radio = Radio()
        let store = Self.makeStore(radio: radio)
        // The ride's ambient scan, as `ActiveRideFeature` starts it.
        await store.dependencies.bleCSCClient.startScanning()
        await store.dependencies.variaRadarClient.startScanning()
        await store.dependencies.bleHRClient.startScanning()
        await store.send(.settings(.deviceManagement(.task)))

        await store.send(.scenePhaseChanged(.background))
        #expect(radio.scanning == Self.allKinds)

        await store.send(.scenePhaseChanged(.active))
        await store.send(.settings(.deviceManagement(.onDisappear)))
        await store.finish()
        #expect(radio.scanning == Self.allKinds)

        // The ride ends: nothing else wants the radio.
        await store.dependencies.bleCSCClient.stopScanning()
        await store.dependencies.variaRadarClient.stopScanning()
        await store.dependencies.bleHRClient.stopScanning()
        #expect(radio.scanning.isEmpty)
    }
}
