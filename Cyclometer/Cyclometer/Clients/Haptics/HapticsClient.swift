import ComposableArchitecture
import CoreHaptics

/// TCA dependency for eyes-free haptic safety alerts.
/// L0 / L1 / L2 / L3 map to Audio.md alert levels.
struct HapticsClient {
    var playAllClear: @Sendable () async -> Void   // L0 — threat resolved
    var playAdvisory: @Sendable () async -> Void   // L1 — radar connection lost
    var playWarning:  @Sendable () async -> Void   // L2 — vehicle approaching
    var playDanger:   @Sendable () async -> Void   // L3 — immediate threat
    var isAvailable:  @Sendable () -> Bool
}

extension HapticsClient: DependencyKey {
    static let liveValue = HapticsClient(
        playAllClear: { /* CoreHaptics impl */ },
        playAdvisory: { /* CoreHaptics impl */ },
        playWarning:  { /* CoreHaptics impl */ },
        playDanger:   { /* CoreHaptics impl */ },
        isAvailable:  { CHHapticEngine.capabilitiesForHardware().supportsHaptics }
    )
    static let testValue = HapticsClient(
        playAllClear: { },
        playAdvisory: { },
        playWarning:  { },
        playDanger:   { },
        isAvailable:  { true }
    )
}

extension DependencyValues {
    var hapticsClient: HapticsClient {
        get { self[HapticsClient.self] }
        set { self[HapticsClient.self] = newValue }
    }
}
