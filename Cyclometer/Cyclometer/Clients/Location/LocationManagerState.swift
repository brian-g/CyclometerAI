import CoreLocation
import os

private let logger = Logger.cyclometer(.location)

/// The app's single `CLLocationManager`, shared by the two clients that need it.
///
/// A singleton for the same reason `BLECentral` is one: authorization is a
/// process-wide fact, and a second manager would be a second delegate reporting the
/// same status while carrying its own background-updates configuration. `LocationClient`
/// consumes it for the position stream; `PermissionsClient` consumes it for the
/// `.locationWhenInUse` domain.
///
/// `@unchecked Sendable`: thread safety is enforced manually — the main queue for all
/// CoreLocation calls, `lock` for continuation storage.
final class LocationManagerState: NSObject, @unchecked Sendable, CLLocationManagerDelegate {

    static let shared = LocationManagerState(makeManager: { CLLocationManager() })

    private var manager: CLLocationManager?
    private var updateContinuations: [Int: AsyncStream<LocationUpdate>.Continuation] = [:]
    private var oneShotContinuations: [Int: CheckedContinuation<Coordinate?, Never>] = [:]
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var authObservers: [Int: AsyncStream<CLAuthorizationStatus>.Continuation] = [:]
    private var isRequestingAuth = false
    private var nextID = 0
    private let lock = NSLock()
    private let makeManager: @MainActor () -> CLLocationManager

    /// Production uses `shared` only, for the reason above, so the factory has no default:
    /// `LocationManagerState()` does not compile, and a second instance takes a deliberate one.
    /// Tests pass a stub manager that never starts location services, so no `kCLErrorDenied`
    /// can arrive and finish a stream mid-assertion (#590).
    init(makeManager: @escaping @MainActor () -> CLLocationManager) {
        self.makeManager = makeManager
        super.init()
    }

    // MARK: Authorization

    /// The current app-wide authorization, read without presenting anything.
    ///
    /// Creating the manager to read this is harmless: `CLLocationManager.init` does not
    /// prompt, only `requestWhenInUseAuthorization()` does. `async` because the manager
    /// is main-actor confined and callers arrive from arbitrary contexts.
    func authorizationStatus() async -> CLAuthorizationStatus {
        await MainActor.run { ensureManager().authorizationStatus }
    }

    func requestAuthorization() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [self] in
                let mgr = ensureManager()
                let current = mgr.authorizationStatus

                if current != .notDetermined {
                    logger.notice("authorization already resolved: \(String(describing: current))")
                    continuation.resume(returning: current)
                    return
                }

