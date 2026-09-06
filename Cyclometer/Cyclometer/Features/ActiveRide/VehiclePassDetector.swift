import Foundation

/// Per-vehicle radar tracking history, keyed by `RadarTarget.id` — `VariaRadarClient`
/// keeps that id stable for the same real-world vehicle across ticks (resolved from
/// the wire's own threat id), so it doubles as the join key here with no separate
/// identity scheme needed. TCA.md §4.12.
///
/// Closing-speed samples are folded into running counters rather than kept as an
/// array: the pass-speed estimate only ever needs the count and sum of positive
/// samples, and a vehicle that lingers under the same wire id for a long time (a
/// stuck/phantom radar target) would otherwise grow that array for the rest of the
/// ride. `minimumRangeMetres` is folded the same way and for the same reason.
struct VehicleTrackingRecord: Equatable {
    var firstSeenAt: Date
    /// Updated on every tick the vehicle is present — the basis for both the
    /// tracked-duration check and the disappearance grace period below, since it's
    /// the last moment this vehicle was actually confirmed present.
    var lastSeenAt: Date
    var sampleCount: Int
    var positiveSampleCount: Int
    var positiveSampleSum: Double
    /// Closest this vehicle has ever come, in metres — the overtake criterion (#207).
    /// A vehicle that disappears without having come within
    /// `VehiclePassDetector.passProximityMetres` never reached the rider, so its
    /// disappearance is a lost track or a turn-off, not a pass.
    ///
    /// TCA.md §4.12 also specs a `lastDistance` alongside this. Deliberately omitted:
    /// nothing consumes it once the minimum is tracked, and the range trend it would
    /// describe is already implied by a vehicle reaching the proximity threshold.
    var minimumRangeMetres: Double
    /// Snapshotted from the tick that last saw this vehicle, not the tick that
    /// eventually confirms its disappearance — the rider may have moved, and the
    /// alert level may have changed for an unrelated vehicle, in the time it takes
    /// `disappearanceGracePeriod` to elapse.
    var lastKnownCoordinate: Coordinate?
    var lastRiderSpeedMPS: Double
    var lastAlertLevel: AlertLevel
}

/// Detects a genuine vehicle overtake from radar history, distinguishing it from a
/// vehicle that turned off or was lost before reaching the rider (#172, #207, PRD §8.7 /
/// DataModel.md §3.4). A plain pure function rather than a TCA reducer — there's no
/// independent lifecycle or UI here, just a per-tick fold over `ActiveRideFeature`'s
/// own tracking dictionary, called directly from `radarTargetsUpdated`.
enum VehiclePassDetector {
    /// Minimum continuous tracking duration before a disappearance counts as a pass
    /// rather than noise (PRD §8.7 / DataModel.md §3.4 detection criteria).
    static let minimumTrackedDuration: TimeInterval = 2

    /// How long a vehicle absent from `targets` is kept tracked, unresolved, before
    /// its disappearance is treated as final. Radar isn't a fixed-rate feed — a
    /// single dropped BLE notification would otherwise read as an instant
    /// disappearance, firing a premature pass on a vehicle still genuinely
    /// approaching (code review, #172). A reappearance inside this window resumes
    /// the existing record untouched, rather than starting a new one.
    static let disappearanceGracePeriod: TimeInterval = 2

    /// How close a vehicle must come before its disappearance counts as an overtake
    /// rather than a lost track — PRD §8.7's "distance reached minimum threshold",
    /// TCA.md §4.12's `minimumDistance` (#207).
    ///
    /// Calibrated against the ride of 2026-09-06, captured from RTL15451 hardware and
    /// replayed in `VehiclePassDetectorReplayTests`: its four genuine overtakes each
    /// spent 11–21 consecutive frames (~1.3–2.5 s) at or below 10 m and every one
    /// reached 0 m, while the single vehicle that never reached the rider was lost at
    /// 52 m. The margin is wide on both sides, so this tolerates radar dropping a
    /// genuinely passing vehicle several metres early without admitting that 52 m case.
    static let passProximityMetres: Double = 10

