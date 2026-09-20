import Foundation

/// Where the direction-of-travel chevrons go on a route, and which way each one points.
///
/// Pure arithmetic over values, deliberately: a live `Map` cannot be pixel-snapshot-tested
/// reliably (tiles render asynchronously — `RoutesMapCamera.swift:6-9`), so the part of the
/// direction indicator that can be wrong is kept where ordinary tests can reach it and the
/// `MapContent` wrapper is left with nothing to decide.
///
/// UX.md §S20 asks for direction of travel on the route detail map; #194 puts the same
/// treatment on S19's map, which is why this is shared rather than living in either screen.
enum RouteDirectionMarkers {

    struct Placement: Equatable, Sendable {
        var coordinate: RouteCoordinate
        /// Degrees clockwise from true north, matching `RouteGeometry.bearingDegrees`.
        var bearingDegrees: Double
    }

    /// Chevrons no closer together than this on the ground, however far the rider zooms in.
    /// Without a floor, a viewport a few hundred metres wide would ask for a chevron every
    /// couple of metres and bury the line it is annotating. Raised from 150 m after review:
    /// at tight zooms the floor is what sets the density, and 150 m was still crowding.
    static let minimumSpacingMeters = 300.0

    /// Roughly this many chevrons across the viewport, whatever it is showing. This is what
    /// makes the spacing zoom-adaptive: it is a fraction of what is on screen, not of the
    /// route, so a 5 km route and a 100 km route read the same at the zoom you view them at.
    ///
    /// Halved from 8 after review: the chevrons annotate a line the rider can already see, and
    /// at that density they were reading as the line rather than as its direction.
    static let chevronsAcrossViewport = 4.0

    /// Ground distance between chevrons for a given viewport.
    static func spacingMeters(for visibleBounds: RouteBounds) -> Double {
        // The viewport's east-west extent, measured on the tangent plane at its own middle
        // latitude — the same primitive every other distance in this app is built on, so the
        // spacing cannot disagree with the route lengths it is drawn against.
        let centerLatitude = visibleBounds.center.latitude
        let width = RouteGeometry.tangentPlaneOffset(
            from: RouteCoordinate(latitude: centerLatitude,
                                  longitude: visibleBounds.minLongitude,
                                  elevationMeters: nil),
            to: RouteCoordinate(latitude: centerLatitude,
                                longitude: visibleBounds.maxLongitude,
                                elevationMeters: nil)
        ).east
        guard width.isFinite else { return minimumSpacingMeters }
        return max(abs(width) / chevronsAcrossViewport, minimumSpacingMeters)
    }

    /// Ground distance between chevrons on a map that reports a camera rather than a region
    /// (#258, the live ride map). That map is pitched, and a pitched camera's region is the box
    /// around the whole frustum — it runs to the horizon, so it says nothing about how wide the
    /// road on screen reads. `MapCamera.distance` does, and it is immune to the tilt.
    ///
    /// Same constants as `spacingMeters(for:)`, so the same route reads at the same density
    /// whether the rider is browsing it on S19 or riding it.
    static func spacingMeters(forCameraDistanceMeters distance: Double) -> Double {
        guard distance.isFinite, distance > 0 else { return minimumSpacingMeters }
        return max(distance / chevronsAcrossViewport, minimumSpacingMeters)
    }

    /// The on-screen angle a chevron must be drawn at to point along `bearingDegrees`, on a map
    /// turned to `headingDegrees` and tilted to `pitchDegrees` (#258).
    ///
    /// `Annotation` content is screen-space: MapKit neither turns it with the map nor lays it in
    /// the map plane. S19 and S20 dodge this by refusing rotation and pitch (`RoutesView`), but
    /// the live map is heading-up and tilted by design, so the angle is computed instead.
    ///
    /// Two corrections, in order: the map's heading turns the world under the glyph, and the tilt
    /// foreshortens the screen's vertical axis by `cos(pitch)` while leaving the horizontal one
    /// alone. A due-north bearing on a heading-up map pointing north is screen-up either way; a
    /// bearing at 45° to the camera is drawn nearer the horizontal the more the map is tilted.
    static func screenAngleDegrees(
        bearingDegrees: Double,
        headingDegrees: Double,
        pitchDegrees: Double
    ) -> Double {
        guard bearingDegrees.isFinite, headingDegrees.isFinite else { return 0 }
        let relative = (bearingDegrees - headingDegrees) * .pi / 180
        // A pitch MapKit has not reported yet, or one outside the range it can draw, is treated
        // as flat rather than allowed to flip or collapse the glyph.
        let pitch = pitchDegrees.isFinite ? min(max(pitchDegrees, 0), 89) * .pi / 180 : 0
        let angle = atan2(sin(relative), cos(relative) * cos(pitch)) * 180 / .pi
        return angle < 0 ? angle + 360 : angle
    }

