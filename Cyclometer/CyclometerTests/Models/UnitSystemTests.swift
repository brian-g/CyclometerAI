import Testing
import Foundation
@testable import Cyclometer

@Suite("UnitSystem")
struct UnitSystemTests {

    /// `AppPreferences.preferredUnit` defaults to whatever this mapping returns for the
    /// device locale, so the rows are asserted against named locales rather than
    /// `Locale.current` — otherwise the test would only prove what region the machine
    /// running it is set to.
    ///
    /// Liberia and Myanmar are in here deliberately: they are the two locales that make
    /// the switch a measurement-system test rather than a "US or GB" test.
    @Test("A locale's measurement system picks the unit system", arguments: [
        ("en_US", UnitSystem.imperial),
        ("en_GB", UnitSystem.imperial),
        ("en_LR", UnitSystem.imperial),   // Liberia — ussystem
        ("en_MM", UnitSystem.imperial),   // Myanmar — uksystem
        ("de_DE", UnitSystem.metric),
        ("ja_JP", UnitSystem.metric),
        ("en_AU", UnitSystem.metric),
        ("en_CA", UnitSystem.metric)      // Mixed in practice; ICU reports metric.
    ])
    func unitSystemForLocale(identifier: String, expected: UnitSystem) {
        #expect(UnitSystem(Locale(identifier: identifier)) == expected)
    }

    /// The raw values land in `app-preferences.json`, so renaming a case silently
    /// resets every rider's unit preference to the locale default on next launch.
    @Test("Raw values are stable", arguments: [
        (UnitSystem.metric, "metric"),
        (UnitSystem.imperial, "imperial")
    ])
    func rawValues(unit: UnitSystem, raw: String) {
        #expect(unit.rawValue == raw)
    }

    // MARK: - Pace (#8)

    /// Built on `speed(fromMPS:)` rather than a separate factor (36 km/h ⇒ 100
    /// s/km; 36 km/h ≈ 22.37 mph ⇒ ~160.9 s/mi), so this also guards against
    /// pace and speed ever disagreeing about the conversion.
    @Test("Pace seconds derive from the same conversion as speed", arguments: [
        (UnitSystem.metric, 10.0, 100.0),
        (UnitSystem.imperial, 10.0, 160.9344)
    ])
    func paceSecondsMatchesSpeedConversion(unit: UnitSystem, mps: Double, expectedSeconds: Double) throws {
        let seconds = try #require(unit.paceSeconds(fromMPS: mps))
        #expect(abs(seconds - expectedSeconds) < 0.01)
    }

    /// GPS noise on a stationary phone (#262) is stopped, not a 500-minute pace (#144).
    @Test("Pace is undefined when stopped", arguments: [0.0, -1.0, 0.03, ActiveRideFeature.stationarySpeedMPS])
    func paceSecondsIsNilWhenStopped(mps: Double) {
        #expect(UnitSystem.metric.paceSeconds(fromMPS: mps) == nil)
        #expect(UnitSystem.imperial.paceSeconds(fromMPS: mps) == nil)
    }

    @Test("Pace label pairs the '/' with the distance symbol", arguments: [
        (UnitSystem.metric, "/km"),
        (UnitSystem.imperial, "/mi")
    ])
    func paceLabelMatchesDistanceLabel(unit: UnitSystem, expected: String) {
        #expect(unit.paceLabel == expected)
    }

    // MARK: - Elevation (#194)

    @Test("Elevation is metres or feet, never kilometres or miles", arguments: [
        (UnitSystem.metric, 1_000.0, 1_000.0),
        (UnitSystem.imperial, 1_000.0, 3_280.839_895)
    ])
    func elevationConverts(unit: UnitSystem, meters: Double, expected: Double) {
        // A climb is quoted in the small unit in both systems, which is why this does not go
        // through `lengthUnit`.
        #expect(abs(unit.elevation(fromMeters: meters) - expected) < 0.01)
    }

