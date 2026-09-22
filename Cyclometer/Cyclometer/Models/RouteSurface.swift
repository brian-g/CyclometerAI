import Foundation

/// What a route is ridden on, in the four classes a cyclist chooses tyres by (#252).
enum SurfaceClass: String, Codable, Sendable, Equatable, CaseIterable {
    case paved, gravel, unpaved, unknown

    /// Whether a bicycle would be on this way rather than beside it. Sidewalks, footpaths and
    /// steps run metres from the road a route follows, and without this the nearest-way match
    /// hands a paved road the surface of the dirt path next to it. A footway signed for bikes
    /// stays in; so do `path` and `track`, which is where gravel routes go.
    static func isRideable(osmTags tags: [String: String]) -> Bool {
        guard let highway = tags["highway"], !nonRideableHighways.contains(highway) else { return false }
        if highway == "footway" || highway == "pedestrian" {
            return ["yes", "designated", "permissive"].contains(tags["bicycle"] ?? "")
        }
        return tags["bicycle"] != "no"
    }

    private static let nonRideableHighways: Set<String> = [
        "steps", "corridor", "elevator", "platform", "bus_stop", "construction", "proposed",
        "abandoned", "razed", "rest_area", "services", "escape", "raceway"
    ]

    /// OpenStreetMap's `surface=*` first, falling back to `tracktype=*` on a farm or forest track
    /// that states no surface. Nothing else is inferred: a road with no surface tag is
    /// `.unknown`, not assumed paved, because in exactly the rural places a cyclist asks the
    /// question the assumption is least safe.
    init(osmTags tags: [String: String]) {
        if let surface = tags["surface"], let known = Self.surfaces[surface] {
            self = known
        } else if let tracktype = tags["tracktype"], let known = Self.trackTypes[tracktype] {
            self = known
        } else {
            self = .unknown
        }
    }

    private static let surfaces: [String: SurfaceClass] = [
        "asphalt": .paved, "paved": .paved, "concrete": .paved, "concrete:plates": .paved,
        "concrete:lanes": .paved, "paving_stones": .paved, "sett": .paved, "cobblestone": .paved,
        "metal": .paved, "wood": .paved, "chipseal": .paved,
        "gravel": .gravel, "fine_gravel": .gravel, "compacted": .gravel, "pebblestone": .gravel,
        "unpaved": .unpaved, "dirt": .unpaved, "earth": .unpaved, "ground": .unpaved,
        "grass": .unpaved, "sand": .unpaved, "mud": .unpaved, "rock": .unpaved,
        "woodchips": .unpaved, "unhewn_cobblestone": .unpaved
    ]

    private static let trackTypes: [String: SurfaceClass] = [
        "grade1": .paved, "grade2": .gravel, "grade3": .unpaved, "grade4": .unpaved, "grade5": .unpaved
    ]
}

/// How much of a route falls in each `SurfaceClass`, in metres. Stored on `Route` once the
/// Overpass lookup comes back; nil there means "not looked up yet", while an all-`unknown`
/// breakdown means "looked up, and OpenStreetMap had nothing to say".
struct RouteSurfaceBreakdown: Codable, Sendable, Equatable {
    var pavedMeters = 0.0
    var gravelMeters = 0.0
    var unpavedMeters = 0.0
    var unknownMeters = 0.0

    subscript(surface: SurfaceClass) -> Double {
        get {
            switch surface {
            case .paved: pavedMeters
            case .gravel: gravelMeters
            case .unpaved: unpavedMeters
            case .unknown: unknownMeters
            }
        }
        set {
            switch surface {
            case .paved: pavedMeters = newValue
            case .gravel: gravelMeters = newValue
            case .unpaved: unpavedMeters = newValue
            case .unknown: unknownMeters = newValue
            }
        }
    }

    var totalMeters: Double { SurfaceClass.allCases.reduce(0) { $0 + self[$1] } }
    var knownMeters: Double { totalMeters - unknownMeters }

    /// Share of the whole route, 0...1.
    func fraction(_ surface: SurfaceClass) -> Double {
        totalMeters > 0 ? self[surface] / totalMeters : 0
    }

    /// Below this share of the route with a known surface, any summary would be a guess.
    static let minimumKnownFraction = 0.5
    /// A class must cover this much of the known distance to describe the route by itself.
    static let dominantFraction = 0.6

    /// One word for the route's surface: its dominant class, `.unknown` for "mixed", or nil when
    /// too little of the route is tagged to say anything.
    var dominant: SurfaceClass? {
        guard totalMeters > 0, knownMeters / totalMeters >= Self.minimumKnownFraction else { return nil }
        let known: [SurfaceClass] = [.paved, .gravel, .unpaved]
        guard let top = known.max(by: { self[$0] < self[$1] }) else { return nil }
        return self[top] / knownMeters >= Self.dominantFraction ? top : .unknown
    }
}

