import ComposableArchitecture
import CoreBluetooth
import CoreLocation
import CoreMotion
import Foundation
import HealthKit
import Testing
@testable import Cyclometer

@Suite("PermissionsClient")
struct PermissionsClientTests {

    // MARK: - PermissionState

    @Test("isGranted covers both location grant levels and nothing else")
    func isGranted() {
        #expect(PermissionState.granted.isGranted)
        #expect(PermissionState.grantedAlways.isGranted)
        #expect(!PermissionState.notDetermined.isGranted)
        #expect(!PermissionState.denied.isGranted)
        #expect(!PermissionState.restricted.isGranted)
        #expect(!PermissionState.unavailable.isGranted)
    }

    @Test("Every domain is enumerable — S01 renders four rows from allCases")
    func domainsAreEnumerable() {
        #expect(PermissionDomain.allCases.count == 4)
        #expect(PermissionDomain.allCases.contains(.bluetooth))
        #expect(PermissionDomain.allCases.contains(.locationWhenInUse))
        #expect(PermissionDomain.allCases.contains(.motion))
        #expect(PermissionDomain.allCases.contains(.health))
    }

    // MARK: - Bluetooth mapping

    @Test("Bluetooth authorization maps to the four determinate states")
    func bluetoothMapping() {
        #expect(PermissionsClient.state(cb: .notDetermined) == .notDetermined)
        #expect(PermissionsClient.state(cb: .allowedAlways) == .granted)
        #expect(PermissionsClient.state(cb: .denied) == .denied)
        #expect(PermissionsClient.state(cb: .restricted) == .restricted)
    }

    // MARK: - Location mapping

    @Test("Location distinguishes When In Use from Always")
    func locationDistinguishesGrantLevels() {
        #expect(PermissionsClient.state(cl: .authorizedWhenInUse) == .granted)
        #expect(PermissionsClient.state(cl: .authorizedAlways) == .grantedAlways)
        #expect(PermissionsClient.state(cl: .authorizedWhenInUse).isGranted)
        #expect(PermissionsClient.state(cl: .authorizedAlways).isGranted)
    }

    @Test("Location refusal states map through unchanged")
    func locationRefusalMapping() {
        #expect(PermissionsClient.state(cl: .notDetermined) == .notDetermined)
        #expect(PermissionsClient.state(cl: .denied) == .denied)
        #expect(PermissionsClient.state(cl: .restricted) == .restricted)
    }

    // MARK: - Motion mapping

    @Test("Motion reports unavailable when the device has no activity hardware")
    func motionUnavailableWinsOverStatus() {
        // isAvailable is checked first and overrides everything — on Simulator the
        // status sits at .notDetermined forever, which S01 would read as "not yet
        // granted" and never enable Next.
        for status: CMAuthorizationStatus in [.notDetermined, .authorized, .denied, .restricted] {
            #expect(PermissionsClient.state(cm: status, isAvailable: false) == .unavailable)
        }
    }

    @Test("Motion maps its four states when the hardware is present")
    func motionMapping() {
        #expect(PermissionsClient.state(cm: .notDetermined, isAvailable: true) == .notDetermined)
        #expect(PermissionsClient.state(cm: .authorized, isAvailable: true) == .granted)
        #expect(PermissionsClient.state(cm: .denied, isAvailable: true) == .denied)
        #expect(PermissionsClient.state(cm: .restricted, isAvailable: true) == .restricted)
    }

    // MARK: - HealthKit mapping

    @Test("HealthKit never reports denied — read authorization is undeterminable")
    func healthNeverReportsDenied() {
        // The core honesty requirement: HealthKit deliberately will not tell an app a
        // read was refused, so no input may produce .denied. S01 must not draw a red X.
        for status: HKAuthorizationRequestStatus in [.unknown, .shouldRequest, .unnecessary] {
            #expect(PermissionsClient.state(health: status, isAvailable: true) != .denied)
            #expect(PermissionsClient.state(health: status, isAvailable: false) != .denied)
        }
    }

    @Test("HealthKit maps request status to what is actually knowable")
    func healthMapping() {
        #expect(PermissionsClient.state(health: .shouldRequest, isAvailable: true) == .notDetermined)
        #expect(PermissionsClient.state(health: .unnecessary, isAvailable: true) == .granted)
        #expect(PermissionsClient.state(health: .unknown, isAvailable: true) == .notDetermined)
        #expect(PermissionsClient.state(health: .unnecessary, isAvailable: false) == .unavailable)
    }

