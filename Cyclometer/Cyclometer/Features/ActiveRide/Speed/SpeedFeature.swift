import ComposableArchitecture
import Foundation

/// A single timestamped speed reading (m/s) used for the watermark sparkline.
struct SpeedSample: Equatable, Sendable {
    let time: Date
    let mps: Double
}

extension Array where Element == SpeedSample {
    /// At most `resolution` samples, each the mean time and speed of a contiguous bucket — so a
    /// downsampled series still sits on the time axis it was recorded on (W2 plots two series
    /// against one axis, #140). Returned unchanged when already within `resolution`.
    func bucketAveraged(to resolution: Int) -> [SpeedSample] {
        guard count > resolution else { return self }
        return (0..<resolution).map { i in
            // Integer edges: `Double(count) / resolution` scaled back up can land one short of
            // `count` (e.g. 123 at 60) and drop the newest sample.
            let slice = self[(i * count / resolution)..<((i + 1) * count / resolution)]
            let n = Double(slice.count)
            let time = slice.reduce(0) { $0 + $1.time.timeIntervalSinceReferenceDate } / n
            return SpeedSample(
                time: Date(timeIntervalSinceReferenceDate: time),
                mps: slice.reduce(0) { $0 + $1.mps } / n
            )
        }
    }
}

@Reducer
struct SpeedFeature {
    /// Wall-clock window of speed samples retained for the watermark sparkline.
    /// A time window (not a sample count) because CoreLocation does not emit at
    /// a fixed rate.
    static let historyWindow: TimeInterval = 3600   // last hour
    /// Maximum points plotted in the watermark; raw samples are downsampled to
    /// this many buckets so memory and render stay bounded over a full hour.
    static let watermarkResolution = 60
    /// GPS fallback delay after a BLE disconnection (PRD §8.4).
    static let fallbackDelay: Duration = .seconds(5)
    /// How long the source-switch banner stays visible before auto-dismissing.
    static let bannerDismissDelay: Duration = .seconds(4)

    static func gpsFallbackBannerText(sensorName: String?) -> String {
        "Switch to GPS for speed — \(sensorName ?? "Speed sensor") disconnected"
    }

    @Dependency(\.date.now) var now
    @Dependency(\.bleCSCClient) var bleCSCClient
    @Dependency(\.continuousClock) var clock

    @ObservableState
    struct State: Equatable {
        /// Read-only here: Settings pushes changes to the CSC client directly, so
        /// this is only the value applied when a ride starts.
        @SharedReader(.appPreferences) var preferences
        var speedMPS: Double? = nil
        var activeSpeedSource: SensorSource = .none
        var connectionState: BLECSCClient.ConnectionState = .disconnected
        var pairedPeripheralId: UUID? = nil
        /// GPS shadow value, kept live even while BLE is the displayed source,
        /// so a fallback has something to promote to immediately.
        var latestGPSSpeedMPS: Double? = nil
        /// Advertised name of the currently paired Speed-role sensor, for the
        /// fallback banner. Nil if unpaired or the peripheral advertised none.
        var pairedSensorName: String? = nil
        /// Transient source-switch banner text; nil means hidden.
        var sourceSwitchBanner: String? = nil
        /// Timestamped speed samples from the last `historyWindow` seconds.
        var speedSamples: [SpeedSample] = []

        /// Watermark series (m/s), downsampled to ≤ `watermarkResolution` points
        /// by averaging contiguous buckets.
        var watermarkSamples: [Double] {
            speedSamples.bucketAveraged(to: SpeedFeature.watermarkResolution).map(\.mps)
        }
    }

    enum Action: Equatable {
        case startListening
        case gpsSpeedReceived(Double)
        case bleSpeedReceived(Double)
        case bleConnectionChanged(BLECSCClient.ConnectionState)
        case bleSensorNameChanged(String?)
        case bleFallbackTimedOut
        case bannerDismissed
    }

