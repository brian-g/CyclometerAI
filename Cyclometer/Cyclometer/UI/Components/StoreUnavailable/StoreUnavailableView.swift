import SwiftUI

/// S14 and S19 in place of their list when the history store failed to open (#206). The ride
/// list and the route library both live in it, so both screens show this. It says what is
/// still safe and offers the reset, which `AppFeature` confirms and runs.
///
/// Reset is disabled during a ride, which is writing to the store it would replace.
struct HistoryUnavailableView: View {
    var isResetDisabled: Bool
    var onReset: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("History Unavailable", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Your ride history couldn't be opened. It's still on this iPhone, and your ride GPX files in Files are safe. You can still record rides.")
        } actions: {
            StoreResetButton(title: "Reset Ride History…", isDisabled: isResetDisabled, action: onReset)
        }
    }
}

/// The first row of S14 when only the track store failed (#206). The list itself is intact;
/// what is missing is each past ride's recorded track, behind S15's map, charts and stats.
struct TracksUnavailableNotice: View {
    var isResetDisabled: Bool
    var onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Amber, the caution token, on the glyph only: amber text is under AA on the light
            // list background (`SensorWarningLabel`). Explicit, or the list tints it brand green.
            Label {
                Text("Ride Tracks Unavailable")
            } icon: {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(Color.cyRatingOkay)
            }
            .font(.headline)
            Text("Recorded tracks couldn't be opened, so past rides show no map or charts. Your rides and their GPX files are safe.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            StoreResetButton(title: "Reset Ride Tracks…", isDisabled: isResetDisabled, action: onReset)
        }
        .padding(.vertical, Spacing.sm)
    }
}

private struct StoreResetButton: View {
    let title: LocalizedStringKey
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button(title, role: .destructive, action: action)
                .buttonStyle(.bordered)
                .tint(.cyDestructive)
                .disabled(isDisabled)
            if isDisabled {
                Text("Finish your ride to reset.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Previews

#Preview("History unavailable") {
    HistoryUnavailableView(isResetDisabled: false, onReset: {})
}

#Preview("History unavailable — riding") {
    HistoryUnavailableView(isResetDisabled: true, onReset: {})
}

#Preview("Tracks unavailable") {
    List {
        TracksUnavailableNotice(isResetDisabled: false, onReset: {})
    }
    .listStyle(.plain)
}

#Preview("Tracks unavailable — riding") {
    List {
        TracksUnavailableNotice(isResetDisabled: true, onReset: {})
    }
    .listStyle(.plain)
}