                lock.withLock { authContinuation = continuation; isRequestingAuth = true }
                logger.notice("requesting when-in-use authorization")
                mgr.requestWhenInUseAuthorization()
            }
        }
    }

    /// Authorization changes, including those made in iOS Settings while the app was
    /// backgrounded — which is exactly how a rider recovers from a denial, so S01 has
    /// to hear about it without re-prompting.
    ///
    /// Replays the current status on subscribe so a late subscriber is not left blank
    /// until the next change, which may never come.
    func makeAuthorizationStream() -> AsyncStream<CLAuthorizationStatus> {
        let (stream, continuation) = AsyncStream<CLAuthorizationStatus>.makeStream()
        let id = lock.withLock { () -> Int in
            let current = nextID; nextID += 1
            authObservers[current] = continuation
            return current
        }
        continuation.onTermination = { [weak self] _ in
            _ = self?.lock.withLock { self?.authObservers.removeValue(forKey: id) }
        }

        DispatchQueue.main.async { [self] in
            continuation.yield(ensureManager().authorizationStatus)
        }

        return stream
    }

    // MARK: Update stream

    func makeUpdateStream() -> AsyncStream<LocationUpdate> {
        let id = lock.withLock { () -> Int in
            let current = nextID; nextID += 1; return current
        }
        let (stream, continuation) = AsyncStream<LocationUpdate>.makeStream()
        lock.withLock { updateContinuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            _ = self?.lock.withLock { self?.updateContinuations.removeValue(forKey: id) }
        }

        DispatchQueue.main.async { [self] in
            let mgr = ensureManager()
            mgr.startUpdatingLocation()
            logger.notice("location updates started")
        }

        return stream
    }

    func stopUpdates() async {
        let continuations = lock.withLock { () -> [AsyncStream<LocationUpdate>.Continuation] in
            let active = Array(updateContinuations.values)
            updateContinuations.removeAll()
            return active
        }
        for c in continuations { c.finish() }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { [self] in
                manager?.stopUpdatingLocation()
                logger.notice("location updates stopped")
                continuation.resume()
            }
        }
    }


    // MARK: One-shot fix

    /// How long to wait on `requestLocation()` before giving up. The caller only wants a
    /// map centre, so a slow answer is worth less than a prompt nil.
    static let oneShotTimeout: Duration = .seconds(5)

    /// Old enough that the rider could plausibly be somewhere else entirely. Under this,
    /// the cached fix is reused and no hardware starts.
    static let maximumCachedFixAge: TimeInterval = 3600

    /// The rider's position once, for a screen that needs a centre rather than a track —
    /// S19's route map (#193). Nil when location is denied, unavailable, or slow.
    ///
    /// Deliberately *not* built on `startUpdates()` + `stopUpdates()`: `stopUpdates()`
    /// finishes every subscriber's continuation and stops the manager outright, so a
    /// browse screen using that pair would end a recording ride's position stream.
    ///
    /// The whole decision is one step on the main queue, the queue every CoreLocation call
    /// runs on. Checking for a stream anywhere else leaves a gap in which a ride's stream
    /// can open before the request goes out (#614).
    func currentCoordinate(timeout: Duration = LocationManagerState.oneShotTimeout) async -> Coordinate? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Coordinate?, Never>) in
            DispatchQueue.main.async { [self] in
                let mgr = ensureManager()
                let cached = mgr.location.map {
                    (coordinate: Coordinate(latitude: $0.coordinate.latitude,
                                            longitude: $0.coordinate.longitude),
                     age: Date().timeIntervalSince($0.timestamp))
                }

                // CoreLocation usually already holds a recent fix — from a ride, or from
                // another app. Reusing it answers instantly and starts no hardware at all.
                if let cached, cached.age <= Self.maximumCachedFixAge {
                    continuation.resume(returning: cached.coordinate)
                    return
                }

                // `requestLocation()` and `startUpdatingLocation()` are mutually exclusive on
                // one manager: CoreLocation documents that starting either immediately cancels
                // the other. So while a ride is streaming, requesting here would cancel the
                // ride's updates — and a ride ending would cancel this request with no callback
                // at all, stranding the waiter until its timeout. Whatever the stream has
                // already delivered is the only safe answer, at any age: it is being refreshed
                // live. A stream that registers after this check is harmless: its
                // `startUpdatingLocation()` is queued behind this block, so it cancels the
                // request, and its first fix answers the waiter through `didUpdateLocations`.
                guard lock.withLock({ updateContinuations.isEmpty }) else {
                    continuation.resume(returning: cached?.coordinate)
                    return
                }

                let id = lock.withLock { () -> Int in
                    let current = nextID; nextID += 1
                    oneShotContinuations[current] = continuation
                    return current
                }

                // Started *after* registration, so it cannot try to resolve an id the table
                // does not hold yet and strand the continuation forever. Not cancelled on a
                // successful fix: a stale timer finds nothing to remove and dies quietly.
                // It is also what covers a transient CoreLocation error, which the delegate
                // deliberately does not treat as an answer.
                Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    self?.resumeOneShot(id: id, with: nil)
                }

                mgr.requestLocation()
                logger.notice("one-shot location requested")
            }
        }
    }

    /// Removal under the lock is what makes a resume happen exactly once. `requestLocation()`
    /// can report `didUpdateLocations` and then `didFailWithError`, and the timeout races
    /// both — resuming a continuation twice is a crash, not a bug.
    private func resumeOneShot(id: Int, with coordinate: Coordinate?) {
        let continuation = lock.withLock { oneShotContinuations.removeValue(forKey: id) }
        continuation?.resume(returning: coordinate)
    }

    private func drainOneShots(with coordinate: Coordinate?) {
        let pending = lock.withLock { () -> [CheckedContinuation<Coordinate?, Never>] in
            let active = Array(oneShotContinuations.values)
            oneShotContinuations.removeAll()
            return active
        }
        for c in pending { c.resume(returning: coordinate) }
    }

    // MARK: Manager lifecycle

    @MainActor
    private func ensureManager() -> CLLocationManager {
        if let manager { return manager }
        let mgr = makeManager()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        mgr.allowsBackgroundLocationUpdates = true
        mgr.pausesLocationUpdatesAutomatically = false
        mgr.activityType = .fitness
        manager = mgr
        logger.notice("CLLocationManager configured (bestForNavigation, background enabled)")
        return mgr
    }

    // MARK: CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Ahead of the stream-subscriber check below: a one-shot caller is typically the
        // only thing listening, and that guard would return before it was ever answered.
        // The newest fix: CoreLocation orders a batch oldest first.
        if let latest = locations.last {
            drainOneShots(with: Coordinate(latitude: latest.coordinate.latitude,
                                           longitude: latest.coordinate.longitude))
        }

        let continuations = lock.withLock { Array(updateContinuations.values) }
        guard !continuations.isEmpty else { return }

        for location in locations {
            let update = LocationUpdate(location)
            for c in continuations { c.yield(update) }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        logger.notice("authorization changed: \(String(describing: status))")

        // Observers want every transition, including back to .notDetermined after a
        // reset — unlike the one-shot request below, which is waiting for an answer.
        let observers = lock.withLock { Array(authObservers.values) }
        for o in observers { o.yield(status) }

        // CLLocationManager fires this delegate once on creation with the current
        // status. If we just called requestWhenInUseAuthorization(), the initial
        // callback arrives with .notDetermined before the user responds — ignore it.
        guard status != .notDetermined else { return }

        let pending = lock.withLock { () -> CheckedContinuation<CLAuthorizationStatus, Never>? in
            guard isRequestingAuth else { return nil }
            isRequestingAuth = false
            let c = authContinuation
            authContinuation = nil
            return c
        }
        pending?.resume(returning: status)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let nsError = error as NSError
        logger.error("location error: \(nsError.localizedDescription)")

        if nsError.domain == kCLErrorDomain && nsError.code == CLError.denied.rawValue {
            // A denial is final, so it is a real answer for a one-shot waiter. Every other
            // error is not: `kCLErrorLocationUnknown` in particular is routine indoors and
            // on a cold start, and CoreLocation keeps trying afterwards — resuming nil here
            // would abandon a fix that lands a second later. Those wait for the timeout.
            drainOneShots(with: nil)

            let continuations = lock.withLock { () -> [AsyncStream<LocationUpdate>.Continuation] in
                let active = Array(updateContinuations.values)
                updateContinuations.removeAll()
                return active
            }
            for c in continuations { c.finish() }
            logger.warning("location access denied — streams finished")
        }
    }
}
