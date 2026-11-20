import Foundation

/// Diagnostics for one calibration window (#419). Nothing in `WheelCalibrationFeature`
/// reads it to decide anything: it rides along so the window's log line can show the
/// numbers needed to tell where a short-measuring window's error comes from.
///
/// #419 found windows measuring ~2% below an independent length. The window's GPS
/// distance is the Doppler integral; this records, over exactly the same accepted
/// intervals, the distance between the fixes' coordinates (positional distance), and it
/// counts the revolutions dropped with the intervals the window left out.
///
/// **Equality-transparent.** `==` is always true, so the probe never shows up in a
/// `TestStore` diff. Every state change the calibration *decides* is still compared
/// field by field. The instrumentation is not part of what those tests pin, and it must
/// not be able to break them. Tests that check the probe read it with `#expect`.
///
/// So it must never drive a view or a decision. `State.==` ignores it, and so does
/// observation: `@ObservableState` skips notifying when old and new compare equal, so
/// assigning a whole new probe (the reset) notifies nobody.
struct CalibrationWindowProbe: Equatable {
    /// Metres between consecutive fixes' coordinates over the accepted intervals:
    /// `RouteGeometry.segmentMeters`, the app's own distance formula.
    private(set) var positionalMeters = 0.0
    /// Intervals whose Doppler distance went into the window.
    private(set) var usedIntervals = 0
    /// Seconds those intervals cover.
    private(set) var integratedSeconds: TimeInterval = 0
    /// Fixes the GPS gate turned away (accuracy, speed or gap), and how many times the
    /// gate went from open to shut.
    private(set) var rejectedFixes = 0
    private(set) var gpsGateShuts = 0
    /// Usable fixes that added nothing, by reason: a re-seed (the first fix after a GPS-gate
    /// shut, after the window reset, or after the sensor or suspension gate reopened, which
    /// only starts the next interval), or a fix that landed while the sensor or suspension
    /// gate was shut.
    private(set) var reseedFixes = 0
    private(set) var fixesSkippedWhileGated = 0
    /// Revolutions counted for an interval the window then left out, split by why it was
    /// left out. They never reach the window (#587): the reducer holds an interval's
    /// revolutions until its closing fix decides whether the interval counts.
    private(set) var droppedRevolutionsAtGPSGate = 0.0
    private(set) var droppedRevolutionsWhileGated = 0.0
    private(set) var droppedRevolutionsAtReseeds = 0.0
    /// Fix times bounding the accepted intervals: the start of the first, the end of the last.
    private(set) var startedAt: Date?
    private(set) var endedAt: Date?

    /// The coordinate of the last fix that landed. Set together with `State.lastFixTimestamp`
    /// and read only while that is non-nil, so the pair it is read with always describes the
    /// same fix. Forgetting the last fix (a GPS-gate shut, a gate reopening) clears only the
    /// timestamp.
    var lastFixCoordinate: Coordinate?

    static func == (lhs: Self, rhs: Self) -> Bool { true }

    /// An interval whose Doppler distance the window just added, from the previous fix
    /// at `previousCoordinate` to `coordinate`.
    mutating func intervalUsed(
        from previousCoordinate: Coordinate, at previousTimestamp: Date,
        to coordinate: Coordinate, at timestamp: Date
    ) {
        positionalMeters += Self.meters(from: previousCoordinate, to: coordinate)
        usedIntervals += 1
        integratedSeconds += timestamp.timeIntervalSince(previousTimestamp)
        if startedAt == nil { startedAt = previousTimestamp }
        endedAt = timestamp
    }

    /// A fix the GPS gate rejected, and the revolutions of the interval it closed.
    /// `gateWasOpen` marks the shut.
    mutating func fixRejected(gateWasOpen: Bool, droppedRevolutions: Double) {
        rejectedFixes += 1
        if gateWasOpen { gpsGateShuts += 1 }
        droppedRevolutionsAtGPSGate += droppedRevolutions
    }

    /// A usable fix that added no distance, and the revolutions of the interval it closed:
    /// a re-seed, or one that landed while the sensor or suspension gate was shut.
    mutating func fixSkipped(isReseed: Bool, droppedRevolutions: Double) {
        if isReseed {
            reseedFixes += 1
            droppedRevolutionsAtReseeds += droppedRevolutions
        } else {
            fixesSkippedWhileGated += 1
            droppedRevolutionsWhileGated += droppedRevolutions
        }
    }

    /// The revolutions of an interval the suspension gate shut partway through, whose
    /// closing fix the GPS gate then rejected. The suspension lost the interval, so they
    /// count as dropped while gated. The fix itself is not tallied: rejected fixes count
    /// only while the suspension gate is open.
    mutating func revolutionsDroppedWhileGated(_ droppedRevolutions: Double) {
        droppedRevolutionsWhileGated += droppedRevolutions
    }

    /// The window's log line, after its existing `calibration window:` line. Numbers only:
    /// no coordinates, so a collected log carries nothing that places the ride.
    ///
    /// Each distance is turned into the circumference it implies with the same arithmetic
    /// as the real measurement, `WheelCalibration.measuredCircumferenceMM`.
    func summary(dopplerMeters: Double, revolutions: Double, storedMM: Int) -> String {
        func f(_ value: Double, _ digits: Int) -> String { String(format: "%.\(digits)f", value) }
        func mm(_ meters: Double, _ revs: Double) -> String {
            WheelCalibration.measuredCircumferenceMM(gpsMeters: meters, revolutions: revs)
                .map { "\(f($0, 0)) mm" } ?? "n/a"
        }
        let ratio = positionalMeters > 0 ? f(dopplerMeters / positionalMeters, 4) : "n/a"
        var span = "n/a"
        if let startedAt, let endedAt { span = "\(f(endedAt.timeIntervalSince(startedAt), 0)) s" }
        return "doppler \(f(dopplerMeters, 1)) m, positional \(f(positionalMeters, 1)) m "
            + "(doppler/positional \(ratio)), \(f(revolutions, 1)) rev → "
            + "doppler \(mm(dopplerMeters, revolutions)), positional \(mm(positionalMeters, revolutions)), "
            + "stored \(storedMM) mm; "
            + "dropped rev \(f(droppedRevolutionsAtGPSGate, 1)) at gps gate "
            + "(\(gpsGateShuts) shuts, \(rejectedFixes) fixes rejected), "
            + "\(f(droppedRevolutionsWhileGated, 1)) while the sensor or suspension gate was shut "
            + "(\(fixesSkippedWhileGated) fixes skipped), "
            + "\(f(droppedRevolutionsAtReseeds, 1)) at re-seeds (\(reseedFixes) re-seed fixes); "
            + "\(usedIntervals) intervals, \(f(integratedSeconds, 1)) s integrated of a \(span) span"
    }

    /// `RouteGeometry.segmentMeters` for two fixes. Altitude is left out, as it is from
    /// the Doppler side.
    static func meters(from start: Coordinate, to end: Coordinate) -> Double {
        RouteGeometry.segmentMeters(
            from: RouteCoordinate(latitude: start.latitude, longitude: start.longitude, elevationMeters: nil),
            to: RouteCoordinate(latitude: end.latitude, longitude: end.longitude, elevationMeters: nil)
        )
    }
}
