import Foundation

/// Per-vehicle radar tracking history, keyed by `RadarTarget.id` — `VariaRadarClient`
/// keeps that id stable for the same real-world vehicle across ticks (resolved from
/// the wire's own threat id), so it doubles as the join key here with no separate
/// identity scheme needed. TCA.md §4.12.
///
/// Closing-speed samples are folded into running counters rather than kept as an
/// array: majority-positive and the pass-speed estimate only ever need the count and
/// sum of positive samples against the total count, and a vehicle that lingers under
/// the same wire id for a long time (a stuck/phantom radar target) would otherwise
/// grow that array for the rest of the ride.
struct VehicleTrackingRecord: Equatable {
    var firstSeenAt: Date
    /// Updated on every tick the vehicle is present — the basis for both the
    /// tracked-duration check and the disappearance grace period below, since it's
    /// the last moment this vehicle was actually confirmed present.
    var lastSeenAt: Date
    var sampleCount: Int
    var positiveSampleCount: Int
    var positiveSampleSum: Double
    /// Snapshotted from the tick that last saw this vehicle, not the tick that
    /// eventually confirms its disappearance — the rider may have moved, and the
    /// alert level may have changed for an unrelated vehicle, in the time it takes
    /// `disappearanceGracePeriod` to elapse.
    var lastKnownCoordinate: Coordinate?
    var lastRiderSpeedMPS: Double
    var lastAlertLevel: AlertLevel
}

/// Detects a genuine vehicle overtake from radar history, distinguishing it from a
/// vehicle that turned off or slowed before reaching the rider (#172, PRD §8.7 /
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

    /// Updates `trackedVehicles` in place for the current radar tick and returns any
    /// vehicle-pass events confirmed this tick (usually zero or one, but more than
    /// one radar target can legitimately disappear on the same tick).
    ///
    /// Detection criteria: tracked >= `minimumTrackedDuration` continuous seconds,
    /// majority-positive closing speed (approaching) across every sample observed,
    /// then the vehicle is absent from `targets` for >= `disappearanceGracePeriod`.
    /// A vehicle whose velocity history is majority non-positive (turned off /
    /// slowed before reaching the rider) is dropped silently — same for one tracked
    /// less than the minimum duration.
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
            guard record.positiveSampleCount * 2 > record.sampleCount else { continue }

            // No GPS fix yet — rare (ride start already requires a lock, PRD §8.8),
            // mirrors makeTrackPoint(from:)'s identical guard. Silently dropped: a
            // VehiclePassEvent's position isn't optional, so there's nothing valid
            // to persist.
            guard let coordinate = record.lastKnownCoordinate else { continue }

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
