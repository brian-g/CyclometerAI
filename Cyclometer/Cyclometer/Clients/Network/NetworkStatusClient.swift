import ComposableArchitecture
import Network

/// Whether the device has a usable network right now (#204), so a screen whose request failed can
/// say "Offline" rather than only that it failed.
///
/// Asked after a failure, never polled. WeatherKit's `WeatherError` has no offline case (only
/// `permissionDenied` and `unknown`), so the failed request itself can't say why; the system's
/// network path can.
struct NetworkStatusClient: Sendable {
    /// True when no network path is usable: airplane mode, or neither Wi-Fi nor cellular. A
    /// network that is up but reaches nothing (a captive portal) still counts as online.
    var isOffline: @Sendable () async -> Bool
}

extension NetworkStatusClient: DependencyKey {
    static let liveValue: NetworkStatusClient = NetworkStatusClient(isOffline: {
        let monitor = NWPathMonitor()
        defer { monitor.cancel() }
        // Iterating starts the monitor, and its first path is the current one. A cancelled task
        // ends the sequence, which reads as online: the caller's plainer message.
        for await path in monitor {
            return path.status != .satisfied
        }
        return false
    })

    /// Online, so a failure test reads as a plain failure unless it asks for `offline`.
    static let testValue: NetworkStatusClient = NetworkStatusClient(isOffline: { false })

    static let previewValue: NetworkStatusClient = testValue

    static let offline: NetworkStatusClient = NetworkStatusClient(isOffline: { true })
}

extension DependencyValues {
    var networkStatus: NetworkStatusClient {
        get { self[NetworkStatusClient.self] }
        set { self[NetworkStatusClient.self] = newValue }
    }
}
