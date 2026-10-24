import ComposableArchitecture
import Foundation

/// A single timestamped cadence reading (rpm) used for the watermark sparkline.
struct CadenceSample: Equatable, Sendable {
    let time: Date
    let rpm: Double
}

@Reducer
struct CadenceFeature {
    /// Wall-clock window of cadence samples retained for the watermark sparkline.
    /// Mirrors `SpeedFeature` — a time window (not a sample count) because BLE CSC
    /// notifications do not arrive at a fixed rate.
    static let historyWindow: TimeInterval = 3600   // last hour
    /// How long cadence may go without a reading before it clears to "--" (BLE.md §6.2). No
    /// GPS-style fallback exists for cadence, so clearing is all there is. Driven by data, not
    /// connection state: a flapping link restarted the old `.reconnecting` grace timer on
    /// every drop and cancelled it on every `.active`, so the last reading held (#456).
    ///
    /// Must outlast `CSCCalculator`'s longest silence on an unbroken link. Sensors notify at
    /// ~1 Hz, and the calculator emits nothing for the first `zeroThreshold − 1` duplicate
    /// frames once the cranks stop (the 3rd emits 0) and nothing for the first pedal stroke
    /// after. That stroke re-primes it and resets the duplicate count, so a single crank turn
    /// mid-coast is three silent frames (re-prime, then two duplicates before the next 0).
    /// That is at most 4 s between readings; 5 s leaves one notification of slack.
    static let staleDataWindow: Duration = .seconds(5)
    /// Longest gap between two readings that is still credited to a zone (or to
    /// coasting). CSC notifications normally arrive about once a second; a longer
    /// gap means the sensor dropped out, and crediting it would invent ride time.
    static let maxCreditedInterval: TimeInterval = 5

    @Dependency(\.date.now) var now
    @Dependency(\.bleCSCClient) var bleCSCClient
    @Dependency(\.continuousClock) var clock

    @ObservableState
    struct State: Equatable {
        var cadenceRPM: Int? = nil
        var connectionState: BLECSCClient.ConnectionState = .disconnected
        var pairedPeripheralId: UUID? = nil
        /// Timestamped cadence samples from the last `historyWindow` seconds.
        var cadenceSamples: [CadenceSample] = []
        /// Count of pedalling readings (rpm > 0) taken while recording; coasting is excluded
        /// so the average reflects effort while actually pedalling.
        var pedalingSampleCount: Int = 0
        /// Running sum of pedalling readings, paired with `pedalingSampleCount`.
        var cadenceSum: Double = 0
        var maxCadenceRPM: Int = 0
        /// Seconds spent pedalling (rpm > 0) at each whole rpm, the reading W5 shows. Kept per
        /// rpm rather than per zone (#79) so `zoneSeconds` sorts it against the zones in effect
        /// when read, as `HeartRateSecondsTally` does for HR. Accumulated as time, not sample
        /// counts, because notifications arrive at irregular intervals.
        var secondsByRPM: [Int: TimeInterval] = [:]
        /// Seconds spent coasting (rpm == 0).
        var coastingSeconds: TimeInterval = 0
        /// Whether the ride is actively recording. Driven by `ActiveRideFeature` from its
        /// `recordingState`: the sensor keeps notifying through a pause or auto-pause, and
        /// none of it belongs to the ride — not the zone/coasting tally, and not the
        /// average or max (#379, PRD: "all sensor recording suspended"). The live reading
        /// and the watermark still follow it.
        var isRecording = false
        /// The rider's S12 cadence zones (#79). A Settings change re-sorts the whole ride's
        /// time, the time before it included.
        @SharedReader(.appPreferences) var preferences

        /// Seconds pedalling in each zone, from `secondsByRPM` against the rider's zones.
        var zoneSeconds: [CadenceZone: TimeInterval] {
            preferences.cadenceZones.zoneSeconds(secondsByRPM)
        }

        /// Average cadence over pedalling time: mean of non-zero rpm readings.
        var averageCadenceRPM: Int {
            pedalingSampleCount > 0
                ? Int((cadenceSum / Double(pedalingSampleCount)).rounded())
                : 0
        }
    }

    enum Action: Equatable {
        case startListening
        case cadenceReceived(Double)
        case bleConnectionChanged(BLECSCClient.ConnectionState)
        case staleDataTimedOut
    }

    private enum CancelID { case staleDataTimer }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startListening:
                return .merge(
                    .run { [bleCSCClient] send in
                        await bleCSCClient.startScanning()
                        for await rpm in bleCSCClient.cadence() {
                            await send(.cadenceReceived(rpm))
                        }
                    },
                    .run { [bleCSCClient] send in
                        for await connectionState in bleCSCClient.connectionState(.cadence) {
                            await send(.bleConnectionChanged(connectionState))
                        }
                    }
                )

            case .cadenceReceived(let rpm):
                guard rpm >= 0 else {
                    state.cadenceRPM = nil
                    return .none
                }
                state.cadenceRPM = Int(rpm.rounded())
                // Left-hold: the time since the previous reading belongs to that
                // reading's state. Read it before appending the new sample.
                if state.isRecording, let previous = state.cadenceSamples.last {
                    let elapsed = now.timeIntervalSince(previous.time)
                    if elapsed > 0, elapsed <= Self.maxCreditedInterval {
                        if previous.rpm > 0 {
                            state.secondsByRPM[Int(previous.rpm.rounded()), default: 0] += elapsed
                        } else {
                            state.coastingSeconds += elapsed
                        }
                    }
                }
                state.cadenceSamples.append(CadenceSample(time: now, rpm: rpm))
                let cutoff = now.addingTimeInterval(-Self.historyWindow)
                state.cadenceSamples.removeAll { $0.time < cutoff }
                if state.isRecording, rpm > 0 {
                    state.pedalingSampleCount += 1
                    state.cadenceSum += rpm
                    state.maxCadenceRPM = max(state.maxCadenceRPM, Int(rpm.rounded()))
                }
                // Each reading restarts the stale-data watchdog. Cancelled explicitly:
                // `cancelInFlight` only cancels once the new task starts, which leaves room
                // for the old timeout to land.
                return .merge(
                    .cancel(id: CancelID.staleDataTimer),
                    .run { send in
                        try await clock.sleep(for: Self.staleDataWindow)
                        await send(.staleDataTimedOut)
                    }
                    .cancellable(id: CancelID.staleDataTimer, cancelInFlight: true)
                )

            case .bleConnectionChanged(let connectionState):
                state.connectionState = connectionState
                switch connectionState {
                case .disconnected:
                    state.cadenceRPM = nil
                    return .cancel(id: CancelID.staleDataTimer)
                case .scanning, .connecting, .connected, .reconnecting, .active:
                    // The stale-data watchdog decides when to clear; a link that flaps
                    // between these says nothing about whether data is arriving.
                    return .none
                }

            case .staleDataTimedOut:
                state.cadenceRPM = nil
                return .none
            }
        }
    }
}