    @Test("HealthKit type sets match PRD §9.4 and the S10 workout write")
    func healthTypeSets() {
        #expect(PermissionsClient.healthReadTypes.contains(HKQuantityType(.heartRate)))
        #expect(PermissionsClient.healthReadTypes.contains(HKQuantityType(.restingHeartRate)))
        #expect(PermissionsClient.healthReadTypes.contains(HKCharacteristicType(.dateOfBirth)))
        #expect(PermissionsClient.healthShareTypes.contains(HKWorkoutType.workoutType()))
    }

    // MARK: - testValue

    @Test("testValue grants everything and finishes its stream immediately")
    func testValueShape() async {
        let client = PermissionsClient.testValue
        for domain in PermissionDomain.allCases {
            #expect(await client.status(domain) == .granted)
            #expect(await client.request(domain) == .granted)
        }
        var count = 0
        for await _ in client.statuses() { count += 1 }
        #expect(count == 0)
    }

    // MARK: - Mock: seeding and scripting

    @Test("Mock defaults every unlisted domain to notDetermined")
    func mockDefaultsToNotDetermined() async {
        let client = PermissionsClient.mock()
        for domain in PermissionDomain.allCases {
            #expect(await client.status(domain) == .notDetermined)
        }
    }

    @Test("Mock is scriptable per domain")
    func mockIsScriptablePerDomain() async {
        let client = PermissionsClient.mock(initial: [
            .bluetooth: .granted,
            .locationWhenInUse: .denied,
            .motion: .unavailable,
        ])
        #expect(await client.status(.bluetooth) == .granted)
        #expect(await client.status(.locationWhenInUse) == .denied)
        #expect(await client.status(.motion) == .unavailable)
        #expect(await client.status(.health) == .notDetermined)
    }

    @Test("Mock answers each domain independently on request")
    func mockAnswersPerDomain() async {
        let client = PermissionsClient.mock(
            onRequest: { $0 == .health ? .denied : .granted }
        )
        #expect(await client.request(.bluetooth) == .granted)
        #expect(await client.request(.health) == .denied)
    }

    @Test("A granted request persists — status reflects the answer afterwards")
    func mockRequestPersists() async {
        let client = PermissionsClient.mock()
        #expect(await client.status(.motion) == .notDetermined)
        _ = await client.request(.motion)
        #expect(await client.status(.motion) == .granted)
    }

    // MARK: - Already-resolved short-circuit (AC 4)

    @Test(
        "Requesting an already-resolved domain presents no prompt and returns current state",
        arguments: [PermissionState.denied, .restricted, .unavailable, .granted, .grantedAlways]
    )
    func requestDoesNotPromptWhenResolved(seeded: PermissionState) async {
        let promptCount = LockIsolated(0)
        let client = PermissionsClient.mock(
            initial: [.bluetooth: seeded],
            onRequest: { _ in
                promptCount.withValue { $0 += 1 }
                return .granted
            }
        )

        let result = await client.request(.bluetooth)

        #expect(result == seeded)
        #expect(promptCount.value == 0)
    }

    @Test("Only notDetermined reaches a prompt")
    func requestPromptsWhenNotDetermined() async {
        let promptCount = LockIsolated(0)
        let client = PermissionsClient.mock(
            initial: [.bluetooth: .notDetermined],
            onRequest: { _ in
                promptCount.withValue { $0 += 1 }
                return .granted
            }
        )

        #expect(await client.request(.bluetooth) == .granted)
        #expect(promptCount.value == 1)

        // Second request finds it resolved and must not prompt again.
        #expect(await client.request(.bluetooth) == .granted)
        #expect(promptCount.value == 1)
    }

    // MARK: - Change stream

    @Test("Stream replays all four domains to a late subscriber")
    func streamReplaysOnSubscribe() async {
        let client = PermissionsClient.mock(initial: [
            .bluetooth: .granted,
            .locationWhenInUse: .denied,
        ])

        var seen: [PermissionDomain: PermissionState] = [:]
        for await change in client.statuses() {
            seen[change.domain] = change.state
            if seen.count == PermissionDomain.allCases.count { break }
        }

        #expect(seen[.bluetooth] == .granted)
        #expect(seen[.locationWhenInUse] == .denied)
        #expect(seen[.motion] == .notDetermined)
        #expect(seen[.health] == .notDetermined)
    }

