import ComposableArchitecture
import CoreLocation

/// TCA dependency wrapping CoreLocation.
/// BLE sensor speed takes priority; GPS is the fallback per architecture spec.
struct LocationClient {
    var requestAuthorization: @Sendable () async -> Void
    var locationStream:       @Sendable () -> AsyncStream<CLLocation>
    var speedStream:          @Sendable () -> AsyncStream<Double>   // m/s, GPS-derived
}

extension LocationClient: DependencyKey {
    static let liveValue = LocationClient(
        requestAuthorization: { },
        locationStream:       { AsyncStream { _ in } },
        speedStream:          { AsyncStream { _ in } }
    )
    static let testValue = LocationClient(
        requestAuthorization: { },
        locationStream:       { AsyncStream { $0.finish() } },
        speedStream:          { AsyncStream { $0.finish() } }
    )
}

extension DependencyValues {
    var locationClient: LocationClient {
        get { self[LocationClient.self] }
        set { self[LocationClient.self] = newValue }
    }
}
