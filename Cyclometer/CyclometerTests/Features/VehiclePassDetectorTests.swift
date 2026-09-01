import Testing
import Foundation
@testable import Cyclometer

@Suite("VehiclePassDetector")
struct VehiclePassDetectorTests {
    private static let start = Date(timeIntervalSince1970: 1_000_000)
    private static let rideId = UUID()
    private static let coordinate = Coordinate(latitude: 43.0731, longitude: -89.4012)

    private static func target(mps: Double, id: UUID) -> RadarTarget {
        RadarTarget(id: id, relativeVelocityMPS: mps, rangeMetres: 40, threatLevel: .allClear)
    }

    @Test("A vehicle tracked >= 2s with majority-positive closing speed that then disappears past the grace period produces exactly one pass event, using the last-seen snapshot")
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
            // Cached from this, the last sighting — not from the disappearance-
            // confirmation tick below, which deliberately uses a different level.
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
        #expect(event.alertLevelAtPass == .clear)
        #expect(event.riderSpeedKph == 6 * AlertLevel.kphPerMPS)
        #expect(event.estimatedPassSpeedKph == 8 * AlertLevel.kphPerMPS)
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
        #expect(event.estimatedPassSpeedKph == 8 * AlertLevel.kphPerMPS)
    }

    @Test("A vehicle that turns off or slows (majority non-positive) before disappearing produces no event")
    func turnOffOrSlowdownProducesNoEvent() {
        let id = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]

        _ = VehiclePassDetector.processTick(
            targets: [Self.target(mps: 8, id: id)],
            trackedVehicles: &tracking, now: Self.start, rideId: Self.rideId,
            alertLevel: .caution, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )
        _ = VehiclePassDetector.processTick(
            targets: [Self.target(mps: -3, id: id)],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(1), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )
        _ = VehiclePassDetector.processTick(
            targets: [Self.target(mps: -3, id: id)],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(2), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        // Tracked 2 continuous seconds (well past the minimum) but two of the three
        // samples are non-positive, so this is a turn-off/slowdown, not a pass.
        let events = VehiclePassDetector.processTick(
            targets: [],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(4), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        #expect(events.isEmpty)
        #expect(tracking[id] == nil)
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

    @Test("A zero closing-speed sample does not count as approaching")
    func zeroClosingSpeedIsNotApproaching() {
        let id = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]

        _ = VehiclePassDetector.processTick(
            targets: [Self.target(mps: 0, id: id)],
            trackedVehicles: &tracking, now: Self.start, rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )
        _ = VehiclePassDetector.processTick(
            targets: [Self.target(mps: 0, id: id)],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(2), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )
        let events = VehiclePassDetector.processTick(
            targets: [],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(4), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 6
        )

        #expect(events.isEmpty)
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

    @Test("estimatedPassSpeedKph is the average of only the positive closing-speed samples, in km/h")
    func estimatedPassSpeedIsAverageOfPositiveSamples() throws {
        let id = UUID()
        var tracking: [UUID: VehicleTrackingRecord] = [:]

        for (offset, mps) in [4.0, 8.0, 6.0].enumerated() {
            _ = VehiclePassDetector.processTick(
                targets: [Self.target(mps: mps, id: id)],
                trackedVehicles: &tracking, now: Self.start.addingTimeInterval(TimeInterval(offset)),
                rideId: Self.rideId, alertLevel: .caution,
                riderCoordinate: Self.coordinate, riderSpeedMPS: 0
            )
        }
        let events = VehiclePassDetector.processTick(
            targets: [],
            trackedVehicles: &tracking, now: Self.start.addingTimeInterval(4), rideId: Self.rideId,
            alertLevel: .clear, riderCoordinate: Self.coordinate, riderSpeedMPS: 0
        )

        let event = try #require(events.first)
        #expect(event.estimatedPassSpeedKph == 6.0 * AlertLevel.kphPerMPS)
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
            sampleCount: 3, positiveSampleCount: 3, positiveSampleSum: 15,
            lastKnownCoordinate: Self.coordinate, lastRiderSpeedMPS: 6, lastAlertLevel: .clear
        ))
    }
}
