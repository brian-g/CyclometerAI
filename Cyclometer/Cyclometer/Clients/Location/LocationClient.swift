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
    let altitude: Double              // meters above sea level
    let speed: Double                 // m/s; -1 if invalid
    let horizontalAccuracy: Double    // meters; lower is better
    let heading: Double               // degrees from true north (0–360); -1 if unavailable
    let timestamp: Date
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
}

// MARK: - DependencyKey

extension LocationClient: DependencyKey {
    static let liveValue = LocationClient(
        startUpdates: { LocationManagerState.shared.makeUpdateStream() },
        stopUpdates:  { await LocationManagerState.shared.stopUpdates() }
    )

    static let testValue = LocationClient(
        startUpdates: { AsyncStream { $0.finish() } },
        stopUpdates:  { }
    )
}

extension DependencyValues {
    var locationClient: LocationClient {
        get { self[LocationClient.self] }
        set { self[LocationClient.self] = newValue }
    }
}
