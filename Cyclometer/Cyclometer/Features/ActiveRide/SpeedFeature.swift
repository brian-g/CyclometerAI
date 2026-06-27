import ComposableArchitecture
import Foundation

enum SensorSource: Equatable, Sendable {
    case none
    case gps
    case bleWheel
}

/// A single timestamped speed reading (m/s) used for the watermark sparkline.
struct SpeedSample: Equatable, Sendable {
    let time: Date
    let mps: Double
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

    @Dependency(\.date.now) var now

    @ObservableState
    struct State: Equatable {
        var speedMPS: Double? = nil
        var activeSpeedSource: SensorSource = .none
        var connectionState: BLECSCClient.ConnectionState = .disconnected
        var pairedPeripheralId: UUID? = nil
        /// Timestamped speed samples from the last `historyWindow` seconds.
        var speedSamples: [SpeedSample] = []

        /// Watermark series (m/s), downsampled to ≤ `watermarkResolution` points
        /// by averaging contiguous buckets.
        var watermarkSamples: [Double] {
            let values = speedSamples.map(\.mps)
            guard values.count > SpeedFeature.watermarkResolution else { return values }
            let bucket = Double(values.count) / Double(SpeedFeature.watermarkResolution)
            return (0..<SpeedFeature.watermarkResolution).map { i in
                let start = Int(Double(i) * bucket)
                let end = max(start + 1, Int(Double(i + 1) * bucket))
                let slice = values[start..<min(end, values.count)]
                return slice.reduce(0, +) / Double(slice.count)
            }
        }
    }

    enum Action: Equatable {
        case startListening
        case gpsSpeedReceived(Double)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startListening:
                guard state.pairedPeripheralId != nil else { return .none }
                return .none

            case .gpsSpeedReceived(let speed):
                guard speed >= 0 else {
                    state.speedMPS = nil
                    state.activeSpeedSource = .none
                    return .none
                }
                state.speedMPS = speed
                state.activeSpeedSource = .gps
                state.speedSamples.append(SpeedSample(time: now, mps: speed))
                let cutoff = now.addingTimeInterval(-Self.historyWindow)
                state.speedSamples.removeAll { $0.time < cutoff }
                return .none
            }
        }
    }
}
