import Foundation

extension HealthKitClient {

    /// Deterministic values for `TestStore` and previews — no `HKHealthStore` touched.
    ///
    /// Unlike `PermissionsClient.mock`, there is no "answer once" transition to model
    /// here: every closure just hands back whatever it was scripted with.
    static func mock(
        restingHeartRate: Int? = nil,
        dateOfBirth: DateComponents? = nil,
        heartRateSamples: [Int] = [],
        onRequestAuthorization: @escaping @Sendable () async throws -> Void = { }
    ) -> HealthKitClient {
        HealthKitClient(
            requestAuthorization:  onRequestAuthorization,
            fetchRestingHeartRate: { restingHeartRate },
            fetchDateOfBirth:      { dateOfBirth },
            heartRateStream: {
                AsyncStream { continuation in
                    for bpm in heartRateSamples { continuation.yield(bpm) }
                    continuation.finish()
                }
            }
        )
    }
}
