import Testing
import Foundation
@testable import Cyclometer

@Suite("AppPreferences — paired sensor lookup")
struct AppPreferencesTests {

    private static let comboID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private static let cadenceID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!

    @Test("Each role resolves to the sensor holding it")
    func lookupPerRole() {
        var preferences = AppPreferences()
        preferences.pairedSensors = [
            PairedSensor(peripheralID: Self.comboID, role: .speed, displayName: "Wahoo RPM"),
            PairedSensor(peripheralID: Self.cadenceID, role: .cadence, displayName: "GSC-10")
        ]

        #expect(preferences.pairedSensor(for: .speed)?.peripheralID == Self.comboID)
        #expect(preferences.pairedSensor(for: .cadence)?.peripheralID == Self.cadenceID)
    }

    @Test("An unpaired role resolves to nil")
    func lookupMissingRole() {
        var preferences = AppPreferences()
        preferences.pairedSensors = [
            PairedSensor(peripheralID: Self.comboID, role: .speed, displayName: "Wahoo RPM")
        ]

        #expect(preferences.pairedSensor(for: .cadence) == nil)
    }

    /// A combo device assigned Both is two records sharing one peripheral — the shape
    /// DataModel.md §3.7 specifies, and what makes role-keyed lookup work unchanged.
    @Test("A combo sensor fills both roles from two records")
    func comboSensorAtTwoRoles() {
        var preferences = AppPreferences()
        preferences.pairedSensors = [
            PairedSensor(peripheralID: Self.comboID, role: .speed, displayName: "Wahoo RPM"),
            PairedSensor(peripheralID: Self.comboID, role: .cadence, displayName: "Wahoo RPM")
        ]

        #expect(preferences.pairedSensor(for: .speed)?.peripheralID == Self.comboID)
        #expect(preferences.pairedSensor(for: .cadence)?.peripheralID == Self.comboID)
        // One peripheral, two roles — not two connections.
        #expect(preferences.sensorAssignments == [Self.comboID: [.speed, .cadence]])
    }

    @Test("Assignments group by peripheral")
    func assignmentsGroupByPeripheral() {
        var preferences = AppPreferences()
        preferences.pairedSensors = [
            PairedSensor(peripheralID: Self.comboID, role: .speed, displayName: "Wahoo RPM"),
            PairedSensor(peripheralID: Self.cadenceID, role: .cadence, displayName: "GSC-10")
        ]

        #expect(preferences.sensorAssignments == [
            Self.comboID: [.speed],
            Self.cadenceID: [.cadence]
        ])
    }

    @Test("No pairings means nothing to connect")
    func emptyAssignments() {
        #expect(AppPreferences().sensorAssignments.isEmpty)
        #expect(AppPreferences().pairedSensor(for: .speed) == nil)
    }

    @Test("Preferences round-trip through JSON")
    func jsonRoundTrip() throws {
        var preferences = AppPreferences()
        preferences.wheelCircumferenceMM = 2155
        preferences.pairedSensors = [
            PairedSensor(peripheralID: Self.comboID, role: .speed, displayName: "Wahoo RPM"),
            PairedSensor(peripheralID: Self.cadenceID, role: .cadence, displayName: nil)
        ]

        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(AppPreferences.self, from: data) == preferences)
    }

    /// An `app-preferences.json` written before #67 has no `pairedSensors` key.
    /// Decoding must fall back to the property default rather than throw, otherwise
    /// an upgrading rider loses their wheel circumference too (DataModel.md §9).
    @Test("A document written before pairings existed still decodes")
    func decodesDocumentWithoutPairedSensors() throws {
        let legacy = Data(#"{"wheelCircumferenceMM":2136}"#.utf8)

        let decoded = try JSONDecoder().decode(AppPreferences.self, from: legacy)

        #expect(decoded.wheelCircumferenceMM == 2136)
        #expect(decoded.pairedSensors.isEmpty)
    }

    /// The raw values are what land in the file, so renaming a case silently orphans
    /// every record that used it.
    @Test("Role raw values are stable", arguments: [
        (BLECSCClient.SensorRole.speed, "speed"),
        (BLECSCClient.SensorRole.cadence, "cadence")
    ])
    func roleRawValues(role: BLECSCClient.SensorRole, raw: String) {
        #expect(role.rawValue == raw)
    }
}
