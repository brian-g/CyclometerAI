import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

@MainActor
@Suite("SettingsFeature")
struct SettingsFeatureTests {

    /// Collects every circumference pushed to the CSC client, so tests can assert
    /// the stored value and the value driving the speed derivation stay in step.
    private func makeSpyClient(
        applied: LockIsolated<[Int]>
    ) -> BLECSCClient {
        var client = BLECSCClient.testValue
        client.setWheelCircumference = { mm in applied.withValue { $0.append(mm) } }
        return client
    }

    /// Each store gets its own in-memory file system (`.inMemory` builds a fresh
    /// one per access), so the persisted circumference cannot leak between tests
    /// when the suite runs repeatedly or in parallel. Seeding happens inside the
    /// same scope, otherwise the seed and the store would read different storage.
    private func makeStore(
        circumferenceMM: Int = WheelPreset.default.circumferenceMM,
        riderProfile: RiderProfile = RiderProfile(),
        bleCSCClient: BLECSCClient = .testValue,
        healthKitClient: HealthKitClient = .testValue
    ) -> TestStoreOf<SettingsFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.wheelCircumferenceMM = circumferenceMM }
            @Shared(.riderProfile) var profile
            $profile.withLock { $0 = riderProfile }
            return TestStore(initialState: SettingsFeature.State()) {
                SettingsFeature()
            } withDependencies: {
                $0.bleCSCClient = bleCSCClient
                $0.healthKitClient = healthKitClient
                $0.date = .constant(Date(timeIntervalSince1970: 1_800_000_000))
                $0.defaultFileStorage = storage
            }
        }
    }

    @Test("Selecting a preset persists its circumference and pushes it to the CSC client")
    func presetSelectionPersistsAndPushes() async {
        let applied = LockIsolated<[Int]>([])
        let store = makeStore(bleCSCClient: makeSpyClient(applied: applied))

        await store.send(.wheelSelectionChanged(.preset(.c700x32))) {
            $0.$preferences.withLock { $0.wheelCircumferenceMM = 2155 }
        }
        await store.finish()

        #expect(applied.value == [2155])
        #expect(store.state.wheelSelection == .preset(.c700x32))
        // No draft in flight, so the field falls back to the persisted value.
        #expect(store.state.customCircumferenceText == "2155")
    }

    @Test("Manual entry inside the sanity bounds is applied and pushed")
    func customEntryWithinBoundsIsApplied() async {
        let applied = LockIsolated<[Int]>([])
        let store = makeStore(bleCSCClient: makeSpyClient(applied: applied))

        await store.send(.wheelSelectionChanged(.custom)) {
            $0.userChoseCustom = true
        }
        // The field shows the persisted value with no draft and no lifecycle action.
        #expect(store.state.customCircumferenceText == "2096")

        await store.send(.customCircumferenceChanged("2140")) {
            $0.customCircumferenceDraft = "2140"
        }
        await store.send(.customCircumferenceCommitted) {
            $0.$preferences.withLock { $0.wheelCircumferenceMM = 2140 }
            $0.customCircumferenceDraft = nil
        }
        await store.finish()

        #expect(applied.value == [2140])
    }

    @Test("Manual entry outside 1,500–3,000 mm is rejected and reverts", arguments: ["1200", "3100", "abc"])
    func customEntryOutOfBoundsIsRejected(_ entry: String) async {
        let applied = LockIsolated<[Int]>([])
        let store = makeStore(bleCSCClient: makeSpyClient(applied: applied))

        await store.send(.wheelSelectionChanged(.custom)) {
            $0.userChoseCustom = true
        }
        await store.send(.customCircumferenceChanged(entry)) {
            $0.customCircumferenceDraft = entry
        }
        #expect(store.state.isCustomCircumferenceInvalid)

        await store.send(.customCircumferenceCommitted) {
            $0.customCircumferenceDraft = nil
        }
        await store.finish()

        #expect(store.state.preferences.wheelCircumferenceMM == 2096)
        #expect(store.state.customCircumferenceText == "2096")
        #expect(applied.value.isEmpty)
    }

    /// Picking a preset while the manual field has focus tears the field down,
    /// which fires a commit for the value the preset just wrote.
    @Test("Committing an unchanged value does not push to the CSC client again")
    func commitOfUnchangedValueIsNoop() async {
        let applied = LockIsolated<[Int]>([])
        let store = makeStore(bleCSCClient: makeSpyClient(applied: applied))

        await store.send(.wheelSelectionChanged(.preset(.c700x28))) {
            $0.$preferences.withLock { $0.wheelCircumferenceMM = 2136 }
        }
        await store.send(.customCircumferenceCommitted)
        await store.finish()

        #expect(applied.value == [2136])
    }

    /// The manual field is populated on a cold launch with no lifecycle action:
    /// with no draft in flight it reads straight through to the persisted value.
    @Test("A persisted non-preset circumference reads as Custom and populates the field")
    func nonPresetValueResolvesToCustom() {
        let store = makeStore(circumferenceMM: 2140)

        #expect(store.state.wheelSelection == .custom)
        #expect(store.state.userChoseCustom == false)
        #expect(store.state.customCircumferenceText == "2140")
        #expect(store.state.isCustomCircumferenceInvalid == false)
    }

    @Test("A persisted preset circumference selects that preset on a cold launch")
    func presetValueResolvesToPreset() {
        let store = makeStore()

        #expect(store.state.wheelSelection == .preset(.c700x23))
        #expect(store.state.customCircumferenceText == "2096")
    }

    /// The toggle writes through to storage rather than to feature state, because
    /// `AppFeature` reads the same document to decide whether to run the auto-dim
    /// countdown (#110) — and because it has to survive a relaunch.
    @Test("Auto-dim toggles persist rather than living in feature state")
    func autoDimTogglePersists() async {
        let store = makeStore()
        #expect(store.state.isAutoDimEnabled)

        await store.send(.autoDimToggled) {
            $0.$preferences.withLock { $0.isAutoDimEnabled = false }
        }
        #expect(store.state.isAutoDimEnabled == false)

        await store.send(.autoDimToggled) {
            $0.$preferences.withLock { $0.isAutoDimEnabled = true }
        }
        #expect(store.state.isAutoDimEnabled)
    }

    /// Auto-pause used to be a feature-local `Bool` nobody else could read; #102
    /// moves it through the same document `ActiveRideFeature` consults.
    @Test("Auto-pause toggles persist rather than living in feature state")
    func autoPauseTogglePersists() async {
        let store = makeStore()
        #expect(store.state.isAutoPauseEnabled)

        await store.send(.autoPauseToggled) {
            $0.$preferences.withLock { $0.isAutoPauseEnabled = false }
        }
        #expect(store.state.isAutoPauseEnabled == false)

        await store.send(.autoPauseToggled) {
            $0.$preferences.withLock { $0.isAutoPauseEnabled = true }
        }
        #expect(store.state.isAutoPauseEnabled)
    }

    @Test("Selecting a unit persists it")
    func unitSelectionPersists() async {
        let store = makeStore()
        #expect(store.state.preferredUnit == .system)

        await store.send(.unitSelected(.imperial)) {
            $0.$preferences.withLock { $0.preferredUnit = .imperial }
        }
        #expect(store.state.preferredUnit == .imperial)

        await store.send(.unitSelected(.metric)) {
            $0.$preferences.withLock { $0.preferredUnit = .metric }
        }
        #expect(store.state.preferredUnit == .metric)
    }

    /// A combo sensor holding both the Speed and Cadence roles is one physical
    /// device — the count must not double it (S12: "count of paired sensors").
    @Test("Sensor count is deduped by peripheral, not by role record")
    func pairedSensorCountDedupesByPeripheral() {
        let comboID = UUID()
        let radarID = UUID()
        let store = makeStore()
        store.state.$preferences.withLock {
            $0.pairedSensors = [
                PairedSensor(peripheralID: comboID, role: .speed, displayName: "Combo"),
                PairedSensor(peripheralID: comboID, role: .cadence, displayName: "Combo"),
                PairedSensor(peripheralID: radarID, role: .radar, displayName: "Varia")
            ]
        }
        #expect(store.state.pairedSensorCount == 2)
    }

    // MARK: - HR Zones (#103)

    @Test("HR zone rows default to the Karvonen worked example, and only rows 1-4 are steppable")
    func hrZoneRowsDefaultToKarvonen() {
        let store = makeStore()

        let ranges = store.state.hrZoneRows.map(\.range)
        #expect(ranges == [60...137, 138...150, 151...163, 164...176, 177...190])
        #expect(store.state.hrZoneRows.map(\.isSteppable) == [true, true, true, true, false])
        #expect(store.state.hrZoneRows.map(\.displayName) == [
            "Recovery/Light", "Endurance", "Aerobic", "Threshold", "Anaerobic"
        ])
    }

    @Test("Stepping a row's boundary persists the override into the shared rider profile")
    func steppingBoundaryPersists() async {
        let store = makeStore()

        await store.send(.hrZoneBoundaryStepped(zone: .zone1, delta: 1)) {
            $0.$riderProfile.withLock { $0.zone1CeilingOverrideBPM = 138 }
        }

        #expect(store.state.hrZoneRows[0].range == 60...138)
        #expect(store.state.hrZoneRows[1].range == 139...150)
    }

    @Test("Stepping past a neighbouring boundary is a no-op")
    func steppingPastNeighbourIsNoop() async {
        let profile = try! RiderProfile().settingBoundaryOverride(149, afterZone: .zone1)
        let store = makeStore(riderProfile: profile)

        // zone2's boundary defaults to 150 — stepping zone1 past it would cross.
        await store.send(.hrZoneBoundaryStepped(zone: .zone1, delta: 1))

        #expect(store.state.riderProfile.zone1CeilingOverrideBPM == 149)
    }

    @Test("`.task` fetches HealthKit terms and hrZoneRows reflect them, not the 60/190 defaults (#160)")
    func taskPopulatesHRZoneRowsFromHealthKit() async {
        let store = makeStore(healthKitClient: .mock(
            restingHeartRate: 48,
            dateOfBirth: DateComponents(year: 1990, month: 1, day: 1)
        ))
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.healthProfileFetched) {
            $0.healthRestingBPM = 48
            // Fixed test clock is 2027-01-15; already 37 by 1990-01-01 → 220 − 37 = 183.
            $0.healthMaxBPM = 183
        }

        #expect(store.state.hrZoneRows.map(\.range) == [48...128, 129...142, 143...155, 156...169, 170...183])
    }

    @Test(".hrZoneResetTapped clears every manual boundary override")
    func resetClearsManualBoundaries() async {
        var profile = RiderProfile()
        profile = try! profile.settingBoundaryOverride(130, afterZone: .zone1)
        profile = try! profile.settingBoundaryOverride(180, afterZone: .zone4)
        let store = makeStore(riderProfile: profile)

        await store.send(.hrZoneResetTapped) {
            $0.$riderProfile.withLock { $0 = $0.resettingZoneBoundaries() }
        }

        #expect(store.state.hrZoneRows.map(\.range) == [60...137, 138...150, 151...163, 164...176, 177...190])
    }
}