    @Test("Stream delivers a change made after subscribe")
    func streamDeliversSubsequentChanges() async {
        let client = PermissionsClient.mock()
        var iterator = client.statuses().makeAsyncIterator()

        // Drain the four replayed values.
        for _ in PermissionDomain.allCases { _ = await iterator.next() }

        _ = await client.request(.health)

        let change = await iterator.next()
        #expect(change == PermissionChange(domain: .health, state: .granted))
    }

    // MARK: - Live wiring
    //
    // These run the real client against the real frameworks — the part the pure
    // mapping tests above cannot reach: the main-actor hop into CoreLocation, the
    // CoreMotion availability probe, and the HealthKit request-status query. They
    // assert agreement with the framework rather than a fixed value, so they hold on
    // Simulator and on a device alike. `.testValue` stands in for BLE so no
    // permission prompt is raised by running the suite.

    @Test("Live motion status agrees with CoreMotion availability")
    func liveMotionStatus() async {
        let client = PermissionsClient.live(bleClient: .testValue)
        let state = await client.status(.motion)

        if CMMotionActivityManager.isActivityAvailable() {
            #expect(state != .unavailable)
        } else {
            // The Simulator path. Without this the domain would sit at notDetermined
            // and S01's Next button could never enable.
            #expect(state == .unavailable)
        }
    }

    @Test("Live health status is never a denial")
    func liveHealthStatus() async {
        let client = PermissionsClient.live(bleClient: .testValue)
        #expect(await client.status(.health) != .denied)
    }

    @Test("Live location status agrees with CoreLocation, without prompting")
    func liveLocationStatus() async {
        let client = PermissionsClient.live(bleClient: .testValue)
        let state = await client.status(.locationWhenInUse)
        let expected = PermissionsClient.state(
            cl: await LocationManagerState.shared.authorizationStatus()
        )
        #expect(state == expected)
    }

    @Test("Live bluetooth status reflects the injected transport")
    func liveBluetoothStatus() async {
        let client = PermissionsClient.live(bleClient: .testValue)
        #expect(await client.status(.bluetooth) == .granted)
    }

    /// A `BLEClient` whose authorization answer is scriptable and whose event stream is
    /// driven by the test — enough to prove the observe → re-read → broadcast wiring
    /// without a radio.
    private static func scriptableBLE(
        authorization: LockIsolated<CBManagerAuthorization>,
        events: AsyncStream<BLEEvent>
    ) -> BLEClient {
        BLEClient(
            startScanning: { _ in },
            stopScanning: { _ in },
            connect: { _, _ in },
            disconnect: { _, _ in },
            discoverServices: { _, _ in },
            discoverCharacteristics: { _, _, _ in },
            setNotifyValue: { _, _, _, _ in },
            readValue: { _, _, _ in },
            events: { events },
            authorization: { authorization.value },
            requestAuthorization: { authorization.value }
        )
    }

    /// Awaits the next change for one domain, skipping the other three.
    ///
    /// The four replayed values interleave freely with observer yields, so
    /// position-based assertions on this stream are racy. Filtering by domain is
    /// order-independent and carries no wall-clock budget.
    ///
    /// **The tests below carried `.timeLimit` traits until #117; they are gone because
    /// there is nothing left for them to bound.** The traits guarded against a hang that
    /// could only come from the frameworks in the path, and `.fixed` probes take those
    /// out. They also had to go: a deadline is subject to the same contention it guards
    /// against. CI run 32037935488 stalled an entire simulator clone — `isGranted()` and
    /// `bluetoothMapping()`, pure enum switches with no I/O, took 90.3 seconds each, and
    /// the job logged `Failed to launch app with identifier: com.xavier.cyclometer`.
    /// Every test on that clone blocked and then completed at once; the only casualty
    /// was the one carrying a 60-second deadline, killed rather than merely delayed. A
    /// later passing run showed `isGranted()` at 544 seconds, so no threshold was ever
    /// going to be safe.
    private static func nextChange(
        for domain: PermissionDomain,
        from iterator: inout AsyncStream<PermissionChange>.Iterator
    ) async -> PermissionState? {
        while let change = await iterator.next() {
            if change.domain == domain { return change.state }
        }
        return nil
    }