    @Test("Elevation label is the OS symbol for that unit", arguments: [
        (UnitSystem.metric, "m"),
        (UnitSystem.imperial, "ft")
    ])
    func elevationLabelMatchesUnit(unit: UnitSystem, expected: String) {
        #expect(unit.elevationLabel == expected)
    }

    // MARK: - Turn distance (#200)

    @Test("A turn close in is metres or feet rounded to 10; from 1 km or 0.1 mi, one decimal", arguments: [
        (UnitSystem.metric, 347.0, "350", "m"),
        (UnitSystem.metric, 994.0, "990", "m"),
        (UnitSystem.metric, 996.0, "1.0", "km"),     // rounds to 1,000 m, so it reads in km
        (UnitSystem.metric, 1_234.0, "1.2", "km"),
        (UnitSystem.imperial, 100.0, "330", "ft"),   // 328 ft
        (UnitSystem.imperial, 158.0, "520", "ft"),   // 518 ft
        (UnitSystem.imperial, 162.0, "0.1", "mi"),   // 531 ft rounds to 530, past 528
        (UnitSystem.imperial, 1_000.0, "0.6", "mi")
    ])
    func turnDistanceSwitchesUnitClose(unit: UnitSystem, meters: Double, value: String, symbol: String) {
        let distance = unit.turnDistance(fromMeters: meters)
        #expect(distance.value == value)
        #expect(distance.unit == symbol)
    }

    @Test("A turn distance never reads negative", arguments: UnitSystem.allCases)
    func turnDistanceClampsAtZero(unit: UnitSystem) {
        #expect(unit.turnDistance(fromMeters: -5).value == "0")
    }

    // MARK: - Spoken (#361)

    @Test("A spoken turn distance is the shown one, units in words", arguments: [
        (UnitSystem.metric, 347.0, "350 meters"),
        (UnitSystem.metric, 996.0, "1.0 kilometers"),
        (UnitSystem.imperial, 100.0, "330 feet"),
        (UnitSystem.imperial, 1_000.0, "0.6 miles")
    ])
    func spokenTurnDistanceMatchesShown(unit: UnitSystem, meters: Double, spoken: String) {
        #expect(unit.spokenTurnDistance(fromMeters: meters) == spoken)
    }

    @Test func spokenSpeedAndDistanceSpellOutUnits() {
        #expect(UnitSystem.metric.spokenSpeed(fromMPS: 10) == "36.0 kilometers per hour")
        #expect(UnitSystem.imperial.spokenSpeed(fromMPS: 10) == "22.4 miles per hour")
        #expect(UnitSystem.metric.spokenDistance(fromMeters: 12_400) == "12.4 kilometers")
        #expect(UnitSystem.imperial.spokenDistance(fromMeters: 12_400) == "7.7 miles")
    }

    /// 10 m/s is 100 s/km and 160.9 s/mi: whole seconds, truncated, as W11 has always shown them.
    @Test("Pace reads M:SS, shown and spoken, and is nil where pace is undefined", arguments: [
        (UnitSystem.metric, 10.0, "1:40", "1 minute, 40 seconds per kilometer"),
        (.imperial, 10.0, "2:40", "2 minutes, 40 seconds per mile"),
        (.metric, 1.0, "16:40", "16 minutes, 40 seconds per kilometer"),
    ])
    func paceFormats(unit: UnitSystem, mps: Double, shown: String, spoken: String) {
        #expect(unit.formattedPace(fromMPS: mps) == shown)
        #expect(unit.spokenPace(fromMPS: mps) == spoken)
    }

    @Test("No pace to show or speak at zero speed", arguments: UnitSystem.allCases)
    func paceFormatsAreNilWhenStopped(unit: UnitSystem) {
        #expect(unit.formattedPace(fromMPS: 0) == nil)
        #expect(unit.spokenPace(fromMPS: 0) == nil)
    }
}
