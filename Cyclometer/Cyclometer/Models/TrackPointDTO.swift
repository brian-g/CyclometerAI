import Foundation

/// Sensor-facing shape for a single 1Hz recorded sample. Optionals carry "no source"
/// here; sentinel encoding for CoreData (-1.0 / 0) happens only at the TrackPointMO
/// mapping boundary, never on this type.
struct TrackPointDTO: Sendable, Equatable {
    var id: UUID = UUID()
    var rideId: UUID
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    /// Nil when CoreLocation marked the fix's altitude invalid (#303).
    var altitudeMeters: Double?
    var horizontalAccuracyMeters: Double
    var speedMPS: Double?
    var speedSource: SensorSource
    var heartRateBPM: Int?
    var heartRateSource: SensorSource
    var cadenceRPM: Int?
    var powerWatts: Int?
    /// Which continuous stretch of riding this point belongs to (#263). Zero for the
    /// first, incremented by every resume, so a pause is a boundary in the data rather
    /// than something a reader has to infer from a time gap — a GPS dropout in a tunnel
    /// leaves the same gap and is not a pause.
    ///
    /// Last, with a default, so every existing `TrackPointDTO(...)` literal still compiles
    /// and still means what it did: one segment, index 0.
    var segmentIndex: Int = 0
    /// False for a second recorded while `GPSFixFilter` held the fix back: the point is
    /// there for its sensor readings, and its position is the last trusted one, held. A
    /// saved track's reader gets it on the line between its trusted neighbours instead
    /// (`interpolatingUntrustedPositions`).
    ///
    /// Before this, a second with a poor fix recorded nothing, so heart rate, cadence and
    /// speed under tree cover kept one second in every 10 — one in 60 once the backstop
    /// stopped taking fixes worse than 20 m (#624 review).
    var isPositionTrusted: Bool = true
}

extension TrackPointDTO {
    /// Splits track points into runs of equal `segmentIndex` (#263).
    ///
    /// Consecutive runs, not a group-by: the points arrive ascending by timestamp, so a
    /// change of index is a boundary, and grouping by value would reorder the ride if an
    /// index ever repeated. Always returns at least one segment, possibly empty — the GPX
    /// export writes it as the one empty `<trkseg>` a pointless ride has always had. Callers
    /// that draw or measure should drop segments too short for that (`RideMapThumbnail`).
    static func segments(of trackPoints: [TrackPointDTO]) -> [[TrackPointDTO]] {
        var segments: [[TrackPointDTO]] = [[]]
        for point in trackPoints {
            if let previous = segments[segments.count - 1].last,
               previous.segmentIndex != point.segmentIndex {
                segments.append([])
            }
            segments[segments.count - 1].append(point)
        }
        return segments
    }

    /// The track with every untrusted point placed on the straight line between the trusted
    /// points either side of it in its segment, in proportion to time: where the map draws the
    /// rider across a stretch of poor GPS, so every reader of a saved track — map, GPX, Health
    /// route, energy — agrees with it.
    ///
    /// A run without a trusted point on both sides in its segment keeps the position it was
    /// recorded with, the last trusted one. Never across a segment boundary: the rider was paused there,
    /// and a line across it is the chord #263 removed.
    static func interpolatingUntrustedPositions(_ trackPoints: [TrackPointDTO]) -> [TrackPointDTO] {
        guard trackPoints.contains(where: { !$0.isPositionTrusted }) else { return trackPoints }
        return segments(of: trackPoints).flatMap { segment -> [TrackPointDTO] in
            var segment = segment
            var before: TrackPointDTO?
            var index = segment.startIndex
            while index < segment.endIndex {
                guard !segment[index].isPositionTrusted else {
                    before = segment[index]
                    index += 1
                    continue
                }
                let runEnd = segment[index...].firstIndex(where: \.isPositionTrusted) ?? segment.endIndex
                if let before, runEnd < segment.endIndex {
                    let after = segment[runEnd]
                    let span = after.timestamp.timeIntervalSince(before.timestamp)
                    for inRun in index..<runEnd where span > 0 {
                        let fraction = segment[inRun].timestamp.timeIntervalSince(before.timestamp) / span
                        segment[inRun].latitude = before.latitude + (after.latitude - before.latitude) * fraction
                        segment[inRun].longitude = before.longitude + (after.longitude - before.longitude) * fraction
                    }
                }
                index = runEnd
            }
            return segment
        }
    }
}
