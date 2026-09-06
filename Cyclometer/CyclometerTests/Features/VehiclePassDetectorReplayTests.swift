import Testing
import Foundation
@testable import Cyclometer

/// Replays the five real radar tracks in `RadarPassFixtures` through
/// `VehiclePassDetector.processTick` at the frames' own arrival spacing.
///
/// `VehiclePassDetectorTests` pins each criterion in isolation with hand-built tracks;
/// this suite pins them against what RTL15451 hardware actually emitted on the ride of
/// 2026-09-06 — including the vehicle that never reached the rider and was recorded as
/// a `danger` pass anyway, which is what #207 was filed for.
@Suite("VehiclePassDetector — 2026-09-06 capture replay")
struct VehiclePassDetectorReplayTests {
    private static let start = Date(timeIntervalSince1970: 1_000_000)
    private static let rideId = UUID()
    private static let coordinate = Coordinate(latitude: 36.0873546, longitude: -79.5468742)

    /// Feeds one captured track through the detector frame by frame at the offsets the
    /// hardware delivered them, then lets `disappearanceGracePeriod` elapse so the
    /// vehicle's absence is treated as final, and returns every event confirmed.
    private static func replay(_ track: RadarPassFixtures.Track) -> [VehiclePassEventDTO] {
        let id = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]
        var events: [VehiclePassEventDTO] = []

        for frame in track.frames {
            let target = RadarTarget(
                id: id,
                relativeVelocityMPS: Double(frame.kph) / AlertLevel.kphPerMPS,
                rangeMetres: Double(frame.range),
                threatLevel: .warning
            )
            events += VehiclePassDetector.processTick(
                targets: [target],
                trackedVehicles: &tracking,
                now: start.addingTimeInterval(Double(frame.ms) / 1000),
                rideId: rideId,
                alertLevel: AlertLevel.level(for: [target]),
                riderCoordinate: coordinate,
                riderSpeedMPS: 6
            )
        }

        let afterLastFrame = Double(track.frames.last?.ms ?? 0) / 1000
            + VehiclePassDetector.disappearanceGracePeriod + 1
        events += VehiclePassDetector.processTick(
            targets: [],
            trackedVehicles: &tracking,
            now: start.addingTimeInterval(afterLastFrame),
            rideId: rideId,
            alertLevel: .clear,
            riderCoordinate: coordinate,
            riderSpeedMPS: 6
        )
        return events
    }

    @Test("Every captured track is classified correctly — four overtakes, one vehicle that never arrived")
    func capturedTracksAreClassifiedCorrectly() {
        for track in RadarPassFixtures.all {
            let events = Self.replay(track)
            #expect(
                events.count == (track.isGenuinePass ? 1 : 0),
                "\(track.name), ending \(track.endsAt), produced \(events.count) event(s)"
            )
        }
    }

    @Test("The 16:01:03 vehicle, lost at 52 m while still closing at 48 km/h, produces no pass event")
    func vehicleLostBeyondThresholdProducesNoEvent() {
        let track = RadarPassFixtures.noPass1201

        // It satisfies every criterion the detector had before #207: tracked 3.4s,
        // and every one of its 29 samples approaching. Only range rejects it.
        #expect(track.frames.map { $0.range }.min() == 52)
        #expect(track.frames.allSatisfy { $0.kph > 0 })
        #expect(Double(track.frames.last?.ms ?? 0) / 1000 >= VehiclePassDetector.minimumTrackedDuration)

        #expect(Self.replay(track).isEmpty)
    }

    @Test("Each genuine overtake produces one event carrying the rider's position and alert level")
    func genuineOvertakesProduceAWellFormedEvent() throws {
        for track in RadarPassFixtures.all where track.isGenuinePass {
            let event = try #require(Self.replay(track).first, "\(track.name)")
            #expect(event.rideId == Self.rideId)
            #expect(event.latitude == Self.coordinate.latitude)
            #expect(event.longitude == Self.coordinate.longitude)
            #expect(event.riderSpeedKph == 6 * AlertLevel.kphPerMPS)
        }
    }

    @Test("The capture's separation is wide enough that the 10 m threshold is not finely tuned")
    func captureSeparatesGenuinePassesFromTheLostTrackByAWideMargin() {
        // Documents why `passProximityMetres` is not delicate: nothing in this capture
        // sits between 0 m and 52 m at the moment its track ends. If a future capture
        // narrows that gap, this fails and the threshold needs revisiting rather than
        // silently drifting.
        let closest = RadarPassFixtures.all.filter(\.isGenuinePass).compactMap { $0.frames.map { $0.range }.min() }
        let lost = RadarPassFixtures.all.filter { !$0.isGenuinePass }.compactMap { $0.frames.map { $0.range }.min() }

        #expect(closest.allSatisfy { Double($0) <= VehiclePassDetector.passProximityMetres })
        #expect(lost.allSatisfy { Double($0) > VehiclePassDetector.passProximityMetres })
        #expect(closest.max() ?? 0 == 0)
        #expect(lost.min() ?? 0 == 52)
    }
}
