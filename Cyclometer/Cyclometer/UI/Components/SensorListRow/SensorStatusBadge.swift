import SwiftUI

/// A paired sensor's live status as a capsule: Connected or Searching. Shared by the Start
/// sheet (S05.1) and the ride's Sensors sheet (#466), so a rider reads one status the same way
/// before and during a ride.
struct SensorStatusBadge: View {
    let status: SensorRow.Status

    var body: some View {
        let badge = status.badge
        Text(badge.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .foregroundStyle(badge.foreground)
            .background(badge.background, in: Capsule())
    }
}

// MARK: - Previews

#Preview("Statuses") {
    VStack(spacing: Spacing.md) {
        SensorStatusBadge(status: .connected)
        SensorStatusBadge(status: .searching)
    }
    .padding()
}
