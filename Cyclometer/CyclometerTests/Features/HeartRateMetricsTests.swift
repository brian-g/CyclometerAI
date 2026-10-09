import Testing
import Foundation
@testable import Cyclometer

/// #145 — the Heart Rate sheet's rows: what each reads, and where its zones come from.
@Suite("Heart Rate Metrics")
struct HeartRateMetricsTests {

    @Test func currentReading() {
        let metrics = HeartRateMetrics.sample
        #expect(metrics.current == MetricReading(shown: "156 bpm", spoken: "156 beats per minute"))
        #expect(metrics.currentZone == MetricReading(shown: "Z3 Aerobic", spoken: "Zone 3, Aerobic"))
    }

    /// The widgets' empty states: no source at all reads as such; a source with no reading is "—".
    @Test func emptyStatesMatchTheWidgets() {
        let noSource = HeartRateMetrics()
        #expect(noSource.current.shown == "No HR Source")
        #expect(noSource.currentZone == .missing)

        let silent = HeartRateMetrics(bpm: 0, zone: 0, source: .bleStrap)
        #expect(silent.current == .missing)
        #expect(silent.currentZone == .missing)
    }

    /// S12's names and ranges, against the default profile (resting 60, max 190).
    @Test func zoneRowsUseS12NamesAndRanges() {
        let rows = HeartRateMetrics.sample.zoneRows
        #expect(rows.map(\.name) == [
            "Z1 Recovery/Light", "Z2 Endurance", "Z3 Aerobic", "Z4 Threshold", "Z5 Anaerobic"
        ])
        #expect(rows.map(\.range.shown) == [
            "60–137 bpm", "138–150 bpm", "151–163 bpm", "164–176 bpm", "177–190 bpm"
        ])
        #expect(rows[2].time == MetricReading(shown: "0:11:42", spoken: "11 minutes, 42 seconds"))
        #expect(rows[0].range.spoken == "60 to 137 beats per minute")
    }

    /// Before a recorded second, every zone reads zero and there is no donut to draw.
    @Test func noZoneTimeYet() {
        let metrics = HeartRateMetrics()
        #expect(!metrics.hasZoneTime)
        #expect(metrics.zoneRows.count == 5)
        #expect(metrics.zoneRows.allSatisfy { $0.time.shown == "0:00:00" })
    }

    /// The sheet reads W4/W12's display values, and sorts the tally into the zones S12 and S10
    /// resolve, Health's included.
    @Test func builtFromRideState() {
        var state = ActiveRideFeature.State(recordingState: .active, heartRateBPM: 156, hrZone: 3, isHRPaired: true)
        state.healthZoneCeilingsBPM = [120, 140, 155, 170]
        state.hrSecondsTally.add(point(bpm: 130))
        state.hrSecondsTally.add(point(bpm: 156))
        state.hrSecondsTally.add(point(bpm: 156))

        let metrics = state.heartRateMetrics
        let bounds = HeartRateZone.allCases.map {
            state.riderProfile.bounds(for: $0, healthZoneCeilings: [120, 140, 155, 170])
        }
        #expect(metrics == HeartRateMetrics(
            bpm: 156, zone: 3, source: .bleStrap, zoneBounds: bounds, zoneSeconds: [0, 1, 0, 2, 0]
        ))
    }

    private func point(bpm: Int) -> TrackPointDTO {
        RideSummaryFeatureTests.track(count: 1, heartRate: { _ in bpm })[0]
    }
}
