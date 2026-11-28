import SwiftUI

/// S15's Synced To row (#632, UX §S15), as Design.sketch — S15 - Ride Detail (Alternative) draws it:
/// "Synced To" with one capsule per destination, filled once the ride is sent or on its way. A
/// failed upload or a deleted activity says so on a line under the capsules; a failure has Retry.
/// No progress: S12.1 shows that.
///
/// A section of its own for now. #633 puts the Strava Segments row above it, in the same card.
struct SyncedToSection: View {
    let syncedTo: RideDetailFeature.SyncedTo
    let tap: (SyncDestination) -> Void
    let retry: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Side by side as drawn, or the capsules under the label when they don't fit.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.md) {
                        label
                        Spacer(minLength: 0)
                        HStack(spacing: Spacing.xs) { capsules }
                    }
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        label
                        HStack(spacing: Spacing.xs) { capsules }
                    }
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        label
                        VStack(alignment: .leading, spacing: Spacing.xs) { capsules }
                    }
                }
                if let status = syncedTo.status {
                    StatusLine(status: status, retry: retry)
                }
            }
        }
    }

    private var label: some View {
        Text("Synced To")
    }

    private var capsules: some View {
        ForEach(syncedTo.capsules) { capsule in
            SyncToCapsule(destination: capsule.destination, isFilled: capsule.isSent, size: .compact) {
                tap(capsule.destination)
            }
            .accessibilityHint(capsule.hint)
        }
    }
}

/// What went wrong, under the capsules. A failure's Retry sits beside the reason, or under it
/// when the two don't fit side by side (large text).
private struct StatusLine: View {
    let status: RideDetailFeature.SyncedTo.Status
    let retry: () -> Void

    var body: some View {
        Group {
            switch status {
            case .failed(let reason):
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        failure(reason)
                        Spacer(minLength: 0)
                        retryButton
                    }
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        failure(reason)
                        retryButton
                    }
                }
            case .deletedOnStrava:
                Text("Deleted on Strava. Tap Strava to upload it again.")
            }
        }
        .font(.footnote)
        .foregroundStyle(Color.cyTextSecondary)
    }

    /// The glyph and Strava's reason, close together: a list's `Label` spaces its icon as a row's.
    private func failure(_ reason: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.cyRatingBad)
            Text(reason)
        }
    }

    private var retryButton: some View {
        Button("Retry", action: retry)
            .buttonStyle(.borderless)
            .fontWeight(.semibold)
    }
}

private extension RideDetailFeature.SyncedTo.Capsule {
    /// What a tap does, for VoiceOver: the capsule's look alone doesn't say.
    var hint: String {
        switch (destination, isSent) {
        case (.appleHealth, true): "Opens Health"
        case (.appleHealth, false): "Adds this ride to Apple Health"
        case (.service(.strava), true): "Opens the ride on Strava"
        case (.service(.strava), false): "Uploads this ride to Strava"
        case (.service, _): ""
        }
    }
}

// MARK: - Previews

private func syncedToPreview(_ syncedTo: RideDetailFeature.SyncedTo) -> some View {
    List {
        SyncedToSection(syncedTo: syncedTo, tap: { _ in }, retry: {})
    }
}

#Preview("Synced") {
    syncedToPreview(.init(capsules: [.init(destination: .appleHealth, isSent: true),
                                     .init(destination: .service(.strava), isSent: true)], status: nil))
}

#Preview("Never sent") {
    syncedToPreview(.init(capsules: [.init(destination: .appleHealth, isSent: false),
                                     .init(destination: .service(.strava), isSent: false)], status: nil))
}

#Preview("Failed") {
    syncedToPreview(.init(capsules: [.init(destination: .appleHealth, isSent: true),
                                     .init(destination: .service(.strava), isSent: false)],
                          status: .failed("The file was empty.")))
}

#Preview("Deleted on Strava") {
    syncedToPreview(.init(capsules: [.init(destination: .appleHealth, isSent: true),
                                     .init(destination: .service(.strava), isSent: false)],
                          status: .deletedOnStrava))
}

#Preview("Health only — dark") {
    syncedToPreview(.init(capsules: [.init(destination: .appleHealth, isSent: true)], status: nil))
        .preferredColorScheme(.dark)
}