    /// Updates `trackedVehicles` in place for the current radar tick and returns any
    /// vehicle-pass events confirmed this tick (usually zero or one, but more than
    /// one radar target can legitimately disappear on the same tick).
    ///
    /// Detection criteria: tracked >= `minimumTrackedDuration` continuous seconds,
    /// came within `passProximityMetres` of the rider, then absent from `targets` for
    /// >= `disappearanceGracePeriod`. A vehicle that turned off or was lost before
    /// reaching the rider fails the proximity check and is dropped silently — same
    /// for one tracked less than the minimum duration.
    static func processTick(
        targets: [RadarTarget],
        trackedVehicles: inout [UUID: VehicleTrackingRecord],
        now: Date,
        rideId: UUID,
        alertLevel: AlertLevel,
        riderCoordinate: Coordinate?,
        riderSpeedMPS: Double
    ) -> [VehiclePassEventDTO] {
        for target in targets {
            let isApproaching = target.relativeVelocityMPS > 0
            if var record = trackedVehicles[target.id] {
                record.lastSeenAt = now
                record.sampleCount += 1
                if isApproaching {
                    record.positiveSampleCount += 1
                    record.positiveSampleSum += target.relativeVelocityMPS
                }
                record.minimumRangeMetres = min(record.minimumRangeMetres, target.rangeMetres)
                record.lastKnownCoordinate = riderCoordinate
                record.lastRiderSpeedMPS = riderSpeedMPS
                record.lastAlertLevel = alertLevel
                trackedVehicles[target.id] = record
            } else {
                trackedVehicles[target.id] = VehicleTrackingRecord(
                    firstSeenAt: now,
                    lastSeenAt: now,
                    sampleCount: 1,
                    positiveSampleCount: isApproaching ? 1 : 0,
                    positiveSampleSum: isApproaching ? target.relativeVelocityMPS : 0,
                    minimumRangeMetres: target.rangeMetres,
                    lastKnownCoordinate: riderCoordinate,
                    lastRiderSpeedMPS: riderSpeedMPS,
                    lastAlertLevel: alertLevel
                )
            }
        }

        let currentIDs = Set(targets.map(\.id))
        // Collected up front — removing keys while iterating the dictionary being
        // mutated is undefined behavior.
        let missingIDs = Set(trackedVehicles.keys).subtracting(currentIDs)
        guard !missingIDs.isEmpty else { return [] }

        var events: [VehiclePassEventDTO] = []
        for id in missingIDs {
            guard let record = trackedVehicles[id] else { continue }

            // Inside the grace window — may just be one dropped notification.
            // Leave it tracked untouched; a reappearance resumes its history.
            guard now.timeIntervalSince(record.lastSeenAt) >= disappearanceGracePeriod else { continue }

            trackedVehicles.removeValue(forKey: id)

            let duration = record.lastSeenAt.timeIntervalSince(record.firstSeenAt)
            guard duration >= minimumTrackedDuration else { continue }

            // The overtake criterion (#207). This replaced a majority-positive
            // closing-speed test, which could never reject anything: `parseAlert`
            // decodes closing speed from an *unsigned* wire byte, so
            // `relativeVelocityMPS` is never negative and `positiveSampleCount`
            // always equalled `sampleCount`. Across the 565 target-bearing frames of
            // the 2026-09-06 capture, not one carried even a zero speed byte. Range
            // is what actually separates an overtake from a vehicle that turned off
            // or was lost while still behind.
            guard record.minimumRangeMetres <= Self.passProximityMetres else { continue }

            // No GPS fix yet — rare (ride start already requires a lock, PRD §8.8),
            // mirrors makeTrackPoint(from:)'s identical guard. Silently dropped: a
            // VehiclePassEvent's position isn't optional, so there's nothing valid
            // to persist.
            guard let coordinate = record.lastKnownCoordinate else { continue }

            // The nil branch is PRD §8.7's "omitted if insufficient data" and is not
            // reachable from live hardware — every wire frame carries a positive
            // closing speed, so `positiveSampleCount` is never 0 for a vehicle that
            // was tracked at all. Kept rather than force-unwrapped: nil is a
            // documented, persisted output of this field, and the arithmetic below
            // would divide by zero without it.
            //
            // What this averages is closing speed across the whole track, which
            // understates a genuine pass — the estimator is #208's problem, not this
            // change's.
            let estimatedPassSpeedKph = record.positiveSampleCount == 0
                ? nil
                : (record.positiveSampleSum / Double(record.positiveSampleCount)) * AlertLevel.kphPerMPS

            events.append(VehiclePassEventDTO(
                rideId: rideId,
                timestamp: record.lastSeenAt,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                alertLevelAtPass: record.lastAlertLevel,
                riderSpeedKph: record.lastRiderSpeedMPS * AlertLevel.kphPerMPS,
                estimatedPassSpeedKph: estimatedPassSpeedKph
            ))
        }

        return events
    }
}
