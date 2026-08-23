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

    @Test("Pace is undefined at zero or negative speed", arguments: [0.0, -1.0])
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
}
