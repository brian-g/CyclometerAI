import ComposableArchitecture
import HealthKit

/// TCA dependency for HealthKit.
/// maxHeartRate and restingHeartRate drive Karvonen HR zone computation.
/// Manual entry in Settings is the fallback when HealthKit is unavailable.
struct HealthKitClient {
    var requestAuthorization:  @Sendable () async throws -> Void
    var fetchMaxHeartRate:     @Sendable () async throws -> Int
    var fetchRestingHeartRate: @Sendable () async throws -> Int
    var heartRateStream:       @Sendable () -> AsyncStream<Int>     // live BPM from Watch / HR strap
}

extension HealthKitClient: DependencyKey {
    static let liveValue = HealthKitClient(
        requestAuthorization:  { },
        fetchMaxHeartRate:     { 190 },
        fetchRestingHeartRate: { 55 },
        heartRateStream:       { AsyncStream { _ in } }
    )
    static let testValue = HealthKitClient(
        requestAuthorization:  { },
        fetchMaxHeartRate:     { 190 },
        fetchRestingHeartRate: { 55 },
        heartRateStream:       { AsyncStream { $0.finish() } }
    )
}

extension DependencyValues {
    var healthKitClient: HealthKitClient {
        get { self[HealthKitClient.self] }
        set { self[HealthKitClient.self] = newValue }
    }
}
