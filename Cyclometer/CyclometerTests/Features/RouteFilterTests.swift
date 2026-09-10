import Foundation
import Testing
@testable import Cyclometer

/// #194 — S19's sheet filters and the travel of the sliders behind them.
@Suite("RouteFilter")
struct RouteFilterTests {

    private static func summary(
        name: String = "Route",
        distanceMeters: Double,
        elevationGainMeters: Double? = nil
    ) -> RouteSummary {
        var summary = RouteSummary.empty
        summary.id = UUID()
        summary.name = name
        summary.distanceMeters = distanceMeters
        summary.elevationGainMeters = elevationGainMeters
        return summary
    }

    // MARK: - Distance

    @Test("distance bounds are inclusive at both edges")
    func distanceEdgesAreInclusive() {
        let filter = RouteFilter(distanceMeters: 20_000...40_000, maxElevationGainMeters: nil)
        #expect(filter.matches(Self.summary(distanceMeters: 20_000)))
        #expect(filter.matches(Self.summary(distanceMeters: 40_000)))
        #expect(!filter.matches(Self.summary(distanceMeters: 19_999)))
        #expect(!filter.matches(Self.summary(distanceMeters: 40_001)))
    }

    // MARK: - Elevation gain

    @Test("the gain maximum is inclusive")
    func gainMaximumIsInclusive() {
        let filter = RouteFilter(distanceMeters: nil, maxElevationGainMeters: 500)
        #expect(filter.matches(Self.summary(distanceMeters: 10_000, elevationGainMeters: 500)))
        #expect(!filter.matches(Self.summary(distanceMeters: 10_000, elevationGainMeters: 501)))
    }

    @Test("a route with no elevation data is never dropped by the gain filter")
    func nilGainSurvives() {
        // A GPX with no `<ele>` gives nil, which means *unknown*, not zero. Dropping those
        // would hide every no-elevation route behind any gain filter — the same confident-zero
        // conflation `RouteGeometry.elevationGainLoss` refuses to make.
        let filter = RouteFilter(distanceMeters: nil, maxElevationGainMeters: 100)
        #expect(filter.matches(Self.summary(distanceMeters: 10_000, elevationGainMeters: nil)))
        // Even at the strictest setting the slider can reach.
        let strictest = RouteFilter(distanceMeters: nil, maxElevationGainMeters: 0)
        #expect(strictest.matches(Self.summary(distanceMeters: 10_000, elevationGainMeters: nil)))
    }

    // MARK: - Composition and counting

    @Test("distance and gain compose rather than overriding one another")
    func filtersCompose() {
        let filter = RouteFilter(distanceMeters: 20_000...40_000, maxElevationGainMeters: 300)
        #expect(filter.matches(Self.summary(distanceMeters: 30_000, elevationGainMeters: 250)))
        // Right length, too much climbing.
        #expect(!filter.matches(Self.summary(distanceMeters: 30_000, elevationGainMeters: 900)))
        // Little climbing, wrong length.
        #expect(!filter.matches(Self.summary(distanceMeters: 60_000, elevationGainMeters: 10)))
    }

    @Test("the badge counts only the filters that are set")
    func activeCount() {
        #expect(RouteFilter().activeCount == 0)
        #expect(RouteFilter().isEmpty)
        #expect(RouteFilter(distanceMeters: 1...2, maxElevationGainMeters: nil).activeCount == 1)
        #expect(RouteFilter(distanceMeters: 1...2, maxElevationGainMeters: 3).activeCount == 2)
    }

    @Test("filtering does not disturb the routes it was given")
    func filteringLeavesTheInputAlone() {
        let routes = [
            Self.summary(name: "Short", distanceMeters: 10_000),
            Self.summary(name: "Long", distanceMeters: 90_000)
        ]
        let filter = RouteFilter(distanceMeters: 0...20_000, maxElevationGainMeters: nil)
        let kept = routes.filter(filter.matches)
        #expect(kept.map(\.name) == ["Short"])
        #expect(routes.map(\.name) == ["Short", "Long"])
    }

    // MARK: - Domain

    @Test("an empty library has no domain")
    func emptyLibraryHasNoDomain() {
        #expect(RouteFilterDomain.from([]) == nil)
    }

