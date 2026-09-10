import Foundation

/// S19's sheet filters as a value, so the whole rule is testable without a `TestStore` and
/// without MapKit — the shape `RoutesMapCamera` and `TurnDerivation` already take.
///
/// The map narrowing is deliberately *not* in here. It needs each route's polyline and costs a
/// walk of every coordinate, so `RoutesFeature` evaluates it once per capture and keeps the
/// surviving ids; these two are scalar comparisons cheap enough to run on every read.
struct RouteFilter: Equatable, Sendable {
    /// Nil means unset. A range covering the whole domain is normalised to nil rather than
    /// stored, so "no constraint" and "a constraint that happens to admit everything" cannot
    /// render as the same badge count.
    var distanceMeters: ClosedRange<Double>?
    var maxElevationGainMeters: Double?

    /// What the toolbar badge shows. The map filter is excluded by design — it has its own
    /// chip, because a count in the toolbar cannot explain a narrowing the rider performed
    /// by panning a map.
    var activeCount: Int {
        (distanceMeters == nil ? 0 : 1) + (maxElevationGainMeters == nil ? 0 : 1)
    }

    var isEmpty: Bool { activeCount == 0 }

    func matches(_ summary: RouteSummary) -> Bool {
        // `ClosedRange.contains` is inclusive at both ends, which is what "filter correctly at
        // both edges" asks for: a route exactly as long as the minimum is not excluded by it.
        if let distanceMeters, !distanceMeters.contains(summary.distanceMeters) { return false }

        if let maxElevationGainMeters {
            // A GPX with no `<ele>` yields nil gain, which means *unknown*, not zero. Dropping
            // those would hide every no-elevation route behind any gain filter — the same
            // confident-zero conflation `RouteGeometry.elevationGainLoss` goes out of its way
            // to refuse (`RouteGeometry.swift:196-212`).
            if let gain = summary.elevationGainMeters, gain > maxElevationGainMeters {
                return false
            }
        }
        return true
    }
}

/// The travel of S19's two sliders, derived from the routes the rider actually has.
///
/// A fixed 0–200 km domain would leave a typical library crammed into the first tenth of the
/// track. Deriving it means the domain moves when routes are imported or deleted, which is what
/// `normalizing(_:)` exists to absorb.
///
/// **Metres only, and a function of the routes alone — never of `UnitSystem`.** Choosing
/// endpoints that are round numbers of miles would be a metres → display → metres round trip,
/// and `preferences` is `@Shared` (`RoutesFeature.swift:19`), so a units change in S12 lands
/// here live: the domain would shift under a filter the rider had already set, and under the
/// full-width-means-unset rule the badge would flip 0 → 1 with no rider action at all. The
/// sheet formats its labels to one decimal place in the rider's unit instead, so the thumbs
/// simply do not sit on round mile values.
struct RouteFilterDomain: Equatable, Sendable {
    var distance: ClosedRange<Double>
    var distanceStep: Double
    /// Nil when no saved route carries an elevation gain — an entirely ordinary library of GPX
    /// files exported without `<ele>`. The sheet hides the row rather than drawing a slider
    /// with nothing behind it.
    var elevationGain: ClosedRange<Double>?
    var elevationGainStep: Double?
}

extension RouteFilterDomain {

    /// Nil for an empty library: there is nothing to derive a domain from, and S19 hides the
    /// filter button entirely rather than opening a sheet of dead sliders.
    static func from(_ routes: [RouteSummary]) -> RouteFilterDomain? {
        let distances = routes.map(\.distanceMeters).filter(\.isFinite)
        guard let minimum = distances.min(), let maximum = distances.max() else { return nil }
        let (distanceRange, distanceStep) = bracket(minimum: minimum, maximum: maximum)

        let gains = routes.compactMap(\.elevationGainMeters).filter(\.isFinite)
        var gainRange: ClosedRange<Double>?
        var gainStep: Double?
        if let gainMinimum = gains.min(), let gainMaximum = gains.max() {
            let bracketed = bracket(minimum: gainMinimum, maximum: gainMaximum)
            gainRange = bracketed.range
            gainStep = bracketed.step
        }

        return RouteFilterDomain(
            distance: distanceRange,
            distanceStep: distanceStep,
            elevationGain: gainRange,
            elevationGainStep: gainStep
        )
    }

    /// The observed extent widened out to whole steps.
    ///
    /// The `upper >= lower + step` floor is not cosmetic. One saved route — or several that
    /// happen to be the same length — gives `minimum == maximum`, and a zero-width domain makes
    /// `RangeSlider`'s `(value - lower) / (upper - lower)` divide by zero: the thumb offsets by
    /// NaN, which trips a CoreGraphics invalid-value assertion and leaves it invisible and
    /// unmovable.
    private static func bracket(
        minimum: Double,
        maximum: Double
    ) -> (range: ClosedRange<Double>, step: Double) {
        let step = niceStep(for: maximum - minimum)
        let lower = (minimum / step).rounded(.down) * step
        let upper = max((maximum / step).rounded(.up) * step, lower + step)
        return (lower...upper, step)
    }

    /// A 1, 2 or 5 × 10ᵏ metre step near a tenth of the span, so the thumb moves in figures a
    /// rider reads as deliberate rather than in an arbitrary fraction of whatever they own.
    private static func niceStep(for span: Double) -> Double {
        // Every route the same length. Any positive step will do; 1 km keeps the derived
        // domain a round kilometre either side of the value.
        guard span > 0, span.isFinite else { return 1_000 }
        let target = span / 10
        let magnitude = pow(10, log10(target).rounded(.down))
        switch target / magnitude {
        case ..<1.5:  return magnitude
        case ..<3.5:  return 2 * magnitude
        case ..<7.5:  return 5 * magnitude
        default:      return 10 * magnitude
        }
    }

    /// `filter` brought back into this domain: values outside it clamped, values covering the
    /// whole of it dropped to nil.
    ///
    /// Run on every change to the route set, not only when a thumb moves. Import a 200 km route
    /// while the upper thumb sits at what *was* the maximum — which the rider read as "no upper
    /// limit" — and without this the new route is filtered out the moment it arrives, with the
    /// badge reading 1 and nothing on screen to say why. Delete the longest route and the stored
    /// bound is left outside the domain, drawing the thumb off the end of its own track.
    func normalizing(_ filter: RouteFilter) -> RouteFilter {
        var result = filter

        if let range = filter.distanceMeters {
            let lower = max(range.lowerBound, distance.lowerBound)
            let upper = min(range.upperBound, distance.upperBound)
            if lower <= distance.lowerBound && upper >= distance.upperBound {
                result.distanceMeters = nil
            } else {
                // `lower...upper` traps when inverted, which a clamp against a domain that has
                // moved past the stored range can produce.
                result.distanceMeters = lower <= upper ? lower...upper : nil
            }
        }

        if let maximum = filter.maxElevationGainMeters {
            if let gainDomain = elevationGain {
                let clamped = min(max(maximum, gainDomain.lowerBound), gainDomain.upperBound)
                result.maxElevationGainMeters = clamped >= gainDomain.upperBound ? nil : clamped
            } else {
                // Every route carrying a gain has been deleted. Leaving the filter set would
                // hide routes with no slider left in the sheet to undo it.
                result.maxElevationGainMeters = nil
            }
        }

        return result
    }
}
