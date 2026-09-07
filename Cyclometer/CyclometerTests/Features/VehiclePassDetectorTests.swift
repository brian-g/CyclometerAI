import Testing
import Foundation
@testable import Cyclometer

@Suite("VehiclePassDetector")
struct VehiclePassDetectorTests {
    private static let start = Date(timeIntervalSince1970: 1_000_000)
    private static let rideId = UUID()
    private static let coordinate = Coordinate(latitude: 43.0731, longitude: -89.4012)

    /// `range` defaults to 4 m — well inside `passProximityMetres`, so a track built
    /// from the default reads as a vehicle that genuinely reached the rider. Tests
    /// about the proximity criterion itself pass it explicitly.
    private static func target(mps: Double, id: UUID, range: Double = 4) -> RadarTarget {
        RadarTarget(id: id, relativeVelocityMPS: mps, rangeMetres: range, threatLevel: .allClear)
    }

    @Test("A vehicle tracked >= 2s with majority-positive closing speed that then disappears past the grace period produces exactly one pass event, positioned at the last sighting")
    func overtakeProducesOnePassEvent() throws {
        let id = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]

        _ = VehiclePassDetector.processTick(
            targets: [Self.target(mps: 8, id: id)],
            trackedVehicles: &tracking, now: Self.start, rideId: Self.rideId,
            alertLevel: .caution, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )
        _ = VehiclePassDetector.processTick(
            targets: [Self.target(mps: 8, id: id)],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(2), rideId: Self.rideId,
            // Neither this level nor the confirmation tick's below reaches the event:
            // both differ from the first tick's, which is the one that set the peak.
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        let events = VehiclePassDetector.processTick(
            targets: [],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(4), rideId: Self.rideId,
            alertLevel: .danger, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        let event = try #require(events.first)
        #expect(events.count == 1)
        #expect(event.rideId == Self.rideId)
        // The last-seen moment, not the (2s later) confirmation tick.
        #expect(event.timestamp == Self.start.addingTimeInterval(2))
        #expect(event.latitude == Self.coordinate.latitude)
        #expect(event.longitude == Self.coordinate.longitude)
        // The peak-closing tick (#209) — here the first, since tick two ties at 8 m/s
        // and a tie does not displace the incumbent. Not the last sighting (.clear),
        // and not the confirmation tick (.danger).
        #expect(event.alertLevelAtPass == .caution)
        #expect(event.riderSpeedKph == 6 * AlertLevel.kphPerMPS)
        #expect(event.estimatedPassSpeedKph == (6 + 8) * AlertLevel.kphPerMPS)
        #expect(tracking[id] == nil)
    }

    @Test("A vehicle absent for less than the disappearance grace period is left tracked untouched, not finalized")
    func absenceWithinGracePeriodDoesNotFinalize() {
        let id = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]

        _ = VehiclePassDetector.processTick(
            targets: [Self.target(mps: 8, id: id)],
            trackedVehicles: &tracking, now: Self.start, rideId: Self.rideId,
            alertLevel: .caution, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )
        let recordBeforeGap = tracking[id]

        // One dropped BLE notification: absent for 1s, under the 2s grace period.
        let events = VehiclePassDetector.processTick(
            targets: [],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(1), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        #expect(events.isEmpty)
        // Untouched — not removed, not reset — so a reappearance resumes exactly
        // where it left off.
        #expect(tracking[id] == recordBeforeGap)
    }

    @Test("A vehicle that reappears inside the grace period resumes its existing history instead of restarting")
    func reappearanceWithinGracePeriodResumesHistory() throws {
        let id = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]

        _ = VehiclePassDetector.processTick(
            targets: [Self.target(mps: 8, id: id)],
            trackedVehicles: &tracking, now: Self.start, rideId: Self.rideId,
            alertLevel: .caution, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )
        // Missed one notification, then reacquired the same vehicle.
        _ = VehiclePassDetector.processTick(
            targets: [],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(1), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )
        _ = VehiclePassDetector.processTick(
            targets: [Self.target(mps: 8, id: id)],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(2), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        // firstSeenAt survived the gap — the vehicle has now genuinely been tracked
        // continuously (in wall-clock terms) for 2s despite the one missed tick.
        let events = VehiclePassDetector.processTick(
            targets: [],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(4), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        let event = try #require(events.first)
        #expect(events.count == 1)
        #expect(event.timestamp == Self.start.addingTimeInterval(2))
        #expect(event.estimatedPassSpeedKph == (6 + 8) * AlertLevel.kphPerMPS)
    }

    @Test("A vehicle lost while still beyond the proximity threshold produces no event")
    func lostBeyondProximityThresholdProducesNoEvent() {
        let id = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]

        // Closing hard the whole time — 50 km/h of closing speed, never once
        // receding — but never nearer than 52 m. This is the shape of the
        // 2026-09-06 12:01:03 capture #207 was filed for, which the majority-positive
        // closing-speed guard this replaces recorded as a `danger` pass.
        for (offset, range) in [(0.0, 93.0), (1.0, 72.0), (2.0, 52.0)] {
            _ = VehiclePassDetector.processTick(
                targets: [Self.target(mps: 50 / AlertLevel.kphPerMPS, id: id, range: range)],
                trackedVehicles: &tracking, now: Self.start.addingTimeInterval(offset),
                rideId: Self.rideId, alertLevel: .danger,
                riderCoordinate: Self.coordinate, riderSpeedMPS: 6
            )
        }
        let events = VehiclePassDetector.processTick(
            targets: [],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(4), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        #expect(events.isEmpty)
        #expect(tracking[id] == nil)
    }

    @Test("A vehicle that closes to exactly the proximity threshold produces an event")
    func closingToExactlyTheThresholdProducesEvent() throws {
        let id = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]

        for (offset, range) in [(0.0, 40.0), (2.0, VehiclePassDetector.passProximityMetres)] {
            _ = VehiclePassDetector.processTick(
                targets: [Self.target(mps: 8, id: id, range: range)],
                trackedVehicles: &tracking, now: Self.start.addingTimeInterval(offset),
                rideId: Self.rideId, alertLevel: .caution,
                riderCoordinate: Self.coordinate, riderSpeedMPS: 6
            )
        }
        let events = VehiclePassDetector.processTick(
            targets: [],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(4), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        // The threshold is inclusive — a vehicle that reached exactly it did pass.
        #expect(events.count == 1)
        _ = try #require(events.first)
    }

    @Test("A vehicle that stops one metre short of the proximity threshold produces no event")
    func closingToJustBeyondTheThresholdProducesNoEvent() {
        let id = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]

        // One metre is the wire's own resolution — the range byte is whole metres —
        // so this is the tightest rejection the hardware can express.
        for (offset, range) in [(0.0, 40.0), (2.0, VehiclePassDetector.passProximityMetres + 1)] {
            _ = VehiclePassDetector.processTick(
                targets: [Self.target(mps: 8, id: id, range: range)],
                trackedVehicles: &tracking, now: Self.start.addingTimeInterval(offset),
                rideId: Self.rideId, alertLevel: .caution,
                riderCoordinate: Self.coordinate, riderSpeedMPS: 6
            )
        }
        let events = VehiclePassDetector.processTick(
            targets: [],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(4), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        #expect(events.isEmpty)
    }

    @Test("The closest range ever seen decides the pass, not the range at the last sighting")
    func minimumRangeIsRetainedAfterMovingAway() throws {
        let id = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]

        // Reaches 3 m, then the last frames report it further out again. The Varia's
        // range byte does drift back up as a vehicle clears the beam, so the criterion
        // has to hold the minimum rather than read whatever the final frame said.
        for (offset, range) in [(0.0, 60.0), (1.0, 3.0), (2.0, 30.0)] {
            _ = VehiclePassDetector.processTick(
                targets: [Self.target(mps: 8, id: id, range: range)],
                trackedVehicles: &tracking, now: Self.start.addingTimeInterval(offset),
                rideId: Self.rideId, alertLevel: .caution,
                riderCoordinate: Self.coordinate, riderSpeedMPS: 6
            )
        }
        let events = VehiclePassDetector.processTick(
            targets: [],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(4), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        #expect(events.count == 1)
        _ = try #require(events.first)
    }

    @Test("A track with no positive closing-speed samples reports a nil pass-speed estimate")
    func allZeroClosingSpeedYieldsNilEstimate() throws {
        let id = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]

        // Not reachable from live hardware — the wire's closing speed is an unsigned
        // byte and not one frame of the 2026-09-06 capture carried even a zero. This
        // pins PRD §8.7's "omitted if insufficient data" branch: a peak of 0 means the
        // vehicle was never once observed approaching, so there is nothing to add the
        // rider's speed to.
        for offset in [0.0, 2.0] {
            _ = VehiclePassDetector.processTick(
                targets: [Self.target(mps: 0, id: id)],
                trackedVehicles: &tracking, now: Self.start.addingTimeInterval(offset),
                rideId: Self.rideId, alertLevel: .clear,
                riderCoordinate: Self.coordinate, riderSpeedMPS: 6
            )
        }
        let events = VehiclePassDetector.processTick(
            targets: [],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(4), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        let event = try #require(events.first)
        #expect(event.estimatedPassSpeedKph == nil)
    }

    @Test("A vehicle tracked less than the 2s minimum produces no event even if approaching and confirmed gone")
    func trackedLessThanMinimumDurationProducesNoEvent() {
        let id = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]

        _ = VehiclePassDetector.processTick(
            targets: [Self.target(mps: 8, id: id)],
            trackedVehicles: &tracking, now: Self.start, rideId: Self.rideId,
            alertLevel: .caution, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )
        // Single sighting only — disappearance is confirmed (grace elapsed) but the
        // vehicle was never actually observed for 2 continuous seconds.
        let events = VehiclePassDetector.processTick(
            targets: [],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(2), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        #expect(events.isEmpty)
        #expect(tracking[id] == nil)
    }

    @Test("No GPS fix at the last sighting before a pass drops the event, still clearing the tracked vehicle")
    func noGPSFixDropsEvent() {
        let id = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]

        _ = VehiclePassDetector.processTick(
            targets: [Self.target(mps: 8, id: id)],
            trackedVehicles: &tracking, now: Self.start, rideId: Self.rideId,
            alertLevel: .caution, riderCoordinate: nil, riderSpeedMPS: 6
        )
        _ = VehiclePassDetector.processTick(
            targets: [Self.target(mps: 8, id: id)],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(2), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: nil, riderSpeedMPS: 6
        )
        // A fix arriving only on the confirmation tick doesn't help — the cached
        // last-known position (nil) is what matters, not this tick's.
        let events = VehiclePassDetector.processTick(
            targets: [],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(4), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        #expect(events.isEmpty)
        #expect(tracking[id] == nil)
    }

    /// Feeds `(mps, range)` samples one second apart, then confirms the disappearance,
    /// and returns the single event. The pass-speed tests below differ only in the
    /// track they feed, so the ceremony is hoisted here.
    private static func passSpeed(
        forTrack track: [(mps: Double, range: Double)],
        riderSpeedMPS: Double
    ) throws -> Double? {
        let id = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]

        for (offset, sample) in track.enumerated() {
            _ = VehiclePassDetector.processTick(
                targets: [Self.target(mps: sample.mps, id: id, range: sample.range)],
                trackedVehicles: &tracking, now: Self.start.addingTimeInterval(TimeInterval(offset)),
                rideId: Self.rideId, alertLevel: .caution,
                riderCoordinate: Self.coordinate, riderSpeedMPS: riderSpeedMPS
            )
        }
        let events = VehiclePassDetector.processTick(
            targets: [],
            trackedVehicles: &tracking,
            now: Self.start.addingTimeInterval(TimeInterval(track.count) + 2),
            rideId: Self.rideId, alertLevel: .clear,
            riderCoordinate: Self.coordinate, riderSpeedMPS: riderSpeedMPS
        )
        return try #require(events.first).estimatedPassSpeedKph
    }

    @Test("estimatedPassSpeedKph is the rider's speed plus the peak closing sample, in km/h")
    func estimatedPassSpeedIsPeakClosingSamplePlusRiderSpeed() throws {
        // The peak is neither the mean (6 m/s) nor the last sample (6 m/s), so this
        // fails against the whole-track average this replaced (#208).
        let estimate = try Self.passSpeed(
            forTrack: [(4, 4), (8, 4), (6, 4)],
            riderSpeedMPS: 6
        )

        #expect(estimate == (6 + 8) * AlertLevel.kphPerMPS)
        #expect(estimate != (6 + 6) * AlertLevel.kphPerMPS)
    }

    @Test("The cos(theta) tail as a vehicle draws alongside does not drag the estimate down")
    func estimatedPassSpeedIgnoresTheDecayingTail() throws {
        // The shape every genuine overtake in the 2026-09-06 capture has: closing hard
        // while lined up behind, then a decaying radial component as the vehicle moves
        // laterally into the passing lane. The peak at acquisition is the physically
        // meaningful figure; the whole-track mean here would be 9 m/s.
        let estimate = try Self.passSpeed(
            forTrack: [(16, 80), (12, 40), (6, 12), (2, 4)],
            riderSpeedMPS: 6
        )

        #expect(estimate == (6 + 16) * AlertLevel.kphPerMPS)
        #expect(estimate != (6 + 9) * AlertLevel.kphPerMPS)
    }

    @Test("A track with no decaying tail is unmoved by the switch from whole-track mean to peak")
    func constantClosingSpeedIsUnchangedByTheEstimatorSwitch() throws {
        // #208's fourth acceptance criterion, restated so it can actually be tested.
        // It named the 16:01:03 capture, but #207 rejects that vehicle at 52 m and it
        // now produces no event at all (`VehiclePassDetectorReplayTests`), so the
        // criterion's intent is pinned here instead: where closing speed is constant,
        // peak == mean, and that half of the change is a no-op. Verified by reverting —
        // with the whole-track mean restored and the rider term kept, this test still
        // passes while the two above fail. It is not invariant under the other half:
        // adding the rider's speed necessarily moves every event.
        let estimate = try Self.passSpeed(
            forTrack: [(13, 80), (13, 40), (13, 4)],
            riderSpeedMPS: 6
        )

        #expect(estimate == (6 + 13) * AlertLevel.kphPerMPS)
    }

    @Test("Tracking accumulates independently per vehicle id and only finalizes the one that disappeared")
    func trackingIsIndependentPerVehicle() {
        let staying = UUID()
        let leaving = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]

        for offset in [0, 2] {
            _ = VehiclePassDetector.processTick(
                targets: [Self.target(mps: 8, id: leaving), Self.target(mps: 5, id: staying)],
                trackedVehicles: &tracking, now: Self.start.addingTimeInterval(TimeInterval(offset)),
                rideId: Self.rideId, alertLevel: .caution,
                riderCoordinate: Self.coordinate, riderSpeedMPS: 6
            )
        }
        let events = VehiclePassDetector.processTick(
            targets: [Self.target(mps: 5, id: staying)],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(4), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        #expect(events.count == 1)
        #expect(tracking[leaving] == nil)
        #expect(tracking[staying] == VehicleTrackingRecord(
            firstSeenAt: Self.start,
            lastSeenAt: Self.start.addingTimeInterval(4),
            sampleCount: 3, maxPositiveClosingMPS: 5,
            minimumRangeMetres: 4,
            // .caution, from the offset-0 tick that set the 5 m/s peak — the two later
            // ties leave it alone, including the .clear tick that last touched the
            // record (#209).
            lastKnownCoordinate: Self.coordinate, lastRiderSpeedMPS: 6, alertLevelAtPeakClosing: .caution
        ))
    }

    // MARK: - Alert level at the peak (#209)

    @Test("A track whose alert level peaks mid-encounter and decays before disappearance records the peak")
    func alertLevelIsTakenFromThePeakNotTheDecayingTail() throws {
        // The shape every genuine overtake in the 2026-09-06 capture has: closing hard
        // while lined up behind, then a decaying radial component as the vehicle moves
        // laterally into the passing lane. Under the last-sighting snapshot this
        // replaced, the event took `.caution` off the 2 m/s tail — the least severe
        // instant of the encounter, and the inversion #209 was filed for.
        let id = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]
        let track: [(mps: Double, level: AlertLevel)] = [(4, .advisory), (10, .danger), (2, .caution)]

        for (offset, sample) in track.enumerated() {
            _ = VehiclePassDetector.processTick(
                targets: [Self.target(mps: sample.mps, id: id)],
                trackedVehicles: &tracking, now: Self.start.addingTimeInterval(TimeInterval(offset)),
                rideId: Self.rideId, alertLevel: sample.level,
                riderCoordinate: Self.coordinate, riderSpeedMPS: 6
            )
        }
        let events = VehiclePassDetector.processTick(
            targets: [], trackedVehicles: &tracking,
            now: Self.start.addingTimeInterval(5), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        let event = try #require(events.first)
        #expect(event.alertLevelAtPass == .danger)
        #expect(event.alertLevelAtPass != .caution)
        // The same sample the pass-speed estimate is taken from: after #209 the two
        // exported fields agree on which instant they describe.
        #expect(event.estimatedPassSpeedKph == (6 + 10) * AlertLevel.kphPerMPS)
    }

    @Test("Across a plateau at the peak, the first frame's alert level is the one kept")
    func plateauKeepsTheFirstFrameAtThePeak() throws {
        // Peaks in the capture are held for 4–12 consecutive frames, and the first is
        // the acquisition frame at 87–135 m where theta is near zero. This pins the
        // fold's strict `>`: under `>=` the level would walk forward across the
        // plateau and settle on the frame nearest the rider, which is the geometry
        // #209 exists to get away from.
        let id = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]

        for (offset, level) in [AlertLevel.danger, .caution, .advisory].enumerated() {
            _ = VehiclePassDetector.processTick(
                targets: [Self.target(mps: 9, id: id)],
                trackedVehicles: &tracking, now: Self.start.addingTimeInterval(TimeInterval(offset)),
                rideId: Self.rideId, alertLevel: level,
                riderCoordinate: Self.coordinate, riderSpeedMPS: 6
            )
        }
        let events = VehiclePassDetector.processTick(
            targets: [], trackedVehicles: &tracking,
            now: Self.start.addingTimeInterval(5), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        #expect(try #require(events.first).alertLevelAtPass == .danger)
    }

    @Test("The level recorded is the ride-level alert at the peak tick, so a faster concurrent vehicle sets it")
    func recordedLevelIsTheRideLevelAlertAtThePeakTick() throws {
        // Deliberate, not incidental. `processTick` is handed `AlertLevel.level(for:)`
        // over *every* current target, so a second, faster vehicle present at this
        // one's peak is what this one records. #209 bounds that to the single peak
        // tick rather than removing it: a running max over the encounter would let any
        // later spike in and, since a max only rises, keep it for the rest of the
        // track — and `level(for:)`'s `approaching.count >= 3` clause alone would then
        // stamp `caution` on every pass in traffic regardless of speed.
        let slow = UUID()
        let fast = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]

        // 20 m/s is 72 km/h closing, well past `dangerClosingSpeedKPH`.
        let together = [Self.target(mps: 4, id: slow), Self.target(mps: 20, id: fast)]
        _ = VehiclePassDetector.processTick(
            targets: together, trackedVehicles: &tracking, now: Self.start,
            rideId: Self.rideId, alertLevel: AlertLevel.level(for: together),
            riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )
        let alone = [Self.target(mps: 4, id: slow)]
        for offset in [1.0, 2.0] {
            _ = VehiclePassDetector.processTick(
                targets: alone, trackedVehicles: &tracking,
                now: Self.start.addingTimeInterval(offset), rideId: Self.rideId,
                alertLevel: AlertLevel.level(for: alone),
                riderCoordinate: Self.coordinate, riderSpeedMPS: 6
            )
        }
        let events = VehiclePassDetector.processTick(
            targets: [], trackedVehicles: &tracking,
            now: Self.start.addingTimeInterval(5), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        // Only the slow vehicle produces one: the fast one was seen on a single tick,
        // so it fails `minimumTrackedDuration`.
        #expect(events.count == 1)
        let event = try #require(events.first)
        // 4 m/s is 14.4 km/h closing — on its own that is `advisory`, below
        // `moderateClosingSpeedKPH`. What lands is the level the *rider* was under.
        #expect(AlertLevel.level(for: alone) == .advisory)
        #expect(event.alertLevelAtPass == .danger)
        #expect(event.estimatedPassSpeedKph == (6 + 4) * AlertLevel.kphPerMPS)
    }
}