    @Test("the domain brackets the routes rather than starting at zero")
    func domainBracketsTheRoutes() {
        let domain = RouteFilterDomain.from([
            Self.summary(distanceMeters: 18_000),
            Self.summary(distanceMeters: 62_000)
        ])
        let distance = try! #require(domain?.distance)
        // Widened outward to whole steps, so the whole travel of the slider is useful for the
        // library the rider actually has.
        #expect(distance.lowerBound <= 18_000)
        #expect(distance.upperBound >= 62_000)
        #expect(distance.lowerBound > 0, "a fixed 0-based domain would waste most of the track")
    }

    @Test("a library whose routes are all the same length still gets a usable domain")
    func degenerateDomainIsWidened() {
        // min == max. A zero-width domain makes the slider's (value - lower)/(upper - lower)
        // divide by zero: the thumb offsets by NaN, trips a CoreGraphics assertion, and is
        // both invisible and unmovable.
        let domain = try! #require(RouteFilterDomain.from([
            Self.summary(distanceMeters: 36_050),
            Self.summary(distanceMeters: 36_050)
        ]))
        #expect(domain.distanceStep > 0)
        #expect(domain.distance.upperBound - domain.distance.lowerBound >= domain.distanceStep)
        #expect(domain.distance.contains(36_050))
    }

    @Test("one route is enough for a domain")
    func singleRouteDomain() {
        let domain = try! #require(RouteFilterDomain.from([Self.summary(distanceMeters: 20_000)]))
        #expect(domain.distance.contains(20_000))
        #expect(domain.distance.upperBound > domain.distance.lowerBound)
    }

    @Test("a library with no elevation anywhere has no gain slider to draw")
    func noGainAnywhereMeansNoGainDomain() {
        let domain = try! #require(RouteFilterDomain.from([
            Self.summary(distanceMeters: 20_000, elevationGainMeters: nil),
            Self.summary(distanceMeters: 40_000, elevationGainMeters: nil)
        ]))
        #expect(domain.elevationGain == nil)
        #expect(domain.elevationGainStep == nil)
    }

    @Test("routes without elevation do not drag the gain domain down")
    func nilGainDoesNotContributeToTheDomain() {
        let domain = try! #require(RouteFilterDomain.from([
            Self.summary(distanceMeters: 20_000, elevationGainMeters: 700),
            Self.summary(distanceMeters: 40_000, elevationGainMeters: 800),
            Self.summary(distanceMeters: 30_000, elevationGainMeters: nil)
        ]))
        let gain = try! #require(domain.elevationGain)
        #expect(gain.lowerBound > 0, "the nil route must not pull the floor to zero")
        #expect(gain.contains(700))
        #expect(gain.contains(800))
    }

    @Test("the domain does not depend on the rider's units")
    func domainIsUnitIndependent() {
        // Deriving round *mile* endpoints would make the domain a function of `preferences`,
        // which is `@Shared` — an S12 units change would then move the endpoints under a filter
        // the rider had already set and flip the badge with no action of theirs.
        let routes = [Self.summary(distanceMeters: 18_000), Self.summary(distanceMeters: 62_000)]
        #expect(RouteFilterDomain.from(routes) == RouteFilterDomain.from(routes))
    }

    // MARK: - Normalisation

    @Test("a range covering the whole domain is unset, not stored")
    func fullWidthNormalizesToNil() {
        let domain = try! #require(RouteFilterDomain.from([
            Self.summary(distanceMeters: 18_000),
            Self.summary(distanceMeters: 62_000)
        ]))
        let atFullWidth = RouteFilter(distanceMeters: domain.distance, maxElevationGainMeters: nil)
        #expect(domain.normalizing(atFullWidth).distanceMeters == nil)
        #expect(domain.normalizing(atFullWidth).activeCount == 0)
    }

    @Test("a filter set before the library grew is clamped, not widened")
    func normalizingClampsIntoTheDomain() {
        // The rider capped distance at 40 km. Then a 200 km route arrives and the domain grows.
        let filter = RouteFilter(distanceMeters: 18_000...40_000, maxElevationGainMeters: nil)
        let grown = try! #require(RouteFilterDomain.from([
            Self.summary(distanceMeters: 18_000),
            Self.summary(distanceMeters: 200_000)
        ]))
        let normalized = grown.normalizing(filter)
        let range = try! #require(normalized.distanceMeters)
        #expect(range.upperBound == 40_000, "the cap the rider set must survive the import")
        #expect(normalized.activeCount == 1)
    }

    @Test("a bound left outside a shrunken domain is pulled back inside it")
    func normalizingHandlesAShrinkingDomain() {
        // The longest route was deleted; the stored upper bound is now past the end of the
        // slider's own track.
        let filter = RouteFilter(distanceMeters: 18_000...150_000, maxElevationGainMeters: nil)
        let shrunk = try! #require(RouteFilterDomain.from([
            Self.summary(distanceMeters: 18_000),
            Self.summary(distanceMeters: 40_000)
        ]))
        let normalized = shrunk.normalizing(filter)
        // It now covers everything left, so it is no longer a filter at all.
        #expect(normalized.distanceMeters == nil)
    }

    @Test("a gain filter is dropped when nothing left carries an elevation")
    func gainFilterDroppedWithNoGainDomain() {
        // Otherwise it keeps hiding routes with no slider left in the sheet to undo it.
        let filter = RouteFilter(distanceMeters: nil, maxElevationGainMeters: 300)
        let domain = try! #require(RouteFilterDomain.from([
            Self.summary(distanceMeters: 20_000, elevationGainMeters: nil)
        ]))
        #expect(domain.normalizing(filter).maxElevationGainMeters == nil)
    }

    @Test("a gain maximum at the top of its domain is unset")
    func gainAtFullWidthNormalizesToNil() {
        let domain = try! #require(RouteFilterDomain.from([
            Self.summary(distanceMeters: 20_000, elevationGainMeters: 100),
            Self.summary(distanceMeters: 40_000, elevationGainMeters: 800)
        ]))
        let gain = try! #require(domain.elevationGain)
        let filter = RouteFilter(distanceMeters: nil, maxElevationGainMeters: gain.upperBound)
        #expect(domain.normalizing(filter).maxElevationGainMeters == nil)
    }
}

