import Foundation
import Testing
import ComposableArchitecture
@testable import Cyclometer

/// With the `audio` background mode, a running audio engine keeps iOS from suspending the app, so
/// the ride's end has to stop it along with the sensors and location.
@MainActor
@Suite("Ride end releases the audio session")
struct RideEndAudioTests {
    private static let testDate = Date(timeIntervalSince1970: 1_000_000)

    @Test("Finishing a ride stops the audio engine")
    func finishingARideStopsAudio() async {
        let stops = LockIsolated(0)
        let ride = RideSummaryUpdate(
            rideId: UUID(), recordingState: .active, durationSeconds: 600, distanceMeters: 4000,
            averageSpeedMPS: 6, maxSpeedMPS: 12, averageHeartRateBPM: nil, maxHeartRateBPM: nil,
            averageCadenceRPM: nil, maxCadenceRPM: nil, vehiclePassCount: 0
        )
        let store = TestStore(initialState: ActiveRideFeature.State(resuming: ride)) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(Self.testDate)
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = .mock()
            $0.audioClient.stop = { stops.withValue { $0 += 1 } }
        }
        // About the audio teardown, not the rest of the ride-end pipeline (`RideEndFailureTests`).
        store.exhaustivity = .off

        await store.send(.pauseTapped)
        #expect(stops.value == 0)
        await store.send(.finishTapped)
        await store.send(.finishAlert(.presented(.confirmFinish)))
        await expectEventually { stops.value == 1 }
        await store.skipInFlightEffects(strict: false)
    }
}
