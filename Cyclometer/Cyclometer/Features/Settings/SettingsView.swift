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
                }
                Toggle("Auto-pause", isOn: Binding(
                    get: { store.isAutoPauseEnabled },
                    set: { _ in store.send(.autoPauseToggled) }
                ))
                Toggle("Auto-dim", isOn: Binding(
                    get: { store.isAutoDimEnabled },
                    set: { _ in store.send(.autoDimToggled) }
                ))
                NavigationLink {
                    DeviceManagementView(
                        store: store.scope(state: \.deviceManagement, action: \.deviceManagement)
                    )
                } label: {
                    LabeledContent("Sensors", value: "\(store.pairedSensorCount)")
                }
            } footer: {
                if store.wheelSelection == .custom {
                    Text("Wheel circumference must be between 1,500 and 3,000 mm.")
                        .foregroundStyle(store.isCustomCircumferenceInvalid ? Color.red : Color.secondary)
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
                        Text(error.message).font(.caption).foregroundStyle(.red)
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
                        Text(error.message).font(.caption).foregroundStyle(.red)
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
