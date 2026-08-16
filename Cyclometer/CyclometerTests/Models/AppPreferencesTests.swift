import Testing
import Foundation
@testable import Cyclometer

@Suite("AppPreferences — paired sensor lookup")
struct AppPreferencesTests {

    private static let comboID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private static let cadenceID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    private static let radarID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!
    private static let hrID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D4")!

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
        #expect(preferences.cscAssignments == [Self.comboID: [.speed, .cadence]])
    }

    @Test("Assignments group by peripheral")
    func assignmentsGroupByPeripheral() {
        var preferences = AppPreferences()
        preferences.pairedSensors = [
            PairedSensor(peripheralID: Self.comboID, role: .speed, displayName: "Wahoo RPM"),
            PairedSensor(peripheralID: Self.cadenceID, role: .cadence, displayName: "GSC-10")
        ]

        #expect(preferences.cscAssignments == [
            Self.comboID: [.speed],
            Self.cadenceID: [.cadence]
        ])
    }

    @Test("No pairings means nothing to connect")
    func emptyAssignments() {
        #expect(AppPreferences().cscAssignments.isEmpty)
        #expect(AppPreferences().pairedSensor(for: .speed) == nil)
    }

    @Test("Preferences round-trip through JSON")
    func jsonRoundTrip() throws {
        var preferences = AppPreferences()
        preferences.wheelCircumferenceMM = 2155
        preferences.isAutoDimEnabled = false
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
        // Added by #110, so an older document has no key — auto-dim starts on.
        #expect(decoded.isAutoDimEnabled)
    }

    /// #93 moved `SensorRole` out of `BLECSCClient` and added `.radar` / `.heartRate`.
    /// The `speed` and `cadence` raw values did not change, so a document written
    /// before the move must still decode with its pairings intact (DataModel.md §3.7).
    @Test("A document written before the role enum moved still decodes")
    func decodesDocumentWrittenBeforeRoleMove() throws {
        let legacy = Data(#"""
        {"wheelCircumferenceMM":2096,"pairedSensors":[\#
        {"peripheralID":"00000000-0000-0000-0000-0000000000A1",\#
        "role":"speed","displayName":"Wahoo RPM"},\#
        {"peripheralID":"00000000-0000-0000-0000-0000000000A1",\#
        "role":"cadence","displayName":"Wahoo RPM"}]}
        """#.utf8)

        let decoded = try JSONDecoder().decode(AppPreferences.self, from: legacy)

        #expect(decoded.pairedSensor(for: .speed)?.peripheralID == Self.comboID)
        #expect(decoded.pairedSensor(for: .cadence)?.displayName == "Wahoo RPM")
        #expect(decoded.cscAssignments == [Self.comboID: [.speed, .cadence]])
    }

    /// The CSC client is told what to reconnect via this map, and it only speaks
    /// 0x1816 — a radar or HR peripheral reaching it would have it chase a service the
    /// device does not advertise (#93).
    @Test("Radar and heart rate records stay out of the CSC assignments")
    func cscAssignmentsExcludeNonCSCRoles() {
        var preferences = AppPreferences()
        preferences.pairedSensors = [
            PairedSensor(peripheralID: Self.radarID, role: .radar, displayName: "RTL515"),
            PairedSensor(peripheralID: Self.hrID, role: .heartRate, displayName: "HRM-Dual"),
            PairedSensor(peripheralID: Self.comboID, role: .speed, displayName: "Wahoo RPM")
        ]

        #expect(preferences.cscAssignments == [Self.comboID: [.speed]])
        // Still reachable by role — the filter is about who gets connected, not what
        // is persisted.
        #expect(preferences.pairedSensor(for: .radar)?.peripheralID == Self.radarID)
    }

    /// The raw values are what land in the file, so renaming a case silently orphans
    /// every record that used it.
    @Test("Role raw values are stable", arguments: [
        (SensorRole.radar, "radar"),
        (SensorRole.heartRate, "heartRate"),
        (SensorRole.speed, "speed"),
        (SensorRole.cadence, "cadence")
    ])
    func roleRawValues(role: SensorRole, raw: String) {
        #expect(role.rawValue == raw)
    }

    /// `roleRawValues` hardcodes its rows, so a case added without one would go
    /// unpinned. This is the test that fails when that happens. It also pins
    /// declaration order, which `allCases` exposes to the S11 row subtitle and to the
    /// order records are written in (`DeviceManagementFeature.apply`).
    @Test("Every role is pinned, in DataModel §3.7 order")
    func roleCasesAreExhaustive() {
        #expect(SensorRole.allCases.map(\.rawValue) == ["radar", "heartRate", "speed", "cadence"])
        // `power` is reserved for Phase 3 but not declared — see SensorRole's doc.
        #expect(!SensorRole.allCases.contains { $0.rawValue == "power" })
    }
}
