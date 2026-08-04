import SwiftUI
import ComposableArchitecture

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>
    /// The number pad has no return key, so the manual circumference commits when
    /// focus leaves the field (via the keyboard's Done button or a tap elsewhere).
    @FocusState private var isCircumferenceFocused: Bool

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let build, !build.isEmpty, build != version { return "\(version) (\(build))" }
        return version
    }

    var body: some View {
        Form {
            Section {
                Picker("Units", selection: $store.selectedUnits.sending(\.unitSelected)) {
                    ForEach(SettingsDemoData.units, id: \.self) { Text($0) }
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
                Toggle("Set Do Not Disturb", isOn: Binding(
                    get: { store.shouldSetDoNotDisturb },
                    set: { _ in store.send(.doNotDisturbToggled) }
                ))
                NavigationLink("Sensors") { SensorManagementView() }
            } footer: {
                if store.wheelSelection == .custom {
                    Text("Wheel circumference must be between 1,500 and 3,000 mm.")
                        .foregroundStyle(store.isCustomCircumferenceInvalid ? Color.red : Color.secondary)
                }
            }

            Section {
                ForEach(store.heartRateZones) { zone in
                    Stepper {
                        LabeledContent(zone.name, value: "\(zone.lowerBound)-\(zone.upperBound) bpm")
                    } onIncrement: {
                        store.send(.hrZoneUpperBoundAdjusted(id: zone.id, delta: 1))
                    } onDecrement: {
                        store.send(.hrZoneUpperBoundAdjusted(id: zone.id, delta: -1))
                    }
                }
            } header: {
                Text("HR Zones")
            } footer: {
                Text("HR Zone data is derived from data collected by Apple Health.")
            }

            Section("Accounts") {
                LabeledContent("Strava",        value: SettingsDemoData.stravaAccountStatus)
                LabeledContent("Ride with GPS", value: SettingsDemoData.rideWithGPSAccountStatus)
                Button {
                    store.send(.addAccountTapped)
                } label: {
                    Label("Add Account", systemImage: "plus.circle")
                }
                .confirmationDialog(
                    "Add Account",
                    isPresented: Binding(
                        get: { store.isShowingAddAccountOptions },
                        set: { _ in store.send(.addAccountDismissed) }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Strava") { }
                    Button("Ride with GPS") { }
                    Button("Cancel", role: .cancel) { }
                }
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                NavigationLink("Privacy Policy") { PrivacyPolicyView() }
            }
        }
        .navigationTitle("Settings")
        .onChange(of: isCircumferenceFocused) { _, isFocused in
            if !isFocused { store.send(.customCircumferenceCommitted) }
        }
        .toolbar {
            if isCircumferenceFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isCircumferenceFocused = false }
                }
            }
        }
    }
}

struct SensorManagementView: View {
    private let sensors = SensorStatus.demoSensors
    var body: some View {
        List(sensors) { sensor in
            LabeledContent {
                Text(sensor.status).foregroundStyle(.secondary)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sensor.name)
                        Text(sensor.detail).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: sensor.systemImage).foregroundStyle(sensor.tint)
                }
            }
        }
        .navigationTitle("Sensors")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section("Privacy Policy") {
                ForEach(SettingsDemoData.privacyPolicyParagraphs, id: \.self) { Text($0) }
            }
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
