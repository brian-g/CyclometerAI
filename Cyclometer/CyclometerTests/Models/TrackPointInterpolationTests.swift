import Foundation
import Testing
@testable import Cyclometer

@Suite("TrackPointDTO.interpolatingUntrustedPositions — a poor-GPS second on the line the map draws")
struct TrackPointInterpolationTests {

    private let rideId = UUID()
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    /// A point `second`s into the ride. Untrusted ones are recorded, as the ride records them,
    /// at the last trusted position.
    private func point(_ second: TimeInterval, _ latitude: Double, _ longitude: Double,
                       trusted: Bool = true, segment: Int = 0, bpm: Int? = nil) -> TrackPointDTO {
        TrackPointDTO(
            rideId: rideId, timestamp: start.addingTimeInterval(second),
            latitude: latitude, longitude: longitude, horizontalAccuracyMeters: trusted ? 2 : 35,
            speedSource: .bleWheel, heartRateBPM: bpm, heartRateSource: bpm == nil ? .none : .bleHR,
            segmentIndex: segment, isPositionTrusted: trusted
        )
    }

    @Test("A run between two trusted points lands on the line between them, in proportion to time")
    func runBetweenTrustedPointsIsInterpolated() {
        let track = [
            point(0, 10, 20),
            point(1, 10, 20, trusted: false, bpm: 120),
            point(3, 10, 20, trusted: false, bpm: 121),
            point(4, 14, 28)
        ]
        let result = TrackPointDTO.interpolatingUntrustedPositions(track)
        #expect(result.map(\.latitude) == [10, 11, 13, 14])
        #expect(result.map(\.longitude) == [20, 22, 26, 28])
        // Only the position moves: the second's readings and the flag are what was recorded.
        #expect(result.map(\.heartRateBPM) == [nil, 120, 121, nil])
        #expect(result.map(\.isPositionTrusted) == [true, false, false, true])
    }

    @Test("A run at the end of a segment keeps the position it was recorded with")
    func trailingRunKeepsHeldPosition() {
        let track = [point(0, 10, 20), point(1, 10, 20, trusted: false), point(2, 10, 20, trusted: false)]
        #expect(TrackPointDTO.interpolatingUntrustedPositions(track) == track)
    }

    @Test("Interpolation never reaches across a pause to the next segment's trusted point")
    func neverCrossesASegmentBoundary() {
        let track = [
            point(0, 10, 20),
            point(1, 10, 20, trusted: false),
            point(60, 50, 60, segment: 1),
            point(61, 50, 60, trusted: false, segment: 1),
            point(62, 52, 62, segment: 1)
        ]
        let result = TrackPointDTO.interpolatingUntrustedPositions(track)
        // Segment 0's run has no trusted point after it in its own segment, so it holds.
        #expect(result[1].latitude == 10 && result[1].longitude == 20)
        #expect(result[3].latitude == 51 && result[3].longitude == 61)
        #expect(result.map(\.segmentIndex) == [0, 0, 1, 1, 1])
    }

    @Test("A run opening a segment takes its first trusted position, not the one held from before the pause")
    func leadingRunTakesFirstTrustedPosition() {
        // Paused at (10, 20), moved while paused, resumed under a poor fix: the run holds the
        // position from before the pause until the first trusted fix at (50, 60).
        let track = [
            point(0, 10, 20),
            point(60, 10, 20, trusted: false, segment: 1),
            point(61, 10, 20, trusted: false, segment: 1, bpm: 120),
            point(62, 50, 60, segment: 1)
        ]
        let result = TrackPointDTO.interpolatingUntrustedPositions(track)
        #expect(result.map(\.latitude) == [10, 50, 50, 50])
        #expect(result.map(\.longitude) == [20, 60, 60, 60])
        #expect(result.map(\.heartRateBPM) == [nil, nil, 120, nil])
    }

    @Test("A track of trusted points comes back unchanged")
    func allTrustedIsUnchanged() {
        let track = [point(0, 10, 20), point(1, 11, 21), point(5, 30, 40, segment: 1)]
        #expect(TrackPointDTO.interpolatingUntrustedPositions(track) == track)
        #expect(TrackPointDTO.interpolatingUntrustedPositions([]).isEmpty)
    }
}
