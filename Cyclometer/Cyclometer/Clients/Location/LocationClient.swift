import ComposableArchitecture
import CoreLocation
import os

private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "location")

// MARK: - Models

struct Coordinate: Sendable, Equatable, Hashable {
    let latitude: Double
    let longitude: Double

    var clLocationCoordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct LocationUpdate: Sendable, Equatable {
    let coordinate: Coordinate
    let altitude: Double
    let speed: Double              // m/s; -1 if invalid
    let horizontalAccuracy: Double
    let heading: Double            // degrees; -1 if unavailable
    let timestamp: Date
}

// MARK: - LocationClient

struct LocationClient: Sendable {
    var requestAuthorization: @Sendable () async -> CLAuthorizationStatus
    var startUpdates: @Sendable () -> AsyncStream<LocationUpdate>
    var stopUpdates: @Sendable () async -> Void
}

// MARK: - DependencyKey

extension LocationClient: DependencyKey {
    static let liveValue: LocationClient = {
        let state = LocationManagerState()
        return LocationClient(
            requestAuthorization: { await state.requestAuthorization() },
            startUpdates:         { state.makeUpdateStream() },
            stopUpdates:          { await state.stopUpdates() }
        )
    }()

    static let testValue = LocationClient(
        requestAuthorization: { .authorizedWhenInUse },
        startUpdates:         { AsyncStream { $0.finish() } },
        stopUpdates:          { }
    )
}

extension DependencyValues {
    var locationClient: LocationClient {
        get { self[LocationClient.self] }
        set { self[LocationClient.self] = newValue }
    }
}

// MARK: - Live implementation

private final class LocationManagerState: NSObject, @unchecked Sendable, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var updateContinuations: [Int: AsyncStream<LocationUpdate>.Continuation] = [:]
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var isRequestingAuth = false
    private var nextID = 0
    private let lock = NSLock()

    // MARK: Authorization

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
