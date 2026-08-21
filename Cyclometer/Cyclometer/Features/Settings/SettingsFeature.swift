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

    /// One row of the S12 HR Zones table — what `SettingsView` reads to build the
    /// section. Rows 1-4 carry a working `Stepper` on that row's upper boundary;
    /// row 5 (Anaerobic) is display-only, so `isSteppable` is false only for it.
    struct HRZoneRow: Identifiable, Equatable {
        let zone: HeartRateZone
        var id: Int { zone.rawValue }
        let displayName: String
        let range: ClosedRange<Int>
        let isSteppable: Bool
    }

    @ObservableState
    struct State: Equatable {
        @Shared(.appPreferences) var preferences
        @Shared(.riderProfile) var riderProfile
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

        /// The S12 HR Zones table, derived from `riderProfile` via Karvonen (#103).
        var hrZoneRows: [HRZoneRow] {
            HeartRateZone.allCases.map { zone in
                HRZoneRow(
                    zone: zone,
                    displayName: zone.s12DisplayName,
                    range: riderProfile.bounds(for: zone),
                    isSteppable: zone != .zone5
                )
            }
        }

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
        case hrZoneBoundaryStepped(zone: HeartRateZone, delta: Int)
        case hrZoneResetTapped
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
            case .hrZoneBoundaryStepped(let zone, let delta):
                // An out-of-range step is a silent no-op — what makes the Stepper
                // stop naturally at a clamp, with no separate disabled-state to track.
                guard let current = state.riderProfile.resolvedBoundaryBPM(afterZone: zone),
                      let updated = try? state.riderProfile.settingBoundaryOverride(current + delta, afterZone: zone)
                else { return .none }
                state.$riderProfile.withLock { $0 = updated }
                return .none
            case .hrZoneResetTapped:
                state.$riderProfile.withLock { $0 = $0.resettingZoneBoundaries() }
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
