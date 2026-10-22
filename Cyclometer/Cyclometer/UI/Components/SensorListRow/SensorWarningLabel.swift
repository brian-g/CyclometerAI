import SwiftUI

/// A sensor's health warning (#391), drawn full width under its `SensorListRowView`. Shared
/// by the Start sheet (S05.1), which warns from the last ride, and the Ride Summary (S10),
/// which lists the sensors that misbehaved on the ride just finished.
///
/// `cyRatingBad`, as `SensorBatteryLabel` draws a low level, rather than the amber
/// `cyRatingOkay`: amber caption text is 2.5:1 on the light list background, under AA.
struct SensorWarningLabel: View {
    let warning: SensorWarning
    /// The Start sheet's warning is about a ride that is over; S10's is about this one.
    var isFromLastRide = false

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(Color.cyRatingBad)
    }

    /// Names no cause it can't know: a low reading says the battery is low, and a flapping
    /// link alone points at both things that cause one.
    var message: String {
        let when = isFromLastRide ? " on last ride" : ""
        return switch warning {
        case .batteryLow: "Low battery\(when)"
        case .linkUnreliable: "Unreliable connection\(when) — check battery or mount"
        }
    }
}

// MARK: - Previews

#Preview("Warnings") {
    VStack(alignment: .leading, spacing: Spacing.md) {
        SensorWarningLabel(warning: .batteryLow)
        SensorWarningLabel(warning: .linkUnreliable)
        SensorWarningLabel(warning: .batteryLow, isFromLastRide: true)
        SensorWarningLabel(warning: .linkUnreliable, isFromLastRide: true)
    }
    .padding()
}
