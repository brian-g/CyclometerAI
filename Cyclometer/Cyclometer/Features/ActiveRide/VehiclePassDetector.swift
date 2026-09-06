import Foundation

/// Per-vehicle radar tracking history, keyed by `RadarTarget.id` — `VariaRadarClient`
/// keeps that id stable for the same real-world vehicle across ticks (resolved from
/// the wire's own threat id), so it doubles as the join key here with no separate
/// identity scheme needed. TCA.md §4.12.
///
/// Closing-speed samples are folded into a running maximum rather than kept as an
/// array: the pass-speed estimate only ever needs the peak positive sample, and a
/// vehicle that lingers under the same wire id for a long time (a stuck/phantom radar
/// target) would otherwise grow that array for the rest of the ride.
/// `minimumRangeMetres` is folded the same way and for the same reason.
struct VehicleTrackingRecord: Equatable {
    var firstSeenAt: Date
    /// Updated on every tick the vehicle is present — the basis for both the
    /// tracked-duration check and the disappearance grace period below, since it's
    /// the last moment this vehicle was actually confirmed present.
    var lastSeenAt: Date
    var sampleCount: Int
    /// Fastest this vehicle was ever seen closing, in m/s — the basis of the
    /// pass-speed estimate (#208). Never negative: both the seed and the fold clamp
    /// at 0, so `0` means "never once observed approaching", which is exactly the
    /// condition under which `estimatedPassSpeedKph` is omitted.
    ///
    /// The peak rather than an average over the track. Radar measures the *radial*
    /// component of the closing speed, which decays by cos(theta) as a vehicle draws
    /// alongside, so a whole-track mean is dragged down by the tail near the rider —
    /// by 13–27 km/h across the four overtakes captured on 2026-09-06. The peak lands
    /// while the vehicle is still lined up behind the rider (frame 0 of all five of
    /// those tracks, at 87–135 m), where theta is near zero and the radial component
    /// is the true speed difference.
    ///
    /// A running max is in principle more exposed than a mean to one spurious sample
    /// from a stuck/phantom target, since a mean dilutes toward recent values and a
    /// max does not. #207's proximity guard bounds that: a phantom that never comes
    /// within `VehiclePassDetector.passProximityMetres` is dropped before it ever
    /// reaches the estimator.
    var maxPositiveClosingMPS: Double
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
            if var record = trackedVehicles[target.id] {
                record.lastSeenAt = now
                record.sampleCount += 1
                record.maxPositiveClosingMPS = max(record.maxPositiveClosingMPS, target.relativeVelocityMPS)
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
                    // Clamped, like the fold above: hardware cannot report a negative
                    // closing speed, but `RadarTarget` can be constructed with one, and
                    // an unclamped seed would leave the "peak" negative for the track.
                    maxPositiveClosingMPS: max(target.relativeVelocityMPS, 0),
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
            // `relativeVelocityMPS` is never negative and every sample counted as
            // approaching. Across the 565 target-bearing frames of the 2026-09-06
            // capture, not one carried even a zero speed byte. Range is what actually
            // separates an overtake from a vehicle that turned off or was lost while
            // still behind.
            guard record.minimumRangeMetres <= Self.passProximityMetres else { continue }

            // No GPS fix yet — rare (ride start already requires a lock, PRD §8.8),
            // mirrors makeTrackPoint(from:)'s identical guard. Silently dropped: a
            // VehiclePassEvent's position isn't optional, so there's nothing valid
            // to persist.
            guard let coordinate = record.lastKnownCoordinate else { continue }

            // PRD §8.7: this field carries the *vehicle's* ground speed, not the
            // closing speed the radar reports. The Varia measures speed relative to
            // the rider, so the rider's own speed has to be added back to get an
            // absolute figure — exported beside `riderSpeedKph`, a relative one would
            // read as the car being slower than the bike it just overtook (#208).
            //
            // The two terms are not simultaneous, and the PRD says so: the peak lands
            // at acquisition (87–135 m out in every 2026-09-06 capture) while the
            // rider term is the speed at the pass, up to 22 s later. That is the
            // vehicle's speed *on approach* — a car that slows behind the rider before
            // committing is described by how fast it came up, not how fast it went by.
            // Rider drift over that window is a few km/h against the 13–27 km/h
            // geometric bias this replaced, and pairing the two exported fields from
            // the same instant is what lets a consumer recover the raw closing speed
            // by subtracting them.
            //
            // Converted to km/h in a single multiply so a whole-m/s test input lands
            // on an exact decimal: (6 + 8) * 3.6 == 50.4, where two separate
            // conversions would not.
            //
            // The nil branch is PRD §8.7's "omitted if insufficient data" and is not
            // reachable from live hardware — every wire frame carries a positive
            // closing speed, so a vehicle tracked at all has a positive peak. Kept
            // rather than force-unwrapped: nil is a documented, persisted output.
            let estimatedPassSpeedKph = record.maxPositiveClosingMPS > 0
                ? (record.lastRiderSpeedMPS + record.maxPositiveClosingMPS) * AlertLevel.kphPerMPS
                : nil

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
