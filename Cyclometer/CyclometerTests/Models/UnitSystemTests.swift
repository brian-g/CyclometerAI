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
}
