import CoreLocation
import os

private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "location")

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

    static let shared = LocationManagerState()

    private var manager: CLLocationManager?
    private var updateContinuations: [Int: AsyncStream<LocationUpdate>.Continuation] = [:]
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var authObservers: [Int: AsyncStream<CLAuthorizationStatus>.Continuation] = [:]
    private var isRequestingAuth = false
    private var nextID = 0
    private let lock = NSLock()

    override private init() { super.init() }

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

    // MARK: Manager lifecycle

    @MainActor
    private func ensureManager() -> CLLocationManager {
        if let manager { return manager }
        let mgr = CLLocationManager()
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
        let continuations = lock.withLock { Array(updateContinuations.values) }
        guard !continuations.isEmpty else { return }

        for location in locations {
            let update = LocationUpdate(
                coordinate: Coordinate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                ),
                altitude: location.altitude,
                speed: location.speed,
                horizontalAccuracy: location.horizontalAccuracy,
                heading: location.course,
                timestamp: location.timestamp
            )
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
