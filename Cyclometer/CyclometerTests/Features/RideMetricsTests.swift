import Testing
import Foundation
@testable import Cyclometer

/// #144 — the Ride Metrics sheet's rows: what each reads, and when it reads "—".
@Suite("Ride Metrics")
struct RideMetricsTests {

    /// 36 km/h now, 28.8 average, 43.2 max; 12.4 km in 1:02:33 moving, 1:05:00 recording.
    private func live(_ unit: UnitSystem) -> RideMetrics {
        RideMetrics(
            speedMPS: 10, averageSpeedMPS: 8, maxSpeedMPS: 12, distanceMeters: 12_400,
            movingSeconds: 3_753, rideSeconds: 3_900, unit: unit
        )
    }

    @Test func metricRows() {
        let metrics = live(.metric)
        #expect(metrics.currentSpeed.shown == "36.0 km/h")
        #expect(metrics.averageSpeed.shown == "28.8 km/h")
        #expect(metrics.maxSpeed.shown == "43.2 km/h")
        #expect(metrics.currentPace.shown == "1:40 /km")
        #expect(metrics.averagePace.shown == "2:05 /km")
        #expect(metrics.distance.shown == "12.4 km")
        #expect(metrics.movingTime.shown == "1:02:33")
        #expect(metrics.rideTime.shown == "1:05:00")
    }

    /// VoiceOver reads units and times in words, as the widgets do (#361).
    @Test func rowsSpeakInWords() {
        let metrics = live(.metric)
        #expect(metrics.currentSpeed.spoken == "36.0 kilometers per hour")
        #expect(metrics.currentPace.spoken == "1 minute, 40 seconds per kilometer")
        #expect(metrics.distance.spoken == "12.4 kilometers")
        #expect(metrics.movingTime.spoken == "1 hour, 2 minutes, 33 seconds")
        #expect(RideMetrics().currentSpeed == .missing)
        #expect(MetricReading.missing.spoken == "No reading")
    }

    @Test func imperialRows() {
        let metrics = live(.imperial)
        #expect(metrics.currentSpeed.shown == "22.4 mph")
        #expect(metrics.averageSpeed.shown == "17.9 mph")
        #expect(metrics.maxSpeed.shown == "26.8 mph")
        #expect(metrics.currentPace.shown == "2:40 /mi")
        #expect(metrics.averagePace.shown == "3:21 /mi")
        #expect(metrics.distance.shown == "7.7 mi")
    }

    /// Before a source or a moving second, every speed and pace reads "—". Distance and the two
    /// times are real at zero, as W3 and W6 show them.
    @Test func noDataReadsADashOnlyWhereThereIsNoSource() {
        let metrics = RideMetrics()
        #expect(metrics.currentSpeed.shown == "—")
        #expect(metrics.averageSpeed.shown == "—")
        #expect(metrics.maxSpeed.shown == "—")
        #expect(metrics.currentPace.shown == "—")
        #expect(metrics.averagePace.shown == "—")
        #expect(metrics.distance.shown == "0.0 km")
        #expect(metrics.movingTime.shown == "00:00")
        #expect(metrics.rideTime.shown == "00:00")
    }

    /// Stopped with a source: a stationary phone's GPS still reads a few cm/s (#262). That is a
    /// speed to show, but no pace — not the 500-odd minutes per km it works out to.
    @Test func stoppedHasASpeedButNoPace() {
        var metrics = live(.metric)
        metrics.speedMPS = 0.03
        #expect(metrics.currentSpeed.shown == "0.1 km/h")
        #expect(metrics.currentPace.shown == "—")
        #expect(metrics.averagePace.shown == "2:05 /km")
    }

