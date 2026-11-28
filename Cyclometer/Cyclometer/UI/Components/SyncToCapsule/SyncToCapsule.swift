import SwiftUI

/// One sync destination as a capsule: its mark and name, filled when chosen or sent. S10's Sync To
/// toggles (#631) and S15's Synced To row (#632) draw it alike. `primaryDark` for every
/// destination, not each service's brand color (UX §S10, #637); unfilled, outlined so it reads
/// against the page. A service waiting on Reconnect shows the connection symbol in place of its
/// mark, unfilled.
struct SyncToCapsule: View {
    enum Size {
        /// S10's toggles.
        case regular
        /// S15's row, as Design.sketch — S15 - Ride Detail (Alternative) draws it: a row label's
        /// companion, smaller than S10's.
        case compact
    }

    let destination: SyncDestination
    let isFilled: Bool
    var needsReconnect = false
    var size = Size.regular
    let action: () -> Void

    /// The mark's height: Strava's is an image, which doesn't size itself to the text as a symbol does.
    @ScaledMetric(relativeTo: .subheadline) private var regularMarkHeight = Spacing.lg
    @ScaledMetric(relativeTo: .caption) private var compactMarkHeight = Spacing.md

    /// `strava-mark.svg`'s glyph fills 512 of its viewBox's 640 points of height, so its frame is
    /// that much taller for the glyph itself to be the mark's height. Here rather than a cropped
    /// asset: S12's Accounts row draws the same file at its own size.
    private static let stravaMarkFrameScale: CGFloat = 640 / 512

    var body: some View {
        let filled = isFilled && !needsReconnect
        let markHeight = size == .regular ? regularMarkHeight : compactMarkHeight
        Button(action: action) {
            Label {
                Text(destination.name)
            } icon: {
                mark.frame(height: destination == .service(.strava) && !needsReconnect
                           ? markHeight * Self.stravaMarkFrameScale : markHeight)
            }
            .labelStyle(SyncToLabelStyle())
            .font(size == .regular ? .subheadline.weight(.medium) : .caption.weight(.medium))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, size == .regular ? Spacing.sm : Spacing.xs)
            .foregroundStyle(filled ? Color.cyTextOnPrimary : Color.cyTextSecondary)
            .background(filled ? Color.cyPrimaryDark : Color.cyBgTertiary, in: Capsule())
            .overlay {
                if !filled {
                    Capsule().strokeBorder(Color.cyBorder, lineWidth: Spacing.strokeThin)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(filled ? .isSelected : [])
        .accessibilityHint(needsReconnect ? "Reconnects your account" : "")
    }

    @ViewBuilder private var mark: some View {
        if needsReconnect {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
        } else {
            switch destination {
            case .appleHealth:
                Image(systemName: "figure.run")
            case .service(.strava):
                // Template-rendered, so it takes the capsule's color: no orange outside Strava's
                // own assets (#629).
                Image(.stravaMark).resizable().scaledToFit()
            case .service:
                Image(systemName: "arrow.up.circle")
            }
        }
    }
}

/// The mark and name close together, as the frames space them.
private struct SyncToLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.xs) {
            configuration.icon
            configuration.title
        }
    }
}

extension SyncDestination {
    /// The capsule's name.
    var name: LocalizedStringResource {
        switch self {
        case .appleHealth: "Apple Health"
        case .service(.strava): "Strava"
        case .service(.rideWithGPS): "Ride with GPS"
        case .service(.tribosDotStudio): "tribos.studio"
        case .service(.komoot): "Komoot"
        }
    }
}

// MARK: - Previews

#Preview("Regular") {
    HStack {
        SyncToCapsule(destination: .appleHealth, isFilled: true) {}
        SyncToCapsule(destination: .service(.strava), isFilled: false) {}
    }
    .padding()
}

#Preview("Regular — reconnect") {
    SyncToCapsule(destination: .service(.strava), isFilled: true, needsReconnect: true) {}
        .padding()
}

#Preview("Compact") {
    HStack {
        SyncToCapsule(destination: .service(.strava), isFilled: true, size: .compact) {}
        SyncToCapsule(destination: .appleHealth, isFilled: false, size: .compact) {}
    }
    .padding()
}

#Preview("Compact — dark") {
    HStack {
        SyncToCapsule(destination: .service(.strava), isFilled: true, size: .compact) {}
        SyncToCapsule(destination: .appleHealth, isFilled: true, size: .compact) {}
    }
    .padding()
    .preferredColorScheme(.dark)
}
