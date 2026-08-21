import ComposableArchitecture

/// What the wheel-size picker is showing: one of the PRD §8.9 presets, or a
/// manually entered circumference.
enum WheelSelection: Hashable, Sendable {
    case preset(WheelPreset)
    case custom
}

@Reducer
struct SettingsFeature {
    @Dependency(\.bleCSCClient) var bleCSCClient

    @ObservableState
    struct State: Equatable {
        @Shared(.appPreferences) var preferences
        /// S11 subset, pushed from the Sensors row. Non-optional like AppFeature's
        /// tab children — its effects only run while the screen's `.task` is alive.
        var deviceManagement = DeviceManagementFeature.State()
        /// In-progress manual entry. `nil` means the rider is not editing, so the
        /// field shows the persisted value — which is why no lifecycle action is
        /// needed to seed it, and why reverting a bad entry is just clearing this.
        var customCircumferenceDraft: String? = nil
        /// Only matters when the stored circumference happens to equal a preset —
        /// it keeps the custom field on screen while the rider is typing.
        var userChoseCustom: Bool = false
        var heartRateZones: [HeartRateZoneSetting] = HeartRateZoneSetting.standardZones

        /// Read through to storage rather than mirrored in feature state: both have
        /// to survive a relaunch, and `preferredUnit` also has to agree with whatever
        /// `ActiveRideFeature` eventually reads (#8). `isAutoDimEnabled` is read by
        /// `AppFeature`, which runs the dim countdown, off the same document (#110).
        var preferredUnit: UnitSystem { preferences.preferredUnit }
        var isAutoPauseEnabled: Bool { preferences.isAutoPauseEnabled }
        var isAutoDimEnabled: Bool { preferences.isAutoDimEnabled }

        /// Deduped by peripheral (`AppPreferences.pairedRoles`), so a combo
        /// speed+cadence sensor counts once rather than twice.
        var pairedSensorCount: Int { preferences.pairedRoles.count }

        /// Derived from the stored value, so a manual or auto-calibrated (#70)
        /// circumference still reads as Custom after a relaunch.
        var wheelSelection: WheelSelection {
            if userChoseCustom { return .custom }
            return WheelPreset(rawValue: preferences.wheelCircumferenceMM)
                .map(WheelSelection.preset) ?? .custom
        }

        /// What the manual-entry field shows: the live draft while editing,
        /// otherwise whatever is persisted.
        var customCircumferenceText: String {
            customCircumferenceDraft ?? String(preferences.wheelCircumferenceMM)
        }

        /// True while the rider has typed something that cannot be committed.
        var isCustomCircumferenceInvalid: Bool {
            guard case .custom = wheelSelection, !customCircumferenceText.isEmpty else { return false }
            guard let mm = Int(customCircumferenceText) else { return true }
            return !WheelPreset.validRange.contains(mm)
        }
    }
    enum Action: Equatable {
        case unitSelected(UnitSystem)
        case wheelSelectionChanged(WheelSelection)
        case customCircumferenceChanged(String)
        case customCircumferenceCommitted
        case autoPauseToggled
        case autoDimToggled
        case hrZoneUpperBoundAdjusted(id: Int, delta: Int)
        case deviceManagement(DeviceManagementFeature.Action)
    }
    var body: some ReducerOf<Self> {
        Scope(state: \.deviceManagement, action: \.deviceManagement) {
            DeviceManagementFeature()
        }

        Reduce { state, action in
            switch action {
            case .unitSelected(let unit):
                state.$preferences.withLock { $0.preferredUnit = unit }
                return .none
            case .wheelSelectionChanged(let selection):
                switch selection {
                case .preset(let preset):
                    state.userChoseCustom = false
                    return apply(preset.circumferenceMM, to: &state)
                case .custom:
                    state.userChoseCustom = true
                    return .none
                }
            case .customCircumferenceChanged(let text):
                state.customCircumferenceDraft = text; return .none
            case .customCircumferenceCommitted:
                guard let mm = Int(state.customCircumferenceText),
                      WheelPreset.validRange.contains(mm)
                else {
                    // Out of bounds or unparseable — dropping the draft falls the
                    // field back to the persisted value.
                    state.customCircumferenceDraft = nil
                    return .none
                }
                // Committing an unchanged value is a no-op. Picking a preset while
                // the field has focus tears the field down, which fires a commit —
                // without this it would push the same circumference twice.
                guard mm != state.preferences.wheelCircumferenceMM else { return .none }
                return apply(mm, to: &state)
            case .autoPauseToggled:
                state.$preferences.withLock { $0.isAutoPauseEnabled.toggle() }
                return .none
            case .autoDimToggled:
                state.$preferences.withLock { $0.isAutoDimEnabled.toggle() }
                return .none
            case .hrZoneUpperBoundAdjusted(let id, let delta):
                guard let index = state.heartRateZones.firstIndex(where: { $0.id == id }) else { return .none }
                let zone = state.heartRateZones[index]
                state.heartRateZones[index].upperBound = max(zone.lowerBound, zone.upperBound + delta)
                // Normalize downstream zones
                for i in (index + 1)..<state.heartRateZones.count {
                    let lb = state.heartRateZones[i - 1].upperBound + 1
                    state.heartRateZones[i].lowerBound = lb
                    state.heartRateZones[i].upperBound = max(state.heartRateZones[i].upperBound, lb)
                }
                return .none
            case .deviceManagement:
                return .none
            }
        }
    }

    /// Single funnel for every circumference change — persisting and pushing to
    /// the CSC client happen together so the stored value and the value driving
    /// the speed derivation cannot drift apart.
    private func apply(_ mm: Int, to state: inout State) -> Effect<Action> {
        state.$preferences.withLock { $0.wheelCircumferenceMM = mm }
        state.customCircumferenceDraft = nil
        return .run { [bleCSCClient] _ in
            await bleCSCClient.setWheelCircumference(mm)
        }
    }
}
