import ComposableArchitecture

/// TCA dependency for Garmin Varia RTL515 / RCT715 radar data over raw BLE.
/// Protocol: Garmin Radar Data BLE Program.
/// Reference: pycycling RDR module (open-source Python implementation).
/// Note: RearVue 820 excluded — secured BLE protocol.
struct VariaRadarClient {
    var radarTargets:       @Sendable () -> AsyncStream<[RadarTarget]>
    var connect:            @Sendable (String) async throws -> Void   // peripheral UUID string
    var disconnect:         @Sendable () async -> Void
    var pairingStatus:      @Sendable () -> AsyncStream<Bool>
}

extension VariaRadarClient: DependencyKey {
    static let liveValue = VariaRadarClient(
        radarTargets:   { AsyncStream { _ in } },
        connect:        { _ in },
        disconnect:     { },
        pairingStatus:  { AsyncStream { _ in } }
    )
    static let testValue = VariaRadarClient(
        radarTargets:   { AsyncStream { $0.finish() } },
        connect:        { _ in },
        disconnect:     { },
        pairingStatus:  { AsyncStream { $0.finish() } }
    )
}

extension DependencyValues {
    var variaRadarClient: VariaRadarClient {
        get { self[VariaRadarClient.self] }
        set { self[VariaRadarClient.self] = newValue }
    }
}