    private enum CancelID {
        case fallbackTimer
        case bannerTimer
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startListening:
                return .merge(
                    .run { [bleCSCClient, mm = state.preferences.wheelCircumferenceMM] send in
                        // Applied before scanning so the rider's configured wheel
                        // size is in place before the first measurement lands.
                        await bleCSCClient.setWheelCircumference(mm)
                        await bleCSCClient.startScanning()
                        for await mps in bleCSCClient.speed() {
                            await send(.bleSpeedReceived(mps))
                        }
                    },
                    .run { [bleCSCClient] send in
                        for await connectionState in bleCSCClient.connectionState(.speed) {
                            await send(.bleConnectionChanged(connectionState))
                        }
                    },
                    .run { [bleCSCClient] send in
                        for await name in bleCSCClient.sensorName(.speed) {
                            await send(.bleSensorNameChanged(name))
                        }
                    }
                )

            case .bleSpeedReceived(let mps):
                state.speedMPS = mps
                state.activeSpeedSource = .bleWheel
                appendSample(mps, to: &state)
                // Real data flowing back IS the "automatic promotion on reconnect" —
                // no separate promotion action needed.
                return .cancel(id: CancelID.fallbackTimer)

            case .bleConnectionChanged(let connectionState):
                state.connectionState = connectionState
                switch connectionState {
                case .active:
                    // Optimistic cancel, mirrors ActiveRideFeature's radar `.active`
                    // handling rather than waiting for the next bleSpeedReceived.
                    return .cancel(id: CancelID.fallbackTimer)
                case .reconnecting:
                    guard state.activeSpeedSource == .bleWheel else { return .none }
                    return .run { send in
                        try await clock.sleep(for: Self.fallbackDelay)
                        await send(.bleFallbackTimedOut)
                    }
                    .cancellable(id: CancelID.fallbackTimer, cancelInFlight: true)
                case .disconnected:
                    guard state.activeSpeedSource == .bleWheel else {
                        return .cancel(id: CancelID.fallbackTimer)
                    }
                    return .merge(
                        .cancel(id: CancelID.fallbackTimer),
                        fallBackToGPS(&state)
                    )
                case .scanning, .connecting, .connected:
                    return .none
                }

            case .bleSensorNameChanged(let name):
                state.pairedSensorName = name
                return .none

            case .bleFallbackTimedOut:
                guard state.activeSpeedSource == .bleWheel else { return .none }
                return fallBackToGPS(&state)

            case .bannerDismissed:
                state.sourceSwitchBanner = nil
                return .none

            case .gpsSpeedReceived(let speed):
                guard speed >= 0 else {
                    state.latestGPSSpeedMPS = nil
                    guard state.activeSpeedSource != .bleWheel else { return .none }
                    state.speedMPS = nil
                    state.activeSpeedSource = .none
                    return .none
                }
                state.latestGPSSpeedMPS = speed
                // BLE has priority (PRD §8.4); while it's active, GPS is a silent
                // shadow value that doesn't touch the displayed speed.
                guard state.activeSpeedSource != .bleWheel else { return .none }
                state.speedMPS = speed
                state.activeSpeedSource = .gps
                appendSample(speed, to: &state)
                return .none
            }
        }
    }

    private func appendSample(_ mps: Double, to state: inout State) {
        state.speedSamples.append(SpeedSample(time: now, mps: mps))
        let cutoff = now.addingTimeInterval(-Self.historyWindow)
        state.speedSamples.removeAll { $0.time < cutoff }
    }

    private func fallBackToGPS(_ state: inout State) -> Effect<Action> {
        state.activeSpeedSource = state.latestGPSSpeedMPS != nil ? .gps : .none
        state.speedMPS = state.latestGPSSpeedMPS
        state.sourceSwitchBanner = Self.gpsFallbackBannerText(sensorName: state.pairedSensorName)
        return .run { send in
            try await clock.sleep(for: Self.bannerDismissDelay)
            await send(.bannerDismissed)
        }
        .cancellable(id: CancelID.bannerTimer, cancelInFlight: true)
    }
}
