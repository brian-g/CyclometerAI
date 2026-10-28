import ComposableArchitecture
import Foundation

/// A single timestamped speed reading (m/s) used for the watermark sparkline.
struct SpeedSample: Equatable, Sendable {
    let time: Date
    let mps: Double
}

extension SpeedSample: TimedSample {
    var value: Double { mps }
    init(time: Date, value: Double) { self.init(time: time, mps: value) }
}

@Reducer
struct SpeedFeature {
    /// Wall-clock window of speed samples retained for the watermark sparkline.
    /// A time window (not a sample count) because CoreLocation does not emit at
    /// a fixed rate.
    static let historyWindow: TimeInterval = 3600   // last hour
    /// Maximum points W2 plots per series; raw samples are downsampled to this many
    /// buckets so memory and render stay bounded over a full hour.
    static let watermarkResolution = 60
    /// How long BLE speed may go without a reading before the display falls back to GPS
    /// (PRD §8.4). Driven by data, not connection state: a flapping link restarted the old
    /// `.reconnecting` timer on every drop and cancelled it on every `.active`, so the last
    /// reading held for up to 58 s (#390).
    ///
    /// Must outlast `CSCCalculator`'s longest silence on a healthy sensor. Sensors notify at
    /// ~1 Hz, and the calculator emits nothing for the first `zeroThreshold − 1` duplicate
    /// frames of a stop (the 3rd emits 0) and nothing for the first moving frame after one.
    /// That frame re-primes it and resets the duplicate count, so a single wheel turn at a stop
    /// (creeping at a light) is three silent frames: re-prime, then two duplicates before the
    /// next 0. That is at most 4 s between readings; 5 s leaves one notification of slack.
    ///
    /// The bound holds only on an unbroken link. Every drop resets the calculator, so after a
    /// reconnect it re-primes (one silent frame), and at a stop it then needs `zeroThreshold`
    /// duplicates before emitting 0. Any drop at a stop, or one that takes over ~2 s to
    /// reconnect while moving, therefore falls back here even on a healthy sensor.
    static let staleDataWindow: Duration = .seconds(5)
    /// Minimum time between fallback banners. A flapping sensor falls back every cycle;
    /// the source still switches each time, but the rider is told once per window (#390).
    static let fallbackBannerCooldown: TimeInterval = 300
    /// How long the source-switch banner stays visible before auto-dismissing.
    static let bannerDismissDelay: Duration = .seconds(4)

    /// "Disconnected" only when the link is gone: the stale-data watchdog mostly fires with
    /// the link still up and only the readings stopped (#390).
    static func gpsFallbackBannerText(sensorName: String?, isTerminal: Bool = false) -> String {
        "Switched to GPS for speed — \(sensorName ?? "Speed sensor") \(isTerminal ? "disconnected" : "not responding")"
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
        /// When the fallback banner last showed, for `fallbackBannerCooldown`.
        var lastFallbackBannerAt: Date? = nil
        /// Timestamped speed samples from the last `historyWindow` seconds.
        var speedSamples: [SpeedSample] = []
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
                // no separate promotion action needed. Each reading also restarts the
                // stale-data watchdog. Cancelled explicitly: `cancelInFlight` only cancels
                // once the new task starts, which leaves room for the old timeout to land.
                return .merge(
                    .cancel(id: CancelID.fallbackTimer),
                    .run { send in
                        try await clock.sleep(for: Self.staleDataWindow)
                        await send(.bleFallbackTimedOut)
                    }
                    .cancellable(id: CancelID.fallbackTimer, cancelInFlight: true)
                )

            case .bleConnectionChanged(let connectionState):
                state.connectionState = connectionState
                switch connectionState {
                case .disconnected:
                    guard state.activeSpeedSource == .bleWheel else {
                        return .cancel(id: CancelID.fallbackTimer)
                    }
                    return .merge(
                        .cancel(id: CancelID.fallbackTimer),
                        fallBackToGPS(&state, isTerminal: true)
                    )
                case .scanning, .connecting, .connected, .reconnecting, .active:
                    // The stale-data watchdog decides when to fall back; a link that
                    // flaps between these says nothing about whether data is arriving.
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

    /// - Parameter isTerminal: the sensor is gone, not flapping, so the rider is told even
    ///   inside `fallbackBannerCooldown`; flaps arrive as `.reconnecting`, never here.
    private func fallBackToGPS(_ state: inout State, isTerminal: Bool = false) -> Effect<Action> {
        state.activeSpeedSource = state.latestGPSSpeedMPS != nil ? .gps : .none
        state.speedMPS = state.latestGPSSpeedMPS
        let shownAt = now
        if !isTerminal, let last = state.lastFallbackBannerAt,
           shownAt.timeIntervalSince(last) < Self.fallbackBannerCooldown {
            return .none
        }
        state.lastFallbackBannerAt = shownAt
        state.sourceSwitchBanner = Self.gpsFallbackBannerText(
            sensorName: state.pairedSensorName, isTerminal: isTerminal
        )
        return .run { send in
            try await clock.sleep(for: Self.bannerDismissDelay)
            await send(.bannerDismissed)
        }
        .cancellable(id: CancelID.bannerTimer, cancelInFlight: true)
    }
}