/// A way returned by Overpass: its tags and the points it runs through.
struct OSMWay: Equatable, Sendable {
    var id: Int
    var tags: [String: String]
    var geometry: [RouteCoordinate]
}

/// Matches a route to the OpenStreetMap ways along it. Pure, so it is tested against a fixture
/// rather than the network.
enum RouteSurface {

    /// The route is judged every this many metres.
    static let sampleSpacingMeters = 50.0

    /// A sample further than this from every way is on something OpenStreetMap does not map, or
    /// the file's line has drifted off the road; either way, `.unknown`. Also the `around` radius
    /// the Overpass query uses, so nothing fetched is out of reach and nothing in reach is missed.
    static let matchRadiusMeters = 20.0

    /// Grid cell for the segment index, in degrees. At 70° latitude a cell is still wider than
    /// `matchRadiusMeters` east to west, so the 3×3 neighbourhood covers every candidate.
    private static let cellDegrees = 0.001

    static func breakdown(route coordinates: [RouteCoordinate], ways: [OSMWay]) -> RouteSurfaceBreakdown {
        let samples = RouteGeometry.resampled(coordinates, everyMeters: sampleSpacingMeters)
        var breakdown = RouteSurfaceBreakdown()
        guard !samples.isEmpty else { return breakdown }
        let weight = RouteGeometry.distanceMeters(coordinates) / Double(samples.count)

        let index = SegmentIndex(ways: ways, cellDegrees: cellDegrees)
        for sample in samples {
            breakdown[index.nearestSurface(to: sample.coordinate, within: matchRadiusMeters)] += weight
        }
        return breakdown
    }

    /// Way segments bucketed by grid cell. Without it the match is every sample against every
    /// segment — millions of distance calculations for a long route.
    private struct SegmentIndex {
        struct Segment {
            var start: RouteCoordinate
            var end: RouteCoordinate
            var surface: SurfaceClass
        }
        struct Cell: Hashable {
            var latitude: Int
            var longitude: Int
        }

        let cellDegrees: Double
        var cells: [Cell: [Segment]] = [:]

        init(ways: [OSMWay], cellDegrees: Double) {
            self.cellDegrees = cellDegrees
            for way in ways where SurfaceClass.isRideable(osmTags: way.tags) {
                let surface = SurfaceClass(osmTags: way.tags)
                for (start, end) in zip(way.geometry, way.geometry.dropFirst()) {
                    let segment = Segment(start: start, end: end, surface: surface)
                    let low = cell(RouteCoordinate(latitude: min(start.latitude, end.latitude),
                                                   longitude: min(start.longitude, end.longitude)))
                    let high = cell(RouteCoordinate(latitude: max(start.latitude, end.latitude),
                                                    longitude: max(start.longitude, end.longitude)))
                    for latitude in low.latitude...high.latitude {
                        for longitude in low.longitude...high.longitude {
                            cells[Cell(latitude: latitude, longitude: longitude), default: []].append(segment)
                        }
                    }
                }
            }
        }

        func cell(_ coordinate: RouteCoordinate) -> Cell {
            Cell(latitude: Int((coordinate.latitude / cellDegrees).rounded(.down)),
                 longitude: Int((coordinate.longitude / cellDegrees).rounded(.down)))
        }

        /// The surface of the nearest segment within `radius`, or `.unknown`.
        func nearestSurface(to point: RouteCoordinate, within radius: Double) -> SurfaceClass {
            let center = cell(point)
            var best: (distance: Double, surface: SurfaceClass)?
            for latitude in (center.latitude - 1)...(center.latitude + 1) {
                for longitude in (center.longitude - 1)...(center.longitude + 1) {
                    for segment in cells[Cell(latitude: latitude, longitude: longitude)] ?? [] {
                        let distance = RouteSurface.distance(from: point, toSegment: segment.start, segment.end)
                        if distance <= radius, distance < best?.distance ?? .infinity {
                            best = (distance, segment.surface)
                        }
                    }
                }
            }
            return best?.surface ?? .unknown
        }
    }

    /// Metres from a point to a segment: `RouteGeometry`'s own projection, so the surface match
    /// and #197's route tracking flatten the ellipsoid the same way.
    static func distance(from point: RouteCoordinate, toSegment start: RouteCoordinate, _ end: RouteCoordinate) -> Double {
        // Only the offset is read, so the along-route distances can be anything of the right count.
        RouteGeometry.projection(of: point, onto: [start, end], cumulative: [0, 0])?.offsetMeters ?? .infinity
    }
}
