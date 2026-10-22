import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

@Suite("SensorHealth")
struct SensorHealthTests {
    static let rideId = UUID(0)
    static let sensor = UUID(1)
    static let start = Date(timeIntervalSince1970: 1_000_000)

    private func report(_ log: SensorHealthLog) throws -> SensorHealthReport {
        try #require(log.reports(rideId: Self.rideId)[Self.sensor])
    }

    // MARK: Battery

    @Test("The 2026-10-07 speed sensor's battery series reads low (#391)")
    func sagging2026_10_07SeriesIsLow() throws {
        var log = SensorHealthLog()
        // First two minutes of that ride: each link drop clears the reading to nil, and the
        // reconnect re-read lands wherever the cell has sagged or recovered to.
        for level in [87, nil, 10, nil, 95, nil, 0] {
            log.recordBattery(level, peripheral: Self.sensor)
        }
        let report = try report(log)
        #expect(report.minBatteryPercent == 0)
        #expect(report.warning == .batteryLow)
    }

    @Test("A steady 80–87% series is healthy")
    func steadySeriesIsHealthy() throws {
        var log = SensorHealthLog()
        for level in [87, 86, nil, 84, 85, 83, 81, 80, 82] {
            log.recordBattery(level, peripheral: Self.sensor)
        }
        #expect(try report(log).warning == nil)
    }

    @Test("Low is at or below the threshold the battery label tints at", arguments: [
        (SensorHealthReport.lowBatteryPercent, true),
        (SensorHealthReport.lowBatteryPercent + 1, false),
    ])
    func batteryBoundary(level: Int, isLow: Bool) throws {
        var log = SensorHealthLog()
        log.recordBattery(level, peripheral: Self.sensor)
        #expect((try report(log).warning == .batteryLow) == isLow)
    }

    @Test("A nil reading alone reports nothing — the sensor never answered")
    func nilOnlyIsNoReport() {
        var log = SensorHealthLog()
        log.recordBattery(nil, peripheral: Self.sensor)
        #expect(log.reports(rideId: Self.rideId).isEmpty)
    }

    // MARK: Link

    @Test("180 supervision timeouts in 21 minutes reads unreliable (#391)")
    func flapping2026_10_07IsUnreliable() throws {
        var log = SensorHealthLog()
        let interval = 21 * 60.0 / 180   // one drop every 7 s
        for i in 0..<180 {
            log.recordLinkLoss(peripheral: Self.sensor, at: Self.start.addingTimeInterval(Double(i) * interval))
        }
        let report = try report(log)
        #expect(report.maxLinkLossesPerWindow >= 42)
        #expect(report.warning == .linkUnreliable)
    }

    @Test("A single disconnect at ride end is healthy")
    func singleDropIsHealthy() throws {
        var log = SensorHealthLog()
        log.recordBattery(85, peripheral: Self.sensor)
        log.recordLinkLoss(peripheral: Self.sensor, at: Self.start.addingTimeInterval(2 * 3600))
        let report = try report(log)
        #expect(report.maxLinkLossesPerWindow == 1)
        #expect(report.warning == nil)
    }

    @Test("Unreliable takes the threshold's count inside one window", arguments: [
        (SensorHealthReport.unreliableLinkLosses, true),
        (SensorHealthReport.unreliableLinkLosses - 1, false),
    ])
    func linkBoundary(count: Int, isUnreliable: Bool) throws {
        var log = SensorHealthLog()
        let spacing = SensorHealthReport.linkLossWindow / Double(SensorHealthReport.unreliableLinkLosses)
        for i in 0..<count {
            log.recordLinkLoss(peripheral: Self.sensor, at: Self.start.addingTimeInterval(Double(i) * spacing))
        }
        #expect((try report(log).warning == .linkUnreliable) == isUnreliable)
    }

    @Test("Drops spread wider than the window never add up")
    func spreadDropsAreHealthy() throws {
        var log = SensorHealthLog()
        // One every window: a long ride's occasional drop, never a burst.
        for i in 0..<20 {
            log.recordLinkLoss(peripheral: Self.sensor,
                               at: Self.start.addingTimeInterval(Double(i) * SensorHealthReport.linkLossWindow))
        }
        #expect(try report(log).maxLinkLossesPerWindow == 1)
    }

    @Test("A flapping stretch inside a long ride still reads unreliable")
    func burstInsideLongRide() throws {
        var log = SensorHealthLog()
        log.recordLinkLoss(peripheral: Self.sensor, at: Self.start)
        let burst = Self.start.addingTimeInterval(2 * 3600)
        for i in 0..<30 {
            log.recordLinkLoss(peripheral: Self.sensor, at: burst.addingTimeInterval(Double(i) * 10))
        }
        #expect(try report(log).warning == .linkUnreliable)
    }

    // MARK: Both

    @Test("Low battery wins over an unreliable link — it is the more specific cause")
    func batteryWins() throws {
        var log = SensorHealthLog()
        log.recordBattery(5, peripheral: Self.sensor)
        for i in 0..<10 {
            log.recordLinkLoss(peripheral: Self.sensor, at: Self.start.addingTimeInterval(Double(i)))
        }
        #expect(try report(log).warning == .batteryLow)
    }

    @Test("Each peripheral is assessed on its own")
    func perPeripheral() {
        var log = SensorHealthLog()
        let other = UUID(2)
        log.recordBattery(5, peripheral: Self.sensor)
        log.recordBattery(90, peripheral: other)
        let reports = log.reports(rideId: Self.rideId)
        #expect(reports[Self.sensor]?.warning == .batteryLow)
        #expect(reports[other]?.warning == nil)
        #expect(reports[other]?.rideId == Self.rideId)
    }

    // MARK: Persistence

    @Test("Preferences saved before #391 still decode, with no verdicts")
    func legacyPreferencesDecode() throws {
        let legacy = Data(#"{"wheelCircumferenceMM":2105}"#.utf8)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: legacy)
        #expect(decoded.sensorHealth.isEmpty)
        #expect(decoded.wheelCircumferenceMM == 2105)
    }

    @Test("An unreadable verdict is dropped, not a reason to reset every preference")
    func unreadableVerdictKeepsPreferences() throws {
        let corrupt = Data(#"{"wheelCircumferenceMM":2105,"sensorHealth":["not-a-uuid",{"rideId":7}]}"#.utf8)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: corrupt)
        #expect(decoded.sensorHealth.isEmpty)
        #expect(decoded.wheelCircumferenceMM == 2105)
    }

    @Test("Verdicts round-trip through the preferences file")
    func verdictsRoundTrip() throws {
        var preferences = AppPreferences()
        preferences.sensorHealth = [
            Self.sensor: SensorHealthReport(rideId: Self.rideId, minBatteryPercent: 0, maxLinkLossesPerWindow: 43)
        ]
        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(AppPreferences.self, from: data) == preferences)
    }

    @Test("A connection alone yields a healthy verdict")
    func connectedOnlyIsHealthy() throws {
        var log = SensorHealthLog()
        log.recordConnected(peripheral: Self.sensor)
        log.recordConnected(peripheral: Self.sensor)
        let report = try report(log)
        #expect(report.minBatteryPercent == nil)
        #expect(report.warning == nil)
    }
}
