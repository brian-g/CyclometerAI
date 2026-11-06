import Foundation

/// S15's map sheet's track (#537): every drawable point with the readings the route coloring
/// reads, one array per stretch of riding (#263), as `RideMapThumbnail.drawableSegments` splits it.
struct RideMapTrack: Equatable, Sendable {
    struct Point: Equatable, Sendable {
        var coordinate: RouteCoordinate
        var timestamp: Date
        var speedMPS: Double?
        var heartRateBPM: Int?
        var cadenceRPM: Int?
        /// Rise over `RouteTerrain.gradeWindowMeters` centred on the point, as S20 measures a
        /// route. Nil with no altitude (before the stretch's first reading or after its last), on a
        /// stretch shorter than the window, and where the altitude is too noisy to be road.
        var gradePercent: Double?
    }

    var segments: [[Point]]

    init(segments: [[Point]]) {
        self.segments = segments
    }

    init(points: [TrackPointDTO]) {
        segments = TrackPointDTO.segments(of: points)
            .filter { $0.count > 1 }
            .map { segment in
                let grades = Self.grades(segment)
                return segment.indices.map { index in
                    let point = segment[index]
                    return Point(
                        coordinate: RouteCoordinate(latitude: point.latitude, longitude: point.longitude),
                        timestamp: point.timestamp,
                        speedMPS: point.speedMPS,
                        heartRateBPM: point.heartRateBPM,
                        cadenceRPM: point.cadenceRPM,
                        gradePercent: grades?[index]
                    )
                }
            }
    }

    /// Every point, oldest first.
    var points: [Point] { segments.flatMap { $0 } }

    var hasSpeed: Bool { segments.contains { $0.contains { $0.speedMPS != nil } } }
    var hasGrade: Bool { segments.contains { $0.contains { $0.gradePercent != nil } } }
    var hasHeartRate: Bool { segments.contains { $0.contains { $0.heartRateBPM != nil } } }
    var hasCadence: Bool { segments.contains { $0.contains { ($0.cadenceRPM ?? 0) > 0 } } }

    /// Each point's grade along one stretch: the altitude resampled every
    /// `RouteTerrain.sampleSpacingMeters` by distance, then S20's centred grade window. Within the
    /// stretch only, so a grade never spans a pause, where the altitude moved without riding.
    ///
    /// No creek-fill smoothing (#533): that is for a terrain model's bare earth, and a ride's
    /// altitude is the barometer's.
    static func grades(_ segment: [TrackPointDTO]) -> [Double?]? {
        let coordinates = segment.map {
            RouteCoordinate(latitude: $0.latitude, longitude: $0.longitude, elevationMeters: $0.altitudeMeters)
        }
        let cumulative = RouteGeometry.cumulativeDistances(coordinates)
        guard let total = cumulative.last, total >= RouteTerrain.gradeWindowMeters else { return nil }
        // `elevationProfile` holds the first and last altitudes flat out to the stretch's ends. A
        // held altitude is no reading, not a flat road, so the points out there have no grade.
        let measured = segment.indices.filter { segment[$0].altitudeMeters != nil }
        guard let firstMeasured = measured.first, let lastMeasured = measured.last else { return nil }
        let measuredSpan = cumulative[firstMeasured]...cumulative[lastMeasured]
        let sampleCount = Int((total / RouteTerrain.sampleSpacingMeters).rounded()) + 1
        guard let profile = RouteGeometry.elevationProfile(coordinates, sampleCount: sampleCount),
              profile.count > 1 else { return nil }
        let spacing = total / Double(profile.count - 1)
        let grades = RouteTerrain.grades(profile, spacing: spacing)
        guard !grades.isEmpty else { return nil }
        return cumulative.map { distance in
            guard measuredSpan.contains(distance) else { return nil }
            let grade = grades[min(grades.count - 1, max(0, Int((distance / spacing).rounded())))]
            // `ElevationTracker`'s bar: steeper than any road is the altitude, not the road.
            return abs(grade) <= RideEnergy.maxPlausibleGrade * 100 ? grade : nil
        }
    }
}

/// A pause as S15's map marks it (#537): where the rider stopped, and for how long.
struct RideStop: Equatable, Sendable {
    var coordinate: RouteCoordinate
    var startedAt: Date
    var duration: TimeInterval
    var isAuto: Bool

    /// The marker's title, and all VoiceOver reads of it: which kind of pause, and how long.
    var title: String {
        let length = Duration.seconds(duration.rounded())
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
        return "\(isAuto ? "Auto-pause" : "Pause") · \(length)"
    }
}

enum RideStops {
    /// One stop per pause the rider resumed from, at the last point recorded at or before it
    /// began. A pause still open is where the ride ended, not a stop. A pause before the first
    /// point has nowhere to go and is left out.
    static func stops(pauses: [RidePause], track: RideMapTrack) -> [RideStop] {
        let points = track.points
        return pauses.compactMap { pause in
            guard let endedAt = pause.endedAt,
                  let point = points.last(where: { $0.timestamp <= pause.startedAt }) else { return nil }
            return RideStop(coordinate: point.coordinate, startedAt: pause.startedAt,
                            duration: endedAt.timeIntervalSince(pause.startedAt), isAuto: pause.isAuto)
        }
    }
}
