import Foundation

enum UnitSystem: String, Equatable, Sendable, Codable {
    case metric, imperial

    var speedLabel: String { self == .metric ? "km/h" : "mph" }
    var distanceLabel: String { self == .metric ? "km" : "mi" }

    func speed(fromMPS mps: Double) -> Double {
        mps * (self == .metric ? 3.6 : 2.23694)
    }

    func distance(fromMeters m: Double) -> Double {
        m / (self == .metric ? 1000.0 : 1609.34)
    }
}
