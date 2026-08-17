import ComposableArchitecture
import HealthKit

/// TCA dependency for HealthKit. **Unimplemented — lands with M5.** Nothing in the
/// app reads it yet.
///
/// Resting heart rate feeds the Karvonen zone computation as the middle term of
/// `RiderProfile`'s `override ?? healthKit ?? default` resolution (DataModel.md §3.5).
/// A manual override in S12 wins over it; the app stores nothing otherwise.
///
/// **There is deliberately no `fetchMaxHeartRate`.** HealthKit has no max-heart-rate
/// type — only `heartRate`, `restingHeartRate`, `walkingHeartRateAverage`,
/// `heartRateVariabilitySDNN` and `heartRateRecoveryOneMinute`. A `.discreteMax` query
/// over historical `heartRate` samples returns *highest ever observed*, which
/// understates any rider who has not gone near their limit wearing a watch, so it is
/// not used. Max HR comes from the 220 − age estimate built on the `dateOfBirth`
/// characteristic, or from manual entry (PRD §8.5, §9.4). A stub promising otherwise
/// stood here until #96 and misled the plan for that issue.
struct HealthKitClient {
    var requestAuthorization:  @Sendable () async throws -> Void
    var fetchRestingHeartRate: @Sendable () async throws -> Int?
    /// For the 220 − age max estimate. `nil` when the rider has not set one.
    var fetchDateOfBirth:      @Sendable () async throws -> DateComponents?
    var heartRateStream:       @Sendable () -> AsyncStream<Int>     // live BPM from Watch / HR strap
}

extension HealthKitClient: DependencyKey {
    /// `nil` rather than a plausible-looking number: an unimplemented read has no
    /// value, and `RiderProfile` resolution already treats absence as "fall through
    /// to the default". Returning 55 here — as this stub did before #96 — would have
    /// silently beaten the corrected 60 default the moment M5 wired it up.
    static let liveValue = HealthKitClient(
        requestAuthorization:  { },
        fetchRestingHeartRate: { nil },
        fetchDateOfBirth:      { nil },
        heartRateStream:       { AsyncStream { _ in } }
    )
    static let testValue = HealthKitClient(
        requestAuthorization:  { },
        fetchRestingHeartRate: { nil },
        fetchDateOfBirth:      { nil },
        heartRateStream:       { AsyncStream { $0.finish() } }
    )
}

extension DependencyValues {
    var healthKitClient: HealthKitClient {
        get { self[HealthKitClient.self] }
        set { self[HealthKitClient.self] = newValue }
    }
}
