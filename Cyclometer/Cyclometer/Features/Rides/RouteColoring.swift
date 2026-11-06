import SwiftUI

/// What S15's map sheet colors the route by (#537). Each point falls in one of five bands, or none
/// with no reading; neighbouring points in a band draw as one polyline.
enum RouteColoring: String, CaseIterable, Identifiable, Sendable {
    case plain, speed, grade, cadence, heartRate

    var id: Self { self }

    var title: String {
        switch self {
        case .plain: "Plain"
        case .speed: "Speed"
        case .grade: "Grade"
        case .cadence: "Cadence"
        case .heartRate: "Heart Rate"
        }
    }

    /// Below this, a run of one band folds into the run before it, so a reading flickering at a
    /// band edge doesn't break the line into slivers.
    static let minimumRunMeters = 50.0

    /// A band's color. Speed and grade share the map's grade ramp, slow or flat to fast or steep;
    /// heart rate and cadence use the zone colors, as their sheets do. No reading is neutral.
    func color(band: Int?) -> Color {
        guard let band else { return .cyTextTertiary }
        switch self {
        case .plain: return .cyPrimary
        case .speed, .grade: return .mapGrade(band: band)
        case .heartRate, .cadence: return .hrZone(band)
        }
    }
}

extension Color {
    /// The map's grade ramp by band, 1 to 5: `mapGrade(percent:)`'s colors.
    static func mapGrade(band: Int) -> Color {
        switch band {
        case ...1: .cyMapGrade1
        case 2: .cyMapGrade2
        case 3: .cyMapGrade3
        case 4: .cyMapGrade4
        default: .cyMapGrade5
        }
    }
}

/// One polyline of the colored route.
struct ColoredRun: Equatable, Sendable {
    /// Ends on the next run's first point, so the line has no gaps.
    var coordinates: [RouteCoordinate]
    /// 1 to 5, nil with no reading.
    var band: Int?
}

/// What puts each point in its band: the ride's own speeds, the rider's zones.
struct RouteColorScale: Equatable, Sendable {
    var coloring: RouteColoring
    /// The ride's 5th and 95th percentile moving speeds, m/s: the speed bands split the span
    /// between them in five, so one fast descent doesn't squeeze the rest of the ride into a band.
    var speedSpan: ClosedRange<Double>?
    /// S12's heart rate zones, zone 1 first.
    var heartRateZones: [ClosedRange<Int>]
    var cadenceZones: CadenceZoneBoundaries

    init(coloring: RouteColoring, track: RideMapTrack, heartRateZones: [ClosedRange<Int>],
         cadenceZones: CadenceZoneBoundaries) {
        self.coloring = coloring
        self.speedSpan = coloring == .speed ? Self.speedSpan(track) : nil
        self.heartRateZones = heartRateZones
        self.cadenceZones = cadenceZones
    }

    static func speedSpan(_ track: RideMapTrack) -> ClosedRange<Double>? {
        let moving = track.points.compactMap(\.speedMPS)
            .filter { $0 > ActiveRideFeature.stationarySpeedMPS }
            .sorted()
        guard !moving.isEmpty else { return nil }
        func percentile(_ fraction: Double) -> Double {
            moving[Int((Double(moving.count - 1) * fraction).rounded())]
        }
        return percentile(0.05)...percentile(0.95)
    }

    func band(_ point: RideMapTrack.Point) -> Int? {
        switch coloring {
        case .plain:
            return 1
        case .speed:
            guard let mps = point.speedMPS, let speedSpan else { return nil }
            return Self.speedBand(mps, span: speedSpan)
        case .grade:
            return point.gradePercent.map(Self.gradeBand)
        case .heartRate:
            return point.heartRateBPM.map { Self.heartRateBand($0, zones: heartRateZones) }
        case .cadence:
            guard let rpm = point.cadenceRPM, rpm > 0 else { return nil }
            return cadenceZones.zone(forRPM: Double(rpm)).rawValue
        }
    }

    /// Five equal bands across `span`; below it is band 1, above it band 5. A ride ridden at one
    /// speed has no span to split, so all of it is the middle band.
    static func speedBand(_ mps: Double, span: ClosedRange<Double>) -> Int {
        let width = span.upperBound - span.lowerBound
        guard width > 0 else { return 3 }
        let fraction = (mps - span.lowerBound) / width
        return min(5, max(1, Int(fraction * 5) + 1))
    }

    /// The map's grade bands (`Color.mapGrade(percent:)`). A descent is flat: the ramp says how
    /// hard the road was to climb.
    static func gradeBand(_ percent: Double) -> Int {
        switch percent {
        case ..<3: 1
        case ..<6: 2
        case ..<9: 3
        case ..<12: 4
        default: 5
        }
    }

    /// The zone whose range holds `bpm`. Below zone 1 is zone 1 and above zone 5 is zone 5, as
    /// the Heart Rate sheet counts them.
    static func heartRateBand(_ bpm: Int, zones: [ClosedRange<Int>]) -> Int {
        guard !zones.isEmpty else { return 1 }
        return (zones.firstIndex { bpm <= $0.upperBound } ?? zones.count - 1) + 1
    }