    /// Each row reads the field its widget does: Moving Time is W3's `speedSampleCount`, Ride Time
    /// W1's `elapsedSeconds`, and the average is W2's distance over moving time. The charts read the
    /// speed watermark's history and the altitude history.
    @Test func stateMapsEachRowToItsWidgetsField() {
        let speedHistory = [SpeedSample(time: at(0), mps: 8), SpeedSample(time: at(1), mps: 9)]
        let altitudeHistory = [AltitudeSample(time: at(0), meters: 120)]
        var state = ActiveRideFeature.State()
        state.speed.speedMPS = 9
        state.speed.speedSamples = speedHistory
        state.altitudeSamples = altitudeHistory
        state.maxSpeedMPS = 12
        state.distanceMeters = 1_000
        state.speedSampleCount = 100
        state.elapsedSeconds = 130

        let metrics = state.rideMetrics
        #expect(metrics == RideMetrics(
            speedMPS: 9, averageSpeedMPS: 10, maxSpeedMPS: 12, distanceMeters: 1_000,
            movingSeconds: 100, rideSeconds: 130, unit: state.unitSystem,
            speedHistory: speedHistory, altitudeHistory: altitudeHistory
        ))
    }

    /// The Time donut's split: stopped is what Ride Time holds beyond Moving Time, never negative.
    @Test func stoppedIsRideTimeBeyondMovingTime() {
        #expect(RideMetrics(movingSeconds: 100, rideSeconds: 130).stoppedSeconds == 30)
        #expect(RideMetrics(movingSeconds: 100, rideSeconds: 90).stoppedSeconds == 0)
    }

    // MARK: - Time axis

    private let chicago = TimeZone(identifier: "America/Chicago")!

    /// A minute into a ride, automatic ticks every 15 s all read the same "6:39 PM". Ticks keep to
    /// whole minutes, so no two labels repeat.
    @Test func timeTicksNeverRepeatAMinute() {
        let start = Date(timeIntervalSince1970: 1_000_000)   // 07:46:40 in Chicago
        let ticks = RideMetricsCharts.timeTicks(in: start...start.addingTimeInterval(70), timeZone: chicago)
        #expect(ticks == [Date(timeIntervalSince1970: 1_000_020)])   // 07:47:00
    }

    /// Under a minute that crosses no whole minute — the history restarts when the app does —
    /// the axis still gets a label, at the start.
    @Test func timeTicksLabelAShortSpanAtItsStart() {
        let start = Date(timeIntervalSince1970: 1_000_000)   // 07:46:40
        let ticks = RideMetricsCharts.timeTicks(in: start...start.addingTimeInterval(15), timeZone: chicago)
        #expect(ticks == [start])
    }

    /// An hour's window ticks on the smallest step that keeps it to three — 30 minutes, as 20
    /// would tick four times on a window starting at :00 — at whole multiples in local time.
    @Test func timeTicksAreAtMostThreeOnWholeSteps() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let ticks = RideMetricsCharts.timeTicks(in: start...start.addingTimeInterval(3_600), timeZone: chicago)
        let minutes = ticks.map { Calendar.current.dateComponents(in: chicago, from: $0).minute }
        #expect(minutes == [0, 30])
    }

    /// A span of exactly three steps that starts on one: still three ticks, not four.
    @Test func timeTicksStayAtThreeWhenTheSpanStartsOnAStep() {
        let start = Date(timeIntervalSince1970: 1_000_020)   // 07:47:00 in Chicago
        let ticks = RideMetricsCharts.timeTicks(in: start...start.addingTimeInterval(180), timeZone: chicago)
        #expect(ticks.count <= 3)
    }

    // MARK: - Pace trace

    private func at(_ second: Int) -> Date { Date(timeIntervalSince1970: 1_000_000 + Double(second)) }

    private func samples(_ mps: [Double]) -> [SpeedSample] {
        mps.enumerated().map { SpeedSample(time: at($0.offset), mps: $0.element) }
    }

    /// A stop is a gap between runs — at a standstill pace is infinite, so there's nothing to plot.
    @Test func paceTraceBreaksAtAStop() {
        let runs = PaceTrace.runs(samples([5, 6, 0, 0, 7]), resolution: 10)
        #expect(runs.map { $0.map(\.mps) } == [[5, 6], [7]])
    }

    /// A bucket's pace comes from its moving samples alone: a stationary reading would drag the
    /// mean speed down and spike the pace at every stop's edges.
    @Test func paceTraceAveragesOnlyMovingSamples() {
        let belowThreshold = ActiveRideFeature.stationarySpeedMPS / 2
        let runs = PaceTrace.runs(samples([4, belowThreshold, 6, 8]), resolution: 2)
        #expect(runs.map { $0.map(\.mps) } == [[4, 7]])
        #expect(runs[0][0].time == at(0))
    }

    /// Riding at 7 m/s (2:22.9 /km) with one bucket rolling up to a light at 0.8 m/s (20:50 /km):
    /// the axis stops at twice the median pace, so the riding pace fills the chart, on whole
    /// minutes.
    @Test func paceAxisIgnoresASlowOutlier() throws {
        let run = samples(Array(repeating: 7, count: 20) + [0.8])
        let axis = try #require(PaceTrace.axis([run], unit: .metric))
        #expect(axis.domain == 120...300)
        #expect(axis.ticks == [120, 180, 240, 300])
    }

    /// A steady pace still gets an axis one step tall, not a zero-height one.
    @Test func paceAxisAtASteadyPaceIsOneStepTall() throws {
        let axis = try #require(PaceTrace.axis([samples([10, 10])], unit: .metric))   // 1:40 /km
        #expect(axis.domain == 90...105)
        #expect(PaceTrace.axis([], unit: .metric) == nil)
    }

    @Test func paceTracePlotsAtMostItsResolution() {
        let hour = samples(Array(repeating: 6, count: 3_600))
        let runs = PaceTrace.runs(hour, resolution: 120)
        #expect(runs.count == 1)
        #expect(runs[0].count == 120)
        #expect(PaceTrace.runs([], resolution: 120).isEmpty)
    }
}
