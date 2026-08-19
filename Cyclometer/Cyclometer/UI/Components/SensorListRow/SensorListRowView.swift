import SwiftUI

/// One sensor in a list. Shared by the Start sheet's Sensors group (S05.1) and the
/// Sensors settings screen (S11).
///
/// The two lists model different things — the Start sheet shows a fixed *category*
/// (Radar / Heart Rate / Speed / Cadence) that is always present, the settings screen
/// a *device* that appears and disappears as scanning proceeds — but they draw the
/// same row: a tinted icon tile, a title over an optional subtitle, and a trailing
/// control. This owns that skeleton.
///
/// What fills each slot stays with the caller, including the trailing control: the
/// Start sheet swaps between a badge and a button depending on status, while the
/// settings screen always shows a button. Passing it in as a view keeps that decision
/// where the context lives rather than encoding both lists' rules here.
struct SensorListRowView<Trailing: View>: View {
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(
        icon: String,
        iconTint: Color = .cyPrimary,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(iconTint)
                .frame(width: Spacing.xxl, height: Spacing.xxl)
                .background(iconTint.opacity(Opacity.iconTile),
                            in: RoundedRectangle(cornerRadius: Spacing.cornerMd))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing
        }
        .padding(.vertical, Spacing.xs)
    }
}

/// The trailing action button in a sensor row — "Pair" or "Unpair" on S11.
///
/// Plain text rather than a capsule: S11 puts one on *every* row, paired or not, and a
/// column of filled capsules would shout. UX.md §S11 specifies text, matching the
/// Sketch's trailing accessory. The Start sheet carried a capsule "Tap to Pair" until
/// its rows became paired-only, at which point that button had no reachable state left.
struct SensorRowButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    init(_ title: String, tint: Color = .cyPrimary, action: @escaping () -> Void) {
        self.title = title
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .font(.body)
            .foregroundStyle(tint)
            // Load-bearing, not cosmetic: the default style in a `List` treats the whole
            // row as the button's target, which would swallow the row tap that role
            // reassignment depends on.
            .buttonStyle(.borderless)
    }
}

// MARK: - Previews

#Preview("Sensor rows") {
    List {
        SensorListRowView(
            icon: "sensor.tag.radiowaves.forward",
            title: "Wahoo RPM",
            subtitle: "Speed · Cadence"
        ) {
            SensorRowButton("Unpair", tint: .cyDestructive) {}
        }

        SensorListRowView(
            icon: "dot.radiowaves.forward",
            iconTint: .purple,
            title: "Radar",
            subtitle: "Varia RTL515"
        ) {
            Text("Connected")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .foregroundStyle(Color.cyTextOnPrimary)
                .background(Color.cyPrimary, in: Capsule())
        }

        SensorListRowView(icon: "speedometer", iconTint: .blue, title: "GSC-10") {
            SensorRowButton("Pair") {}
        }
    }
}
