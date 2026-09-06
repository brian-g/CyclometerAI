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
    ///
    /// `riderSpeedMPS` defaults to the arbitrary 6 m/s the classification tests have
    /// always used; the pass-speed tests below pass the rider's real speed from that
    /// ride's GPX, because the reported inversion only reproduces against it (#208).
    private static func replay(
        _ track: RadarPassFixtures.Track,
        riderSpeedMPS: Double = 6
    ) -> [VehiclePassEventDTO] {
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
                riderSpeedMPS: riderSpeedMPS
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
            riderSpeedMPS: riderSpeedMPS
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

    // MARK: - Pass-speed estimate (#208)

    /// The rider's own speed at each pass, read from the `<cyc:riderSpeedKph>` of the
    /// matching `<wpt>` in `Cyclometer_2026-09-06_11-55.gpx`. The harness's default
    /// 6 m/s (21.6 kph) is slower than every one of these, which is why the exported
    /// estimate has to be checked against the real figure: at 21.6 kph even the old
    /// whole-track mean cleared the rider's speed, so a test run at the default would
    /// have passed against the very bug #208 was filed for.
    private static let riderKphAtPass: [String: Double] = [
        "pass1158": 17.6, "pass1200_09": 33.6, "pass1200_30": 27.3, "pass1200_50": 24.9,
    ]

    @Test("Every captured overtake exports the rider's speed plus that track's peak closing speed")
    func overtakesExportRiderSpeedPlusPeakClosingSpeed() throws {
        for track in RadarPassFixtures.all where track.isGenuinePass {
            let riderKph = try #require(Self.riderKphAtPass[track.name])
            let riderMPS = riderKph / AlertLevel.kphPerMPS
            let peakKph = try #require(track.frames.map(\.kph).max())

            let event = try #require(Self.replay(track, riderSpeedMPS: riderMPS).first, "\(track.name)")
            let estimate = try #require(event.estimatedPassSpeedKph, "\(track.name)")

            // Written in the detector's own evaluation order rather than as a decimal
            // literal: the fixture's km/h -> m/s -> km/h round-trip leaves three of
            // these four a single ULP off the round number (80.6, 87.6, 81.3, 71.9),
            // so `== 87.6` would fail on three tracks and pass on one by luck.
            #expect(estimate == (riderMPS + Double(peakKph) / AlertLevel.kphPerMPS) * AlertLevel.kphPerMPS,
                    "\(track.name): \(estimate) != rider \(riderKph) + peak \(peakKph)")

            // #208's second acceptance criterion. Against the whole-track mean this
            // replaced, pass1200_09/_30/_50 all exported at or below their rider's
            // own speed — 26.9 against a rider doing 33.6, and so on.
            #expect(estimate > event.riderSpeedKph, "\(track.name)")
        }
    }

    @Test("The 16:00:09 pass — exported as 26.9 kph beneath a rider doing 33.6 — now reads 87.6")
    func theReportedInversionIsGone() throws {
        // #208's third acceptance criterion, and the row its bug report leads with.
        // This is the sharpest regression test in the suite: it is the one case where
        // the old estimator's output can be compared against a number a human checked.
        let track = RadarPassFixtures.pass1200_09
        let riderMPS = 33.6 / AlertLevel.kphPerMPS

        let event = try #require(Self.replay(track, riderSpeedMPS: riderMPS).first)
        let estimate = try #require(event.estimatedPassSpeedKph)

        #expect(event.riderSpeedKph == riderMPS * AlertLevel.kphPerMPS)
        // 33.6 + 54 = 87.6 kph — about 54 mph, on a road posted for 55.
        #expect(estimate == (riderMPS + 54 / AlertLevel.kphPerMPS) * AlertLevel.kphPerMPS)
        // The old whole-track mean put this car at 26.9, i.e. 6.7 kph slower than the
        // bicycle it had just overtaken.
        #expect(estimate > event.riderSpeedKph)
    }

    @Test("Each captured peak is a sustained plateau, not an isolated spike a max estimator would latch onto")
    func capturedPeaksAreSustainedNotSpikes() throws {
        // A running max has no noise rejection: one spurious high frame at acquisition
        // would set the exported figure for the whole track. That is acceptable only
        // because it is not what this hardware does — every peak here is held for
        // several frames and the next distinct value sits exactly 1 kph below. Same
        // role as the proximity-margin test above: if a future capture with a spiky
        // acquisition frame is added, this fails and forces a conversation about the
        // estimator rather than silently exporting a wrong number.
        for track in RadarPassFixtures.all {
            let speeds = track.frames.map(\.kph)
            let peak = try #require(speeds.max())
            let runnerUp = try #require(Set(speeds).sorted(by: >).dropFirst().first)

            // Longest run, not the leading one: four of the five tracks are acquired
            // at their peak, but noPass1201 opens at 48, dips to 47, and returns to 48
            // for its last twelve frames.
            let longestRunAtPeak = speeds
                .reduce(into: (best: 0, current: 0)) { acc, kph in
                    acc.current = kph == peak ? acc.current + 1 : 0
                    acc.best = max(acc.best, acc.current)
                }
                .best

            #expect(peak - runnerUp == 1, "\(track.name): peak \(peak) stands \(peak - runnerUp) kph clear")
            #expect(longestRunAtPeak >= 4,
                    "\(track.name): peak \(peak) held for only \(longestRunAtPeak) frames")
        }
    }
}
