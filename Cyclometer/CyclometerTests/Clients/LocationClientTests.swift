import Foundation
import Testing
import CoreLocation
@testable import Cyclometer

@Suite("LocationClient")
struct LocationClientTests {

    // MARK: - Model equality

    @Test("Coordinate equality compares latitude and longitude")
    func coordinateEquality() {
        let a = Coordinate(latitude: 43.0731, longitude: -89.4012)
        let b = Coordinate(latitude: 43.0731, longitude: -89.4012)
        let c = Coordinate(latitude: 43.0732, longitude: -89.4012)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("Coordinate is hashable")
    func coordinateHashable() {
        let a = Coordinate(latitude: 43.0731, longitude: -89.4012)
        let b = Coordinate(latitude: 43.0731, longitude: -89.4012)
        let set: Set<Coordinate> = [a, b]
        #expect(set.count == 1)
    }

    @Test("Coordinate bridges to CLLocationCoordinate2D")
    func coordinateBridge() {
        let coord = Coordinate(latitude: 43.0731, longitude: -89.4012)
        let cl = coord.clLocationCoordinate2D
        #expect(cl.latitude == 43.0731)
        #expect(cl.longitude == -89.4012)
    }

    @Test("LocationUpdate equality compares all fields")
    func locationUpdateEquality() {
        let ts = Date(timeIntervalSince1970: 1_000_000)
        let a = LocationUpdate(
            coordinate: Coordinate(latitude: 43.0731, longitude: -89.4012),
            altitude: 280.0,
            speed: 8.5,
            horizontalAccuracy: 5.0,
            heading: 90.0,
            timestamp: ts
        )
        let b = LocationUpdate(
            coordinate: Coordinate(latitude: 43.0731, longitude: -89.4012),
            altitude: 280.0,
            speed: 8.5,
            horizontalAccuracy: 5.0,
            heading: 90.0,
            timestamp: ts
        )
        let c = LocationUpdate(
            coordinate: Coordinate(latitude: 43.0731, longitude: -89.4012),
            altitude: 280.0,
            speed: 9.0,
            horizontalAccuracy: 5.0,
            heading: 90.0,
            timestamp: ts
        )
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - CLLocation mapping (#303)

    private static func clLocation(verticalAccuracy: Double) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.0731, longitude: -89.4012),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: verticalAccuracy,
            course: 90, speed: 8.5, timestamp: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    @Test("an altitude CoreLocation marks invalid arrives as nil, never as its 0 m")
    func invalidAltitudeIsNil() {
        let update = LocationUpdate(Self.clLocation(verticalAccuracy: -1))
        #expect(update.altitude == nil)
        // Nor its -1 accuracy, which could otherwise anchor the barometer (#387).
        #expect(update.verticalAccuracy == nil)
    }

    @Test("a valid altitude arrives as measured, sea level included")
    func validAltitudeIsKept() {
        let update = LocationUpdate(Self.clLocation(verticalAccuracy: 3))
        #expect(update == LocationUpdate(
            coordinate: Coordinate(latitude: 43.0731, longitude: -89.4012),
            altitude: 0, verticalAccuracy: 3, speed: 8.5, horizontalAccuracy: 5, heading: 90,
            timestamp: Date(timeIntervalSince1970: 1_000_000)
        ))
    }

    // MARK: - speedAccuracy (#540)

    private static func clLocation(speedAccuracy: Double) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.0731, longitude: -89.4012),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 3,
            course: 90, courseAccuracy: 5, speed: 8.5, speedAccuracy: speedAccuracy,
            timestamp: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    @Test("a speed accuracy CoreLocation marks invalid arrives as nil")
    func invalidSpeedAccuracyIsNil() {
        let update = LocationUpdate(Self.clLocation(speedAccuracy: -1))
        #expect(update.speedAccuracy == nil)
        // The speed itself is still delivered: it's the dashboard's, only the max is gated.
        #expect(update.speed == 8.5)
    }

    @Test("a valid speed accuracy arrives as measured")
    func validSpeedAccuracyIsKept() {
        #expect(LocationUpdate(Self.clLocation(speedAccuracy: 0.4)).speedAccuracy == 0.4)
        #expect(LocationUpdate(Self.clLocation(speedAccuracy: 0)).speedAccuracy == 0)
    }

    // MARK: - testValue behaviour

    @Test("testValue startUpdates stream completes immediately")
    func testValueStream() async {
        let client = LocationClient.testValue
        var count = 0
        for await _ in client.startUpdates() { count += 1 }
        #expect(count == 0)
    }

    @Test("testValue stopUpdates does not crash")
    func testValueStop() async {
        let client = LocationClient.testValue
        await client.stopUpdates()
    }

    /// Nil rather than a fabricated coordinate: a feature that has not overridden the
    /// dependency should exercise its no-fix branch, which for S19 is the one a rider with
    /// location denied actually sees (#193).
    @Test("testValue currentCoordinate returns no fix")
    func testValueCurrentCoordinate() async {
        #expect(await LocationClient.testValue.currentCoordinate() == nil)
    }
}

