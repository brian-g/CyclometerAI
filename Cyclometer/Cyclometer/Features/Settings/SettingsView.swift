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
            AccountsSection(store: store)
            AboutSection()
        }
        .navigationTitle("Settings")
        .task { await store.send(.task).finish() }
        // A dim preview the slider never ended gives the rider's brightness back (#471).
        .onDisappear { store.send(.dimPreviewEnded) }
    }
}

/// The Settings tab's stack, driven by `SettingsFeature.path` so S12.1's Disconnect can pop it
/// (#629). Shaped like `RidesNavigationStack`.
struct SettingsNavigationStack: View {
    @Bindable var store: StoreOf<SettingsFeature>
    /// Hides Start Ride while a ride records, as every tab does.
    var isStartRideHidden: Bool = false
    var onStartRide: () -> Void = {}

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            SettingsView(store: store)
                .startRideToolbarItem(isHidden: isStartRideHidden, action: onStartRide)
        } destination: { pathStore in
            switch pathStore.case {
            case .stravaAccount(let accountStore):
                AccountsView(store: accountStore)
            }
        }
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
            // The caption sits in the row, as Show Live Activity's does (#313 review), not in a footer
            // below Sensors (#267). In the label, so VoiceOver reads it with the toggle as a subtitle.
            Toggle(isOn: $store.isResumeWhenMovingEnabled.sending(\.resumeWhenMovingChanged)) {
                Text("Resume When Moving")
                Text("Also resumes a ride you paused yourself. Walking the bike counts as moving.")
            }
            Toggle("Auto-dim", isOn: $store.isAutoDimEnabled.sending(\.autoDimChanged))
            if store.isAutoDimEnabled {
                // The level the dim drops to (#471). Dragging shows it on the real backlight.
                Slider(
                    value: $store.autoDimBrightness.sending(\.autoDimBrightnessChanged),
                    in: AppPreferences.autoDimBrightnessRange
                ) {
                    Text("Dimmed Brightness")
                } minimumValueLabel: {
                    Image(systemName: "sun.min")
                } maximumValueLabel: {
                    Image(systemName: "sun.max")
                } onEditingChanged: { isEditing in
                    store.send(isEditing ? .dimPreviewBegan : .dimPreviewEnded)
                }
                .accessibilityValue(store.autoDimBrightness.formatted(.percent.precision(.fractionLength(0))))
            }
            Toggle("Place Names", isOn: $store.isPlaceNameLookupEnabled.sending(\.placeNameLookupChanged))
            // Off in iOS Settings, the rider's own choice is kept but can't take effect, and the
            // row says why (#313), in the label's subtitle like Resume When Moving's.
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Toggle(isOn: $store.isLiveActivityEnabled.sending(\.liveActivityChanged)) {
                    Text("Show Live Activity")
                    if !store.isSystemLiveActivityEnabled {
                        Text("Live Activities are turned off for Acme Ride in iOS Settings.")
                    }
                }
                .disabled(!store.isSystemLiveActivityEnabled)
                if !store.isSystemLiveActivityEnabled {
                    // Borderless, or the whole row — the toggle included — becomes the button.
                    Button("Open Settings") { store.send(.liveActivitySettingsTapped) }
                        .font(.subheadline)
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

/// One row per supported service (#629), connected or not: just Strava for now. The row pushes
/// S12.1, which shows Connect or the account. After Cadence Zones, which Design.sketch predates.
private struct AccountsSection: View {
    let store: StoreOf<SettingsFeature>

    var body: some View {
        Section("Accounts") {
            NavigationLink(state: store.stravaAccount) {
                LabeledContent {
                    if store.stravaNeedsReconnect { Text("Reconnect") }
                } label: {
                    Label {
                        Text("Strava")
                    } icon: {
                        // Strava's mark in the label colour, as Design.sketch draws it: no orange
                        // outside Strava's own assets.
                        Image(.stravaMark)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(Color.cyTextPrimary)
                    }
                }
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
            // Opens the published policy in Safari (#598). A `Link`, so VoiceOver reads it
            // as one; offline, Safari shows its own error page.
            Link("Privacy Policy", destination: AppLinks.privacyPolicy)
        }
    }
}

// MARK: - Previews

// HealthKit and ActivityKit are stubbed: neither has a `previewValue`, and `.task` reads both.
// The CSC client is too: committing a circumference pushes it to the sensor. And the screen
// client: dragging the Auto-dim slider sets the backlight.
private func previewStore(
    isSystemLiveActivityEnabled: Bool = true,
    isAutoDimEnabled: Bool = true,
    isCustomWheel: Bool = false,
    customCircumferenceDraft: String? = nil,
    restingOverrideDraft: String? = nil,
    maxOverrideDraft: String? = nil,
    isStravaDisconnected: Bool = false
) -> StoreOf<SettingsFeature> {
    var state = SettingsFeature.State()
    state.isSystemLiveActivityEnabled = isSystemLiveActivityEnabled
    state.$preferences.withLock {
        $0.isAutoDimEnabled = isAutoDimEnabled
        $0.connectedServices = isStravaDisconnected ? [
            ConnectedService(
                serviceType: .strava,
                keychainIdentifier: StravaConfig.keychainAccount,
                athleteID: "134815",
                grantedScopes: Set(StravaConfig.requestedScopes),
                connectedAt: Date(timeIntervalSince1970: 1_795_996_800),
                isDisconnected: true
            ),
        ] : []
    }
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
        $0.screenClient = .testValue
    }
}

#Preview("Default") {
    SettingsNavigationStack(store: previewStore(isSystemLiveActivityEnabled: true))
}

#Preview("Live Activities off in iOS") {
    SettingsNavigationStack(store: previewStore(isSystemLiveActivityEnabled: false))
}

#Preview("Auto-dim off") {
    SettingsNavigationStack(store: previewStore(isAutoDimEnabled: false))
}

#Preview("Custom wheel size") {
    SettingsNavigationStack(store: previewStore(isCustomWheel: true))
}

#Preview("Custom wheel size, out of range") {
    SettingsNavigationStack(store: previewStore(isCustomWheel: true, customCircumferenceDraft: "900"))
}

#Preview("Strava needs reconnecting") {
    SettingsNavigationStack(store: previewStore(isStravaDisconnected: true))
}

#Preview("HR overrides out of range") {
    SettingsNavigationStack(store: previewStore(restingOverrideDraft: "20", maxOverrideDraft: "50"))
}
