import ComposableArchitecture
import CoreLocation

// MARK: - Models

struct Coordinate: Sendable, Equatable, Hashable {
    let latitude: Double   // WGS 84 degrees
    let longitude: Double  // WGS 84 degrees

    var clLocationCoordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct LocationUpdate: Sendable, Equatable {
    let coordinate: Coordinate
    let altitude: Double?             // meters above sea level; nil when CoreLocation marks it invalid
    /// Metres, one sigma; nil exactly when `altitude` is. Defaulted so a test fix needn't say.
    var verticalAccuracy: Double? = nil
    let speed: Double                 // m/s; -1 if invalid
    let horizontalAccuracy: Double    // meters; lower is better
    let heading: Double               // degrees from true north (0–360); -1 if unavailable
    let timestamp: Date
}

extension LocationUpdate {
    /// A negative `verticalAccuracy` is CoreLocation's mark of an invalid altitude, which it
    /// often reports as 0 m. Dropped here rather than carried as a sentinel, so no reader can
    /// record it: one mid-ride 0 m fix used to reach the GPX `<ele>` and credit a phantom
    /// climb to the ride's energy estimate (#303).
    init(_ location: CLLocation) {
        self.init(
            coordinate: Coordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ),
            altitude: location.verticalAccuracy < 0 ? nil : location.altitude,
            verticalAccuracy: location.verticalAccuracy < 0 ? nil : location.verticalAccuracy,
            speed: location.speed,
            horizontalAccuracy: location.horizontalAccuracy,
            heading: location.course,
            timestamp: location.timestamp
        )
    }
}

// MARK: - LocationClient

/// Position data only. Authorization for `.locationWhenInUse` lives on
/// `PermissionsClient`, which is the app's single authorization surface — callers
/// asking "may I?" and callers asking "where am I?" are different callers, and S01
/// needs the former without starting GPS.
///
/// Both clients share `LocationManagerState.shared`, so there is still exactly one
/// `CLLocationManager`.
struct LocationClient: Sendable {
    var startUpdates: @Sendable () -> AsyncStream<LocationUpdate>
    var stopUpdates: @Sendable () async -> Void
    /// One position, for a screen that wants a map centre rather than a track (S19, #193).
    /// Nil when location is denied, unavailable, or too slow to answer.
    ///
    /// Separate from the pair above because `stopUpdates` is not per-subscriber — it stops
    /// the manager for everyone — so a browse screen must never open and close the stream
    /// while a ride is recording.
    var currentCoordinate: @Sendable () async -> Coordinate?
}

// MARK: - DependencyKey

extension LocationClient: DependencyKey {
    static let liveValue = LocationClient(
        startUpdates: { LocationManagerState.shared.makeUpdateStream() },
        stopUpdates:  { await LocationManagerState.shared.stopUpdates() },
        currentCoordinate: { await LocationManagerState.shared.currentCoordinate() }
    )

    static let testValue = LocationClient(
        startUpdates: { AsyncStream { $0.finish() } },
        stopUpdates:  { },
        currentCoordinate: { nil }
    )
}

extension DependencyValues {
    var locationClient: LocationClient {
        get { self[LocationClient.self] }
        set { self[LocationClient.self] = newValue }
    }
}