// MARK: - One-shot fix (#193)

/// Every test here runs its own `LocationManagerState` over `StubLocationManager`, never
/// `shared` (#615). What the real manager answers depends on the simulator, not the test: a
/// simulator with location granted and a simulated location set has a cached fix, which skips
/// the request entirely. CI's simulator, which has never been asked for authorization, answers
/// every request with `kCLErrorDenied` about 2 s later. With the stub, no fix or denial arrives
/// unless the test delivers one by calling the delegate itself.
///
/// What the one-shot actually risks is its continuation table: a waiter resumed twice traps, and
/// one never resumed hangs forever.
@Suite("LocationManagerState — one-shot fix")
struct LocationOneShotTests {

    private static let fix = CLLocation(latitude: 43.0731, longitude: -89.4012)
    private static let fixCoordinate = Coordinate(latitude: 43.0731, longitude: -89.4012)

    /// Waits until the stub has received `count` `requestLocation()` calls. Each call is made in
    /// the same main-queue step that registers its waiter, so by then every waiter has been
    /// registered (an expired one may already have been answered and removed).
    ///
    /// Generous on purpose, like `effectDrainTimeout`: each request is one main-queue hop away,
    /// but a contended full-suite run can starve this task for tens of seconds.
    private static func waitForRequests(
        _ count: Int, on manager: StubLocationManager,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while await manager.requestLocationCalls < count {
            try #require(ContinuousClock.now < deadline,
                         "the stub never received \(count) requestLocation() calls",
                         sourceLocation: sourceLocation)
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("A request with no fix available resolves nil rather than hanging")
    func timeoutResolvesNil() async {
        let manager = await StubLocationManager()
        let state = LocationManagerState(makeManager: { manager })

        #expect(await state.currentCoordinate(timeout: .milliseconds(200)) == nil)
        // Answered by its timer, not by a cached fix: the request really went out.
        #expect(await manager.requestLocationCalls == 1)
    }

    /// The two callbacks that answer every waiter at once through `drainOneShots`.
    enum DrainingCallback: CaseIterable, CustomTestStringConvertible {
        case fix, denial

        var testDescription: String {
            switch self {
            case .fix: "didUpdateLocations"
            case .denial: "didFailWithError(kCLErrorDenied)"
            }
        }

        /// What a waiter still in the table gets from this callback.
        var answer: Coordinate? {
            switch self {
            case .fix: LocationOneShotTests.fixCoordinate
            case .denial: nil
            }
        }

        fileprivate func deliver(to state: LocationManagerState, from manager: StubLocationManager) {
            switch self {
            case .fix: state.locationManager(manager, didUpdateLocations: [LocationOneShotTests.fix])
            case .denial: state.locationManager(manager, didFailWithError: CLError(.denied))
            }
        }
    }

    /// Each waiter can be answered three times: by its timer, by `drainOneShots`, and by a
    /// second callback (`requestLocation()` can report a fix and then fail). Only removal from
    /// the table under the lock makes the first answer the only one.
    ///
    /// Both orders are set up for certain, without racing the timers:
    /// - **Timer first.** The expired waiters have all been answered by their timers before the
    ///   callback arrives. If `resumeOneShot` resumed without removing, the drain would resume
    ///   them again and trap.
    /// - **Callback first.** The pending waiters' timers are a minute away, longer than the test
    ///   takes, so only the callback can answer them. It is then delivered again; if
    ///   `drainOneShots` didn't empty the table, the repeat would resume them again and trap.
    ///
    /// The ordering is what's pinned, not the lock: no timer runs concurrently with a drain here.
    @Test("Concurrent requests each get exactly one answer", arguments: DrainingCallback.allCases)
    func concurrentRequestsAllResolve(callback: DrainingCallback) async throws {
        let manager = await StubLocationManager()
        let state = LocationManagerState(makeManager: { manager })
        let pendingTimeout: Duration = .seconds(60)
        let start = ContinuousClock.now

        let expired = (0..<4).map { _ in Task { await state.currentCoordinate(timeout: .zero) } }
        let pending = (0..<4).map { _ in Task { await state.currentCoordinate(timeout: pendingTimeout) } }
        try await Self.waitForRequests(8, on: manager)

        for waiter in expired {
            #expect(await waiter.value == nil, "an expired waiter was not answered by its timer")
        }

        callback.deliver(to: state, from: manager)
        callback.deliver(to: state, from: manager)

        for waiter in pending {
            #expect(await waiter.value == callback.answer, "a pending waiter was not answered by the callback")
        }
        // A denial answers nil, as a timer does, so the value alone can't show who answered.
        // The timers started after `start`, so none can have fired inside `pendingTimeout`.
        #expect(ContinuousClock.now - start < pendingTimeout,
                "the pending waiters were answered by their timers, not the callback")
    }