    // MARK: Runs

    /// The route as polylines of one band each. A run shorter than `RouteColoring.minimumRunMeters`
    /// takes the band of the run before it (the first, of the run after it). Runs never join across
    /// a pause: each stretch of riding starts its own.
    func runs(_ track: RideMapTrack) -> [ColoredRun] {
        track.segments.flatMap { segment -> [ColoredRun] in
            var groups: [(band: Int?, points: [RouteCoordinate])] = []
            for point in segment {
                let band = band(point)
                if let last = groups.indices.last, groups[last].band == band {
                    groups[last].points.append(point.coordinate)
                } else {
                    groups.append((band, [point.coordinate]))
                }
            }
            // Measured to the next group's first point, where the run's line ends.
            func length(_ index: Int, of groups: [(band: Int?, points: [RouteCoordinate])]) -> Double {
                var coordinates = groups[index].points
                if index + 1 < groups.count, let next = groups[index + 1].points.first { coordinates.append(next) }
                return RouteGeometry.distanceMeters(coordinates)
            }
            var folded: [(band: Int?, points: [RouteCoordinate])] = []
            for index in groups.indices {
                if let last = folded.indices.last,
                   folded[last].band == groups[index].band || length(index, of: groups) < RouteColoring.minimumRunMeters {
                    folded[last].points += groups[index].points
                } else {
                    folded.append(groups[index])
                }
            }
            if folded.count > 1, length(0, of: folded) < RouteColoring.minimumRunMeters {
                folded[1].points = folded[0].points + folded[1].points
                folded.removeFirst()
            }
            return folded.indices.map { index in
                var coordinates = folded[index].points
                if index + 1 < folded.count, let next = folded[index + 1].points.first { coordinates.append(next) }
                return ColoredRun(coordinates: coordinates, band: folded[index].band)
            }
        }
    }

    // MARK: Legend

    struct LegendEntry: Equatable, Sendable {
        var band: Int
        /// Short enough for five across a phone: the unit is the legend's, once.
        var label: String
        var spoken: String
    }

    /// The legend's unit, shown once beside the coloring's name.
    func legendUnit(_ unit: UnitSystem) -> String {
        switch coloring {
        case .plain: ""
        case .speed: unit.speedLabel
        case .grade: "%"
        case .heartRate: "bpm"
        case .cadence: "rpm"
        }
    }

    /// Each band the coloring uses, low to high, in the rider's units. Empty for Plain, and for
    /// Speed with no moving second.
    func legend(_ unit: UnitSystem) -> [LegendEntry] {
        switch coloring {
        case .plain:
            return []
        case .speed:
            guard let speedSpan else { return [] }
            let width = speedSpan.upperBound - speedSpan.lowerBound
            func shown(_ mps: Double) -> String { unit.speed(fromMPS: mps).formatted(.number.precision(.fractionLength(0))) }
            func spoken(_ mps: Double) -> String { unit.spokenSpeed(fromMPS: mps, fractionLength: 0) }
            guard width > 0 else {
                return [LegendEntry(band: 3, label: shown(speedSpan.lowerBound), spoken: spoken(speedSpan.lowerBound))]
            }
            let edges = (0...5).map { speedSpan.lowerBound + width * Double($0) / 5 }
            return Self.bands(edges.map(shown), spokenEdges: edges.map(spoken))
        case .grade:
            let edges = [0, 3, 6, 9, 12, 15].map { "\($0)" }
            return Self.bands(edges, spokenEdges: edges.map { "\($0) percent" })
        case .heartRate:
            return heartRateZones.enumerated().map { index, range in
                LegendEntry(band: index + 1, label: "\(range.lowerBound)–\(range.upperBound)",
                            spoken: "Zone \(index + 1), \(range.lowerBound) to \(range.upperBound) beats per minute")
            }
        case .cadence:
            // Zone 1's floor is S12's display floor; a slower pedal stroke is still zone 1.
            let edges = CadenceZone.allCases.map { "\(cadenceZones.lowerBound(of: $0))" }
                + ["\(CadenceZoneBoundaries.ceilingRPM)"]
            return Self.bands(edges, spokenEdges: edges.map { "\($0) r p m" })
                .map { entry in
                    var entry = entry
                    entry.spoken = "Zone \(entry.band), \(entry.spoken)"
                    return entry
                }
        }
    }

    /// Five bands from six edges: under the second edge, the three between, and the fifth edge
    /// and over. The first and last edges only bound the scale.
    private static func bands(_ edges: [String], spokenEdges: [String]) -> [LegendEntry] {
        (1...5).map { band in
            switch band {
            case 1: LegendEntry(band: 1, label: "<\(edges[1])", spoken: "under \(spokenEdges[1])")
            case 5: LegendEntry(band: 5, label: "\(edges[4])+", spoken: "\(spokenEdges[4]) and over")
            default: LegendEntry(band: band, label: "\(edges[band - 1])–\(edges[band])",
                                 spoken: "\(edges[band - 1]) to \(spokenEdges[band])")
            }
        }
    }
}
