import Foundation

/// The dashboard's chart series for a resumed ride, from its saved track: the watermarks W1, W2, W4,
/// W5 and W17/W18 plot over one shared window (`ActiveRideFeature.State.watermarkWindow`), and W2's
/// average line. All live in memory only, so without this a kill leaves the charts drawing just the
/// minutes since the relaunch (2026-11-03 ride). They are seeded together because the window starts
/// at the oldest sample of any of them: one series seeded alone would stretch the window back past
/// the others and crowd their traces against its right edge.
struct WatermarkSeed: Equatable, Sendable {
    var speed: [SpeedSample]
    var averageSpeed: [SpeedSample]
    var cadence: [CadenceSample]
    var heartRate: [HeartRateSample]
    var altitude: [AltitudeSample]

    /// Nil when no saved point from before the resume carries a reading. Only those points count:
    /// any flushed since the resume are already in the live series.
    ///
    /// Each series keeps what its live counterpart would have: speed and cadence every reading,
    /// zeros included; heart rate only above zero, as `ActiveRideFeature` samples it; altitude every
    /// recorded second that had one. The average is replayed through the tick's rule — a point above
    /// `stationarySpeedMPS` adds its speed to the distance and one moving second, and samples
    /// distance over moving seconds — from the ride's first point, so a sample means what it did on
    /// the ride. The track records the speed the tick integrated, so the replay ends where the
    /// restored Avg speed does, give or take a tick that had no fix to record. Every series keeps
    /// only the last history window before the resume, the window the live ones are trimmed to.
    init?(savedTrack points: [TrackPointDTO], resumedAt: Date) {
        self.init(points, before: resumedAt, isWindowed: true)
    }

    /// The same series over a finished ride's whole track, unwindowed: S15's metric sections
    /// (#536). Nil when no point carries a reading.
    init?(wholeRide points: [TrackPointDTO]) {
        self.init(points, before: .distantFuture, isWindowed: false)
    }

    private init?(_ points: [TrackPointDTO], before resumedAt: Date, isWindowed: Bool) {
        func isInWindow(_ point: TrackPointDTO, _ window: TimeInterval) -> Bool {
            !isWindowed || point.timestamp >= resumedAt.addingTimeInterval(-window)
        }
        var speed: [SpeedSample] = []
        var averageSpeed: [SpeedSample] = []
        var cadence: [CadenceSample] = []
        var heartRate: [HeartRateSample] = []
        var altitude: [AltitudeSample] = []
        var distanceMeters = 0.0
        var movingSeconds = 0
        for point in points where point.timestamp < resumedAt {
            let time = point.timestamp
            if let speedMPS = point.speedMPS {
                let isRecent = isInWindow(point, SpeedFeature.historyWindow)
                if isRecent { speed.append(SpeedSample(time: time, mps: speedMPS)) }
                if speedMPS > ActiveRideFeature.stationarySpeedMPS {
                    distanceMeters += speedMPS
                    movingSeconds += 1
                    if isRecent {
                        averageSpeed.append(SpeedSample(time: time, mps: distanceMeters / Double(movingSeconds)))
                    }
                }
            }
            if let rpm = point.cadenceRPM, isInWindow(point, CadenceFeature.historyWindow) {
                cadence.append(CadenceSample(time: time, rpm: Double(rpm)))
            }
            if let bpm = point.heartRateBPM, bpm > 0, isInWindow(point, CadenceFeature.historyWindow) {
                heartRate.append(HeartRateSample(time: time, bpm: bpm))
            }
            if let meters = point.altitudeMeters, isInWindow(point, ActiveRideFeature.altitudeHistoryWindow) {
                altitude.append(AltitudeSample(time: time, meters: meters))
            }
        }
        guard !(speed.isEmpty && cadence.isEmpty && heartRate.isEmpty && altitude.isEmpty) else { return nil }
        self.speed = speed
        self.averageSpeed = averageSpeed
        self.cadence = cadence
        self.heartRate = heartRate
        self.altitude = altitude
    }
}
