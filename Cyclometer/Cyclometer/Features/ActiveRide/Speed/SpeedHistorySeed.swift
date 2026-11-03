import Foundation

/// W2's two series for a resumed ride, from its saved track: the speed watermark
/// (`SpeedFeature.State.speedSamples`) and the average line (`ActiveRideFeature.State.averageSpeedSamples`).
/// Both live in memory only, so without this a kill leaves W2 drawing just the minutes since the
/// relaunch (2026-11-03 ride).
struct SpeedHistorySeed: Equatable, Sendable {
    var speed: [SpeedSample]
    var average: [SpeedSample]

    /// Nil when no saved point from before the resume carries a speed. Only those points count:
    /// any flushed since the resume are already in the live series.
    ///
    /// The average is replayed through the tick's rule — a point above `stationarySpeedMPS` adds its
    /// speed to the distance and one moving second, and samples distance over moving seconds — from
    /// the ride's first point, so a sample means what it did on the ride. The track records the
    /// speed the tick integrated, so the replay ends where the restored Avg speed does, give or
    /// take a tick that had no fix to record. Both series keep only the last
    /// `SpeedFeature.historyWindow` before the resume, the window the live ones are trimmed to.
    init?(savedTrack points: [TrackPointDTO], resumedAt: Date) {
        let windowStart = resumedAt.addingTimeInterval(-SpeedFeature.historyWindow)
        var speed: [SpeedSample] = []
        var average: [SpeedSample] = []
        var distanceMeters = 0.0
        var movingSeconds = 0
        for point in points where point.timestamp < resumedAt {
            guard let speedMPS = point.speedMPS else { continue }
            let isInWindow = point.timestamp >= windowStart
            if isInWindow { speed.append(SpeedSample(time: point.timestamp, mps: speedMPS)) }
            guard speedMPS > ActiveRideFeature.stationarySpeedMPS else { continue }
            distanceMeters += speedMPS
            movingSeconds += 1
            if isInWindow {
                average.append(SpeedSample(time: point.timestamp, mps: distanceMeters / Double(movingSeconds)))
            }
        }
        guard !speed.isEmpty else { return nil }
        self.speed = speed
        self.average = average
    }
}
