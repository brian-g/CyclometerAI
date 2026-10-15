import SwiftUI
import ComposableArchitecture

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>
    /// The number pad has no return key, so the manual circumference commits when
    /// focus leaves the field (via the keyboard's Done button or a tap elsewhere).
    @FocusState private var isCircumferenceFocused: Bool
    /// Same commit-on-blur wiring as `isCircumferenceFocused`, one per HR override
    /// field (#162).
    @FocusState private var isRestingOverrideFocused: Bool
    @FocusState private var isMaxOverrideFocused: Bool

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let build, !build.isEmpty, build != version { return "\(version) (\(build))" }
        return version
    }

    var body: some View {
        Form {
            Section {
                Picker("Units", selection: Binding(
                    get: { store.preferredUnit },
                    set: { store.send(.unitSelected($0)) }
                )) {
                    ForEach(UnitSystem.allCases, id: \.self) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                Picker("Wheel Size", selection: Binding(
                    get: { store.wheelSelection },
                    set: { store.send(.wheelSelectionChanged($0)) }
                )) {
                    ForEach(WheelPreset.allCases) { preset in
                        Text(preset.label).tag(WheelSelection.preset(preset))
                    }
                    Text("Custom").tag(WheelSelection.custom)
                }
                if store.wheelSelection == .custom {
                    // The range sits in the field's own row (#424), and only while the entry is out of
                    // range, like the HR overrides' errors (#429).
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("Circumference") {
                            HStack(spacing: 4) {
                                TextField("mm", text: Binding(
                                    get: { store.customCircumferenceText },
                                    set: { store.send(.customCircumferenceChanged($0)) }
                                ))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .focused($isCircumferenceFocused)
                                Text("mm").foregroundStyle(.secondary)
                            }
                        }
                        if store.isCustomCircumferenceInvalid {
                            Text(WheelPreset.outOfRangeMessage)
                                .font(.caption)
                                .foregroundStyle(Color.cyRatingBad)
                        }
                    }
                }
                Toggle("Auto-pause", isOn: Binding(
                    get: { store.isAutoPauseEnabled },
                    set: { _ in store.send(.autoPauseToggled) }
                ))
                Toggle("Auto-dim", isOn: Binding(
                    get: { store.isAutoDimEnabled },
                    set: { _ in store.send(.autoDimToggled) }
                ))
                Toggle("Place Names", isOn: Binding(
                    get: { store.isPlaceNameLookupEnabled },
                    set: { _ in store.send(.placeNameLookupToggled) }
                ))
                // Off in iOS Settings, the rider's own choice is kept but can't take effect, and the
                // row says why (#313).
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Show Live Activity", isOn: Binding(
                        get: { store.isLiveActivityEnabled },
                        set: { _ in store.send(.liveActivityToggled) }
                    ))
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

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Resting HR") {
                        HStack(spacing: 4) {
                            TextField(store.restingOverridePlaceholder, text: Binding(
                                get: { store.restingOverrideText },
                                set: { store.send(.restingOverrideChanged($0)) }
                            ))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($isRestingOverrideFocused)
                            Text("bpm").foregroundStyle(.secondary)
                        }
                    }
                    if let error = store.restingOverrideValidationError {
                        Text(error.message).font(.caption).foregroundStyle(Color.cyRatingBad)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Max HR") {
                        HStack(spacing: 4) {
                            TextField(store.maxOverridePlaceholder, text: Binding(
                                get: { store.maxOverrideText },
                                set: { store.send(.maxOverrideChanged($0)) }
                            ))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($isMaxOverrideFocused)
                            Text("bpm").foregroundStyle(.secondary)
                        }
                    }
                    if let error = store.maxOverrideValidationError {
                        Text(error.message).font(.caption).foregroundStyle(Color.cyRatingBad)
                    }
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("HR Zone data is derived from data collected by Apple Health.")
                }
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                NavigationLink("Privacy Policy") { PrivacyPolicyView() }
            }
        }
        .navigationTitle("Settings")
        .task { await store.send(.task).finish() }
        .onChange(of: isCircumferenceFocused) { _, isFocused in
            if !isFocused { store.send(.customCircumferenceCommitted) }
        }
        .onChange(of: isRestingOverrideFocused) { _, isFocused in
            if !isFocused { store.send(.restingOverrideCommitted) }
        }
        .onChange(of: isMaxOverrideFocused) { _, isFocused in
            if !isFocused { store.send(.maxOverrideCommitted) }
        }
        .toolbar {
            if isCircumferenceFocused || isRestingOverrideFocused || isMaxOverrideFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isCircumferenceFocused = false
                        isRestingOverrideFocused = false
                        isMaxOverrideFocused = false
                    }
                }
            }
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
