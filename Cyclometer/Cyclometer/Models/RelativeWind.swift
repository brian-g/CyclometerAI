import Foundation

/// The wind as a rider meets it (#150): where it blows relative to the way they are travelling,
/// rather than to north. W10's arrow and its VoiceOver wording both come from here.
enum RelativeWind: Equatable, Sendable {
    case tailwind
    case headwind
    case crosswindFromLeft
    case crosswindFromRight

    /// How far to turn an up-pointing arrow, clockwise, 0..<360, so that up is the rider's direction
    /// of travel and the arrow points the way the wind blows. A wind from the north on a rider
    /// heading south is 0: the arrow points forward, a tailwind.
    ///
    /// - Parameters:
    ///   - windFrom: where the wind blows from, degrees clockwise from true north (meteorological).
    ///   - course: the rider's direction of travel, degrees clockwise from true north.
    static func arrowRotation(windFrom: Double, course: Double) -> Double {
        guard windFrom.isFinite, course.isFinite else { return 0 }
        let turn = (windFrom + downwind - course).truncatingRemainder(dividingBy: fullTurn)
        return turn < 0 ? turn + fullTurn : turn
    }

    /// Which quarter the wind is in. Each owns 45° either side of dead ahead, astern or abeam.
    init(windFrom: Double, course: Double) {
        switch Self.arrowRotation(windFrom: windFrom, course: course) {
        case ..<Self.quarterEdge, (Self.fullTurn - Self.quarterEdge)...: self = .tailwind
        // An arrow pointing right is wind crossing left to right.
        case ..<(Self.downwind - Self.quarterEdge): self = .crosswindFromLeft
        case ..<(Self.downwind + Self.quarterEdge): self = .headwind
        default: self = .crosswindFromRight
        }
    }

    /// For VoiceOver: "headwind", "crosswind from the left".
    var name: String {
        switch self {
        case .tailwind: "tailwind"
        case .headwind: "headwind"
        case .crosswindFromLeft: "crosswind from the left"
        case .crosswindFromRight: "crosswind from the right"
        }
    }

    /// A bearing names where the wind comes from; the arrow shows where it goes.
    private static let downwind = 180.0
    private static let fullTurn = 360.0
    /// Half a quarter: how far either side of dead ahead still counts as ahead.
    private static let quarterEdge = 45.0
}
