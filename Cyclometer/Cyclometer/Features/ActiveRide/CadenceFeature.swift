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
    /// Maximum points plotted in the watermark; raw samples are downsampled to
    /// this many buckets so memory and render stay bounded over a full hour.
    static let watermarkResolution = 60

    @Dependency(\.date.now) var now

    @ObservableState
    struct State: Equatable {
        var cadenceRPM: Int? = nil
        var connectionState: BLECSCClient.ConnectionState = .disconnected
        var pairedPeripheralId: UUID? = nil
        /// Timestamped cadence samples from the last `historyWindow` seconds.
        var cadenceSamples: [CadenceSample] = []
        /// Count of pedalling readings (rpm > 0); coasting is excluded so the
        /// average reflects effort while actually pedalling.
        var pedalingSampleCount: Int = 0
        /// Running sum of pedalling readings, paired with `pedalingSampleCount`.
        var cadenceSum: Double = 0
        var maxCadenceRPM: Int = 0

        /// Average cadence over pedalling time: mean of non-zero rpm readings.
        var averageCadenceRPM: Int {
            pedalingSampleCount > 0
                ? Int((cadenceSum / Double(pedalingSampleCount)).rounded())
                : 0
        }

        /// Watermark series (rpm), downsampled to ≤ `watermarkResolution` points
        /// by averaging contiguous buckets. Identical strategy to `SpeedFeature`.
        var watermarkSamples: [Double] {
            let values = cadenceSamples.map(\.rpm)
            guard values.count > CadenceFeature.watermarkResolution else { return values }
            let bucket = Double(values.count) / Double(CadenceFeature.watermarkResolution)
            return (0..<CadenceFeature.watermarkResolution).map { i in
                let start = Int(Double(i) * bucket)
                let end = max(start + 1, Int(Double(i + 1) * bucket))
                let slice = values[start..<min(end, values.count)]
                return slice.reduce(0, +) / Double(slice.count)
            }
        }
    }

    enum Action: Equatable {
        case startListening
        case cadenceReceived(Double)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startListening:
                guard state.pairedPeripheralId != nil else { return .none }
                return .none

            case .cadenceReceived(let rpm):
                guard rpm >= 0 else {
                    state.cadenceRPM = nil
                    return .none
                }
                state.cadenceRPM = Int(rpm.rounded())
                state.cadenceSamples.append(CadenceSample(time: now, rpm: rpm))
                let cutoff = now.addingTimeInterval(-Self.historyWindow)
                state.cadenceSamples.removeAll { $0.time < cutoff }
                if rpm > 0 {
                    state.pedalingSampleCount += 1
                    state.cadenceSum += rpm
                    state.maxCadenceRPM = max(state.maxCadenceRPM, Int(rpm.rounded()))
                }
                return .none
            }
        }
    }
}
