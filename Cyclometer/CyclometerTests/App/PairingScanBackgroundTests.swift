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
    /// Peripherals passed to `connect`, and (peripheral, owner) pairs passed to `disconnect` (#585).
    let connects: LockIsolated<[UUID]>
    let disconnects: LockIsolated<[Disconnect]>
    let transport: BLEClient
    /// One continuation per `events()` subscriber — each client subscribes once, from its own
    /// task — so an event reaches every client, as `BLECentral` delivers it.
    private let subscribers: LockIsolated<[AsyncStream<BLEEvent>.Continuation]>

    struct Disconnect: Equatable {
        let id: UUID
        let owner: String
    }

    init() {
        let calls = LockIsolated<[Call]>([])
        let connects = LockIsolated<[UUID]>([])
        let disconnects = LockIsolated<[Disconnect]>([])
        let subscribers = LockIsolated<[AsyncStream<BLEEvent>.Continuation]>([])
        self.calls = calls
        self.connects = connects
        self.disconnects = disconnects
        self.subscribers = subscribers
        self.transport = BLEClient(
            startScanning: { uuids in calls.withValue { $0 += uuids.map(Call.start) } },
            stopScanning: { uuids in calls.withValue { $0 += uuids.map(Call.stop) } },
            connect: { id, _ in connects.withValue { $0.append(id) } },
            disconnect: { id, owner in disconnects.withValue { $0.append(Disconnect(id: id, owner: owner)) } },
            discoverServices: { _, _ in },
            discoverCharacteristics: { _, _, _ in },
            setNotifyValue: { _, _, _, _ in },
            readValue: { _, _, _ in },
            events: { AsyncStream { continuation in subscribers.withValue { $0.append(continuation) } } },
            authorization: { .allowedAlways },
            requestAuthorization: { .allowedAlways }
        )
    }

    /// Every client is listening. They subscribe from tasks of their own, so an event sent
    /// before this holds can reach none of them.
    var allClientsSubscribed: Bool { subscribers.value.count == SensorKind.allCases.count }

    func send(_ event: BLEEvent) {
        for continuation in subscribers.value { continuation.yield(event) }
    }

    func dropped(_ id: UUID, by owner: String) -> Bool {
        disconnects.value.contains(Disconnect(id: id, owner: owner))
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

    func starts(of uuid: CBUUID) -> Int { calls.value.filter { $0 == .start(uuid) }.count }
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

    private static func makeStore(
        radio: Radio,
        csc: BLECSCClient? = nil,
        radar: VariaRadarClient? = nil
    ) -> TestStoreOf<AppFeature> {
        let storage = FileStorage.inMemory
        let transport = radio.transport
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            let store = TestStore(initialState: AppFeature.State()) {
                AppFeature()
            } withDependencies: {
                $0.bleCSCClient = csc ?? .live(bleClient: transport, clock: TestClock())
                $0.variaRadarClient = radar ?? .live(bleClient: transport, clock: TestClock())
                $0.bleHRClient = .live(bleClient: transport)
                $0.defaultFileStorage = storage
                // S11's sweep timer: never advanced, so only the screen's own begin/end run.
                $0.continuousClock = TestClock()
                // What a ride started and finished through `AppFeature` needs, as in
                // `RideSummaryPresentationTests`.
                $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
                $0.uuid = .incrementing
                $0.locationClient = .testValue
                $0.hapticsClient = .testValue
                $0.persistenceClient = .mock()
                $0.healthKitClient = .testValue
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

    // MARK: - Start sheet connections (#585)

    nonisolated private static let cscSensor = UUID()
    nonisolated private static let radarUnit = UUID()

    /// The rider's paired CSC sensor and radar, both awake: the Start sheet's pairing scan
    /// finds and connects them.
    private static func connectPairedSensorsUnderTheSheet(
        _ store: TestStoreOf<AppFeature>, _ radio: Radio,
        csc: BLECSCClient, radar: VariaRadarClient
    ) async {
        await csc.setPairedSensors([cscSensor: [.speed, .cadence]])
        await radar.setPairedSensor(radarUnit)
        await expectEventually { radio.allClientsSubscribed }

        await store.send(.startRideButtonTapped)
        radio.send(.discovered(id: cscSensor, name: "Wahoo SPEED", rssi: -55, services: [SensorKind.speedCadence.serviceUUID]))
        radio.send(.discovered(id: radarUnit, name: "Varia RTL515", rssi: -60, services: [SensorKind.radar.serviceUUID]))
        await expectEventually { Set(radio.connects.value) == [cscSensor, radarUnit] }
    }

    /// Cancel with no ride: what the sheet connected goes with it, so nothing is left for a
    /// reconnect ladder to redial when a sensor sleeps.
    @Test("Start sheet cancelled: the sensors it connected are disconnected")
    func startSheetCancelDropsItsConnections() async {
        let radio = Radio()
        let csc = BLECSCClient.live(bleClient: radio.transport, clock: TestClock())
        let radar = VariaRadarClient.live(bleClient: radio.transport, clock: TestClock())
        let store = Self.makeStore(radio: radio, csc: csc, radar: radar)
        await Self.connectPairedSensorsUnderTheSheet(store, radio, csc: csc, radar: radar)

        await store.send(.startSheet(.dismiss))
        await store.finish()
        #expect(radio.dropped(Self.cscSensor, by: "csc"))
        #expect(radio.dropped(Self.radarUnit, by: "radar"))
    }

    /// Start: the ride begins with the sheet's connections. CSC's ride scan skips (every
    /// paired role is held) and the radar's skips (not `.disconnected`), so only the ride flag,
    /// set before the sheet's release, keeps them.
    @Test("Start sheet → Start: the sensors it connected stay connected into the ride")
    func startSheetStartKeepsItsConnections() async {
        let radio = Radio()
        let liveCSC = BLECSCClient.live(bleClient: radio.transport, clock: TestClock())
        let liveRadar = VariaRadarClient.live(bleClient: radio.transport, clock: TestClock())
        // Count the sheet's releases, so "nothing was dropped" is asserted after them.
        let released = LockIsolated<Set<SensorKind>>([])
        var csc = liveCSC
        csc.endPairingScan = {
            await liveCSC.endPairingScan()
            released.withValue { _ = $0.insert(.speedCadence) }
        }
        var radar = liveRadar
        radar.endPairingScan = {
            await liveRadar.endPairingScan()
            released.withValue { _ = $0.insert(.radar) }
        }
        let store = Self.makeStore(radio: radio, csc: csc, radar: radar)
        await Self.connectPairedSensorsUnderTheSheet(store, radio, csc: csc, radar: radar)

        await store.send(.startSheet(.presented(.delegate(.startRide(rideId: UUID(0), route: nil)))))
        await store.receive(\.activeRide.task)
        await expectEventually { released.value == [.speedCadence, .radar] }
        #expect(!radio.dropped(Self.cscSensor, by: "csc"))
        #expect(!radio.dropped(Self.radarUnit, by: "radar"))
        await store.skipInFlightEffects()
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

    /// The rider tapped Pair and left Sensors before the 0x2A5C answer: that is the last
    /// release, so the interrogation is dropped with everything else (#585). Coming back must
    /// end the pairing it left in flight, or every later Pair tap is refused until relaunch
    /// (#577 review). `interrogationWasReleased` does it from the replayed device list.
    @Test("Leaving Sensors mid-interrogation drops it, and Pair works on return")
    func leavingSensorsMidInterrogationThenPairingAgain() async {
        let radio = Radio()
        let store = Self.makeStore(radio: radio)
        let candidate = UUID()
        await expectEventually { radio.allClientsSubscribed }

        await store.send(.settings(.deviceManagement(.task)))
        radio.send(.discovered(id: candidate, name: "Wahoo RPM", rssi: -55, services: [SensorKind.speedCadence.serviceUUID]))
        await Self.waitFor(store) { $0.settings.deviceManagement.devices.contains { $0.id == candidate } }

        await store.send(.settings(.deviceManagement(.pairButtonTapped(candidate))))
        #expect(store.state.settings.deviceManagement.pendingPairing == candidate)
        await Self.waitFor(store) {
            $0.settings.deviceManagement.sources[.speedCadence]?
                .first { $0.id == candidate }?.connectionState != nil
        }

        await store.send(.settings(.deviceManagement(.onDisappear)))
        await expectEventually { radio.dropped(candidate, by: "csc") }

        await store.send(.settings(.deviceManagement(.task)))
        await Self.waitFor(store) { $0.settings.deviceManagement.pendingPairing == nil }

        await store.send(.settings(.deviceManagement(.pairButtonTapped(candidate))))
        #expect(store.state.settings.deviceManagement.pendingPairing == candidate)
        await expectEventually { radio.connects.value == [candidate, candidate] }

        await store.send(.settings(.deviceManagement(.onDisappear)))
        await store.finish()
    }

    /// Wait until the store's state satisfies `condition`. `TestStore.state` shows an
    /// effect's action only once it has been received, so each pass takes in whatever has
    /// arrived; `expectEventually`'s `@Sendable` condition can't read main-actor state anyway.
    private static func waitFor(
        _ store: TestStoreOf<AppFeature>,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: (AppFeature.State) -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while clock.now < deadline {
            await store.skipReceivedActions(strict: false)
            if condition(store.state) { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Condition never held within 10 seconds", sourceLocation: sourceLocation)
    }

    // MARK: - After a ride

    /// The issue's own sequence, end to end: a ride starts with no speed/cadence sensor
    /// connected — so `BLECSCClient.startScanning` starts cold and sets CSC's ambient flag —
    /// and is finished; the rider opens the Sensors list and pockets the phone. Finish has to
    /// clear every client's ambient flag (CSC's since #417), or backgrounding finds it set,
    /// keeps that client scanning as if a ride still wanted it, and the issue recurs for CSC.
    @Test("After a ride that started with no CSC sensor, backgrounding with Sensors open stops all three")
    func afterARideBackgroundingStopsEveryScan() async {
        let radio = Radio()
        let store = Self.makeStore(radio: radio)
        let allKinds = Self.allKinds   // a local, for the `@Sendable` conditions below

        await store.send(.startRideButtonTapped)
        await store.send(.startSheet(.presented(.delegate(.startRide(rideId: UUID(0), route: nil)))))
        await store.receive(\.activeRide.task)
        // Each service started twice — the sheet's pairing scan, then the ride's own — and
        // still on once the sheet's scan is released: the ride holds all three ambient scans.
        await expectEventually {
            SensorKind.allCases.allSatisfy { radio.starts(of: $0.serviceUUID) >= 2 }
                && radio.scanning == allKinds
        }

        await store.send(.activeRide(.pauseTapped))
        await store.send(.activeRide(.finishTapped))
        await store.send(.activeRide(.finishAlert(.presented(.confirmFinish))))
        #expect(store.state.activeRide == nil)
        await expectEventually { radio.scanning.isEmpty }

        await store.send(.settings(.deviceManagement(.task)))
        await expectEventually { radio.scanning == allKinds }

        await store.send(.scenePhaseChanged(.background))
        await expectEventually { radio.scanning.isEmpty }

        await store.send(.scenePhaseChanged(.active))
        await expectEventually { radio.scanning == allKinds }

        await store.send(.settings(.deviceManagement(.onDisappear)))
        await expectEventually { radio.scanning.isEmpty }
        // The Rides tab's post-finish reload waits on a clock this test never advances.
        await store.skipInFlightEffects()
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
