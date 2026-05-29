import Testing
import ComposableArchitecture
@testable import Cyclometer

@Suite("RideMetricsFeature")
struct RideMetricsTests {

    @Test("Initial speed is zero")
    func initialSpeedIsZero() async {
        let store = TestStore(initialState: RideMetricsFeature.State()) {
            RideMetricsFeature()
        }
        #expect(store.state.speedKPH == 0.0)
    }

    @Test("Speed update reflects in state")
    func speedUpdate() async {
        let store = TestStore(initialState: RideMetricsFeature.State()) {
            RideMetricsFeature()
        }
        await store.send(.speedUpdated(28.4)) {
            $0.speedKPH = 28.4
        }
    }

    @Test("Start ride sets isRiding")
    func startRide() async {
        let store = TestStore(initialState: RideMetricsFeature.State()) {
            RideMetricsFeature()
        }
        await store.send(.startRideTapped) {
            $0.isRiding = true
            $0.isPaused = false
        }
    }

    @Test("Pause ride sets isPaused")
    func pauseRide() async {
        let store = TestStore(initialState: RideMetricsFeature.State()) {
            RideMetricsFeature()
        }
        await store.send(.startRideTapped) { $0.isRiding = true }
        await store.send(.pauseRideTapped) { $0.isPaused = true }
    }

    @Test("HR update computes correct zone via Karvonen")
    func hrZoneUpdate() async {
        // maxHR=190, restingHR=55, HRR=135
        // 183 bpm → 95% HRR → Zone 5
        var state = RideMetricsFeature.State()
        state.maxHeartRate     = 190
        state.restingHeartRate = 55
        let store = TestStore(initialState: state) { RideMetricsFeature() }
        await store.send(.heartRateUpdated(183)) {
            $0.heartRateBPM = 183
            $0.hrZone       = 5
        }
    }

    @Test("Elapsed tick increments only when riding and not paused")
    func elapsedTick() async {
        var state = RideMetricsFeature.State()
        state.isRiding = true
        state.isPaused = false
        let store = TestStore(initialState: state) { RideMetricsFeature() }
        await store.send(.elapsedTick) { $0.elapsedSeconds = 1 }
    }
}