    @Test("An authorization change made outside the app reaches subscribers")
    func externalChangeIsBroadcast() async {
        // The Settings-recovery path: the rider denies, leaves for iOS Settings, grants,
        // and comes back. Nothing in the app called request(), so the only way the row
        // updates is a framework callback the client is actually listening to.
        let authorization = LockIsolated<CBManagerAuthorization>(.denied)
        let (events, eventContinuation) = AsyncStream<BLEEvent>.makeStream()
        let client = PermissionsClient.live(
            bleClient: Self.scriptableBLE(authorization: authorization, events: events),
            probes: .fixed()
        )

        var iterator = client.statuses().makeAsyncIterator()

        // Wait for the seeded denial to be replayed before changing anything, so what
        // follows is observed rather than merely read at subscribe time.
        #expect(await Self.nextChange(for: .bluetooth, from: &iterator) == .denied)

        authorization.setValue(.allowedAlways)
        eventContinuation.yield(.stateChanged(.poweredOn))

        #expect(await Self.nextChange(for: .bluetooth, from: &iterator) == .granted)
    }

    @Test("A framework callback carrying no change is not rebroadcast")
    func unchangedCallbackIsNotRebroadcast() async {
        // centralManagerDidUpdateState fires for radio power too, which is not a
        // permission change. Without the transition filter, S01 would rebuild its rows
        // on every Bluetooth toggle.
        let authorization = LockIsolated<CBManagerAuthorization>(.allowedAlways)
        let (events, eventContinuation) = AsyncStream<BLEEvent>.makeStream()
        let client = PermissionsClient.live(
            bleClient: Self.scriptableBLE(authorization: authorization, events: events),
            probes: .fixed()
        )

        var iterator = client.statuses().makeAsyncIterator()
        #expect(await Self.nextChange(for: .bluetooth, from: &iterator) == .granted)

        // Radio cycles twice, permission untouched — neither may reach the stream.
        eventContinuation.yield(.stateChanged(.poweredOff))
        eventContinuation.yield(.stateChanged(.poweredOn))
        // Then a real change. Asserting that *this* is the next Bluetooth value the
        // subscriber sees proves the two above were filtered, with no sleeping: were
        // they rebroadcast, the next value would be a repeated .granted instead.
        authorization.setValue(.denied)
        eventContinuation.yield(.stateChanged(.poweredOn))

        #expect(await Self.nextChange(for: .bluetooth, from: &iterator) == .denied)
    }

    /// The replay contract through the *live* state machine rather than the mock — the
    /// mock has its own replay implementation, so `streamReplaysOnSubscribe` above does
    /// not cover this code path.
    ///
    /// Probed rather than live (#117): a subscriber must see all four domains, and each
    /// one's value must be what its source reported. Distinct seeded states prove the
    /// second half, which the old version could not — against the real frameworks every
    /// domain tended to report the same thing, so a replay that mixed up domains would
    /// have passed.
    @Test("The live stream replays every domain with the value its source reported")
    func liveStreamReplays() async {
        let client = PermissionsClient.live(
            bleClient: .testValue,
            probes: .fixed(location: .denied, motion: .unavailable, health: .granted)
        )

        var seen: [PermissionDomain: PermissionState] = [:]
        for await change in client.statuses() {
            seen[change.domain] = change.state
            if seen.count == PermissionDomain.allCases.count { break }
        }

        #expect(seen[.bluetooth] == .granted)          // .testValue's authorization
        #expect(seen[.locationWhenInUse] == .denied)
        #expect(seen[.motion] == .unavailable)
        #expect(seen[.health] == .granted)
    }

    @Test("A request that presents no prompt yields nothing to the stream")
    func resolvedRequestDoesNotYield() async {
        let client = PermissionsClient.mock(initial: [.bluetooth: .denied, .health: .notDetermined])
        var iterator = client.statuses().makeAsyncIterator()
        for _ in PermissionDomain.allCases { _ = await iterator.next() }

        // Short-circuits, so the next stream element must come from the health request
        // rather than from this one.
        _ = await client.request(.bluetooth)
        _ = await client.request(.health)

        let change = await iterator.next()
        #expect(change?.domain == .health)
    }
}
