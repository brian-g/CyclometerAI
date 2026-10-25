import SwiftUI
import ComposableArchitecture

/// S12. Each section reads the store itself; the numeric fields are `NumericEntryRow`s, which own
/// their focus and commit on blur (#439).
struct SettingsView: View {
    let store: StoreOf<SettingsFeature>

    var body: some View {
        Form {
            GeneralSection(store: store)
            HRZonesSection(store: store)
            CadenceZonesSection(store: store)
            AboutSection()
        }
        .navigationTitle("Settings")
        .task { await store.send(.task).finish() }
    }
}

private struct GeneralSection: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        Section {
            Picker("Units", selection: $store.preferredUnit.sending(\.unitSelected)) {
                ForEach(UnitSystem.allCases, id: \.self) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }
            Picker("Wheel Size", selection: $store.wheelSelection.sending(\.wheelSelectionChanged)) {
                ForEach(WheelPreset.allCases) { preset in
                    Text(preset.label).tag(WheelSelection.preset(preset))
                }
                Text("Custom").tag(WheelSelection.custom)
            }
            if store.wheelSelection == .custom {
                // The range sits in the field's own row (#424), and only while the entry is out of
                // range, like the HR overrides' errors (#429).
                NumericEntryRow(
                    "Circumference",
                    text: $store.customCircumferenceText.sending(\.customCircumferenceChanged),
                    placeholder: "mm",
                    unit: "mm",
                    errorMessage: store.isCustomCircumferenceInvalid ? Text(WheelPreset.outOfRangeMessage) : nil
                ) {
                    store.send(.customCircumferenceCommitted)
                }
            }
            Toggle("Auto-pause", isOn: $store.isAutoPauseEnabled.sending(\.autoPauseChanged))
            Toggle("Auto-dim", isOn: $store.isAutoDimEnabled.sending(\.autoDimChanged))
            Toggle("Place Names", isOn: $store.isPlaceNameLookupEnabled.sending(\.placeNameLookupChanged))
            // Off in iOS Settings, the rider's own choice is kept but can't take effect, and the
            // row says why (#313).
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Toggle("Show Live Activity", isOn: $store.isLiveActivityEnabled.sending(\.liveActivityChanged))
                .disabled(!store.isSystemLiveActivityEnabled)
                if !store.isSystemLiveActivityEnabled {
                    Text("Live Activities are turned off for Cyclometer in iOS Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Borderless, or the whole row — the toggle included — becomes the button.
                    Button("Open Settings") { store.send(.liveActivitySettingsTapped) }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }
            NavigationLink {
                DeviceManagementView(
                    store: store.scope(state: \.deviceManagement, action: \.deviceManagement)
                )
            } label: {
                LabeledContent("Sensors", value: "\(store.pairedSensorCount)")
            }
        }
    }
}

private struct HRZonesSection: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        Section {
            // One field per HR override (#162).
            NumericEntryRow(
                "Resting HR",
                text: $store.restingOverrideText.sending(\.restingOverrideChanged),
                placeholder: store.restingOverridePlaceholder,
                unit: "bpm",
                errorMessage: store.restingOverrideValidationError.map { Text($0.message) }
            ) {
                store.send(.restingOverrideCommitted)
            }
            NumericEntryRow(
                "Max HR",
                text: $store.maxOverrideText.sending(\.maxOverrideChanged),
                placeholder: store.maxOverridePlaceholder,
                unit: "bpm",
                errorMessage: store.maxOverrideValidationError.map { Text($0.message) }
            ) {
                store.send(.maxOverrideCommitted)
            }
            ForEach(store.hrZoneRows) { row in
                if row.isSteppable {
                    Stepper {
                        LabeledContent(row.displayName, value: "\(row.range.lowerBound)-\(row.range.upperBound) bpm")
                    } onIncrement: {
                        store.send(.hrZoneBoundaryStepped(zone: row.zone, delta: 1))
                    } onDecrement: {
                        store.send(.hrZoneBoundaryStepped(zone: row.zone, delta: -1))
                    }
                } else {
                    LabeledContent(row.displayName, value: "\(row.range.lowerBound)-\(row.range.upperBound) bpm")
                }
            }
            Button("Reset HR Zones to Defaults") {
                store.send(.hrZoneResetTapped)
            }

        } header: {
            Text("HR Zones")
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("HR Zone data is derived from data collected by Apple Health.")
            }
        }
    }
}

private struct CadenceZonesSection: View {
    let store: StoreOf<SettingsFeature>

    var body: some View {
        Section("Cadence Zones") {
            ForEach(store.cadenceZoneRows) { row in
                if row.isSteppable {
                    Stepper {
                        LabeledContent(row.displayName, value: row.rangeText)
                    } onIncrement: {
                        store.send(.cadenceZoneBoundaryStepped(zone: row.zone, delta: 1))
                    } onDecrement: {
                        store.send(.cadenceZoneBoundaryStepped(zone: row.zone, delta: -1))
                    }
                } else {
                    LabeledContent(row.displayName, value: row.rangeText)
                }
            }
            Button("Reset Cadence Zones to Defaults") {
                store.send(.cadenceZoneResetTapped)
            }
        }
    }
}

private struct AboutSection: View {
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let build, !build.isEmpty, build != version { return "\(version) (\(build))" }
        return version
    }

    var body: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            NavigationLink("Privacy Policy") { PrivacyPolicyView() }
        }
    }
}

private struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section("Privacy Policy") {
                ForEach(SettingsData.privacyPolicyParagraphs, id: \.self) { Text($0) }
            }
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

// HealthKit and ActivityKit are stubbed: neither has a `previewValue`, and `.task` reads both.
// The CSC client is too: committing a circumference pushes it to the sensor.
private func previewStore(
    isSystemLiveActivityEnabled: Bool = true,
    isCustomWheel: Bool = false,
    customCircumferenceDraft: String? = nil,
    restingOverrideDraft: String? = nil,
    maxOverrideDraft: String? = nil
) -> StoreOf<SettingsFeature> {
    var state = SettingsFeature.State()
    state.isSystemLiveActivityEnabled = isSystemLiveActivityEnabled
    state.userChoseCustom = isCustomWheel
    state.customCircumferenceDraft = customCircumferenceDraft
    state.restingOverrideDraft = restingOverrideDraft
    state.maxOverrideDraft = maxOverrideDraft
    return Store(initialState: state) {
        SettingsFeature()
    } withDependencies: {
        $0.bleCSCClient = .testValue
        $0.healthKitClient = .testValue
        var liveActivity = LiveActivityClient.testValue
        liveActivity.isEnabled = { isSystemLiveActivityEnabled }
        $0.liveActivityClient = liveActivity
    }
}

#Preview("Default") {
    NavigationStack { SettingsView(store: previewStore(isSystemLiveActivityEnabled: true)) }
}

#Preview("Live Activities off in iOS") {
    NavigationStack { SettingsView(store: previewStore(isSystemLiveActivityEnabled: false)) }
}

#Preview("Custom wheel size") {
    NavigationStack { SettingsView(store: previewStore(isCustomWheel: true)) }
}

#Preview("Custom wheel size, out of range") {
    NavigationStack { SettingsView(store: previewStore(isCustomWheel: true, customCircumferenceDraft: "900")) }
}

#Preview("HR overrides out of range") {
    NavigationStack { SettingsView(store: previewStore(restingOverrideDraft: "20", maxOverrideDraft: "50")) }
}