/// #194 review follow-ups — rules that were reachable in production but pinned by nothing.
@Suite("RangeSlider — thumb selection")
struct RangeSliderThumbTests {

    @Test("the nearer thumb wins")
    func nearestThumbWins() {
        #expect(RangeSlider.thumbForDrag(target: 12, lowerValue: 10, upperValue: 90,
                                         translation: 0, isRightToLeft: false,
                                         hasLowerThumb: true) == .lower)
        #expect(RangeSlider.thumbForDrag(target: 88, lowerValue: 10, upperValue: 90,
                                         translation: 0, isRightToLeft: false,
                                         hasLowerThumb: true) == .upper)
    }

    @Test("with the thumbs stacked, a zero translation picks neither")
    func coincidentThumbsWaitForADirection() {
        // A `DragGesture(minimumDistance: 0)` delivers its first `onChanged` with no
        // translation. Latching on it would always pick `.lower`, and since the caller pins the
        // choice for the rest of the drag, a fully closed range could only ever be dragged
        // further closed — never reopened.
        #expect(RangeSlider.thumbForDrag(target: 50, lowerValue: 50, upperValue: 50,
                                         translation: 0, isRightToLeft: false,
                                         hasLowerThumb: true) == nil)
    }

    @Test("with the thumbs stacked, the drag direction decides")
    func coincidentThumbsBreakTheTieByDirection() {
        #expect(RangeSlider.thumbForDrag(target: 50, lowerValue: 50, upperValue: 50,
                                         translation: 12, isRightToLeft: false,
                                         hasLowerThumb: true) == .upper)
        #expect(RangeSlider.thumbForDrag(target: 50, lowerValue: 50, upperValue: 50,
                                         translation: -12, isRightToLeft: false,
                                         hasLowerThumb: true) == .lower)
    }

    @Test("right-to-left reverses which direction opens the range")
    func directionIsMirroredForRightToLeft() {
        #expect(RangeSlider.thumbForDrag(target: 50, lowerValue: 50, upperValue: 50,
                                         translation: 12, isRightToLeft: true,
                                         hasLowerThumb: true) == .lower)
        #expect(RangeSlider.thumbForDrag(target: 50, lowerValue: 50, upperValue: 50,
                                         translation: -12, isRightToLeft: true,
                                         hasLowerThumb: true) == .upper)
    }

    @Test("a one-thumb slider always moves its upper bound")
    func singleThumbAlwaysWins() {
        #expect(RangeSlider.thumbForDrag(target: 0, lowerValue: 0, upperValue: 90,
                                         translation: 0, isRightToLeft: false,
                                         hasLowerThumb: false) == .upper)
    }
}