    /// Chevron placements along `coordinates`, spaced for `visibleBounds` and culled to it.
    ///
    /// Nil bounds means no chevrons: the caller has no camera yet, and guessing a spacing from
    /// the route's own length would make the same route read differently on two screens.
    static func placements(
        coordinates: [RouteCoordinate],
        visibleBounds: RouteBounds?,
        limit: Int = 12
    ) -> [Placement] {
        guard let visibleBounds else { return [] }
        return placements(
            coordinates: coordinates,
            spacingMeters: spacingMeters(for: visibleBounds),
            visibleBounds: visibleBounds,
            limit: limit
        )
    }

    /// The same, for a caller that derives its spacing some other way — the live map, from its
    /// camera distance rather than from a region it cannot trust (see
    /// `spacingMeters(forCameraDistanceMeters:)`). `visibleBounds` still culls: off-screen
    /// chevrons cost annotations for nothing.
    ///
    /// Placement rides on `RouteGeometry.resampled(_:everyMeters:)` (#192) so the result does
    /// not depend on how the source GPX happened to be sampled — a file with a point every
    /// 200 m and one with a point every metre describe the same road and get the same chevrons.
    static func placements(
        coordinates: [RouteCoordinate],
        spacingMeters spacing: Double,
        visibleBounds: RouteBounds,
        limit: Int = 12
    ) -> [Placement] {
        guard coordinates.count > 1, limit > 0, spacing.isFinite, spacing > 0 else { return [] }

        let samples = RouteGeometry.resampled(coordinates, everyMeters: spacing).map(\.coordinate)

        if samples.count < 2 {
            // The whole route is shorter than one chevron spacing. It still has a direction,
            // and exactly one chevron at its midpoint is what says so — resampling at half the
            // length yields start, midpoint, end, and only the middle one is wanted. Falling
            // through to the loop below would also place one on the final point, directly
            // under the finish flag.
            let total = RouteGeometry.distanceMeters(coordinates)
            guard total > 0 else { return [] }
            let thirds = RouteGeometry.resampled(coordinates, everyMeters: total / 2).map(\.coordinate)
            guard thirds.count >= 2 else { return [] }
            let midpoint = thirds[1]
            guard visibleBounds.contains(latitude: midpoint.latitude,
                                         longitude: midpoint.longitude),
                  let bearing = RouteGeometry.bearingDegrees(from: thirds[0], to: midpoint)
            else { return [] }
            return [Placement(coordinate: midpoint, bearingDegrees: bearing)]
        }

        var placements: [Placement] = []
        // Anchored on the *later* sample of each pair, so no chevron lands on the route's first
        // point where it would sit under the start flag.
        for (start, end) in zip(samples, samples.dropFirst()) {
            guard visibleBounds.contains(latitude: end.latitude, longitude: end.longitude) else {
                continue
            }
            guard let bearing = RouteGeometry.bearingDegrees(from: start, to: end) else { continue }
            placements.append(Placement(coordinate: end, bearingDegrees: bearing))
        }
        return thinned(placements, to: limit)
    }

    /// At most `limit` placements, spread across the whole line rather than taken from its
    /// start.
    ///
    /// Spacing is measured *along the route*, not across the screen, so a switchback climb or a
    /// criterium loop that doubles back inside one viewport produces far more in-view samples
    /// than the cap allows. Truncating would leave the back half of a visible line with no
    /// chevrons at all, which reads as "this part has no direction" rather than as a cap.
    private static func thinned(_ placements: [Placement], to limit: Int) -> [Placement] {
        guard placements.count > limit else { return placements }
        // `limit - 1` is the denominator below, so one chevron is its own case — the middle of
        // the line, not the start of it.
        guard limit > 1 else { return [placements[placements.count / 2]] }
        // Evenly spaced indices across the whole array, endpoints included.
        return (0..<limit).map { step in
            placements[Int((Double(step) * Double(placements.count - 1) / Double(limit - 1)).rounded())]
        }
    }
}