    /// The whole point of the one-shot is that it never touches `stopUpdates()`, which would
    /// end a recording ride's stream. Nor `requestLocation()`, which CoreLocation documents as
    /// not usable concurrently with `startUpdatingLocation()`. Nor the manager's own
    /// `stopUpdatingLocation()`, which would leave the stream open but starved of fixes. This
    /// pins the pairing: a live subscriber survives it.
    ///
    /// On the real manager a denial ~2 s after any request would finish this stream, so under
    /// load it could land mid-test (#590): the reason the suite runs on the stub.
    @Test("Asking for a one-shot leaves an active update stream running")
    func oneShotDoesNotDisturbAnActiveStream() async {
        let manager = await StubLocationManager()
        let state = LocationManagerState(makeManager: { manager })

        let stream = state.makeUpdateStream()
        var iterator = stream.makeAsyncIterator()

        _ = await state.currentCoordinate(timeout: .milliseconds(200))

        // A stop or request the one-shot set off asynchronously gets a window to land in first:
        // checked straight after the return, it would land after the checks and pass unseen.
        await allowStrayCallsToLand()

        // Delivered only if the stream is still open: a finished one yields nil instead.
        let fix = CLLocation(latitude: 43.0731, longitude: -89.4012)
        state.locationManager(manager, didUpdateLocations: [fix])
        let next = await iterator.next()

        #expect(next?.coordinate == Coordinate(latitude: 43.0731, longitude: -89.4012),
                "the one-shot finished a live update stream")
        #expect(await manager.requestLocationCalls == 0,
                "the one-shot requested a fix while streaming, which CoreLocation does not allow")
        #expect(await manager.stopUpdatingLocationCalls == 0,
                "the one-shot stopped the manager's updates under a live stream")
    }

    /// The one ordering the one-shot still allows (#614): its request is out, then a ride's
    /// stream starts. That `startUpdatingLocation()` cancels the request with no callback, so
    /// the waiter must be answered by the stream's first fix rather than its own timeout.
    @Test("A stream that starts after a one-shot's request answers the waiter with its first fix")
    func streamStartingAfterTheRequestAnswersTheWaiter() async throws {
        let manager = await StubLocationManager()
        let state = LocationManagerState(makeManager: { manager })

        // Long enough that only the stream's fix can answer it inside the test, and longer
        // than the deadline below, so a contended run can't time the waiter out first.
        let waiter = Task { await state.currentCoordinate(timeout: .seconds(60)) }

        try await Self.waitForRequests(1, on: manager)

        let stream = state.makeUpdateStream()
        var iterator = stream.makeAsyncIterator()
        let fix = CLLocation(latitude: 43.0731, longitude: -89.4012)
        state.locationManager(manager, didUpdateLocations: [fix])

        let expected = Coordinate(latitude: 43.0731, longitude: -89.4012)
        #expect(await waiter.value == expected, "the stream's fix did not answer the waiter")
        #expect(await iterator.next()?.coordinate == expected)
    }
}

/// A `CLLocationManager` that never starts location services: no update or fix is requested,
/// so no fix and no denial ever come back. Callbacks are driven by calling the delegate
/// directly. Authorization (`authorizationStatus`, `requestWhenInUseAuthorization()`) is not
/// stubbed and still reaches CoreLocation.
@MainActor
private final class StubLocationManager: CLLocationManager {
    private(set) var requestLocationCalls = 0
    private(set) var stopUpdatingLocationCalls = 0

    override var location: CLLocation? { nil }
    override func startUpdatingLocation() {}
    override func stopUpdatingLocation() { stopUpdatingLocationCalls += 1 }
    override func requestLocation() { requestLocationCalls += 1 }
}
