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
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.caption.weight(.semibold))
        .textCase(.uppercase)
        .foregroundStyle(Color.cyRatingBad)
    }

    /// Names no cause it can't know: a low reading says the battery is low, and a flapping
    /// link alone points at both things that cause one.
    ///
    /// A resource rather than a `String`, so it wraps the English way whatever the device
    /// language (#430), and each case is a whole sentence a translator can reorder.
    var message: LocalizedStringResource {
        switch (warning, isFromLastRide) {
        case (.batteryLow, false): "Low battery"
        case (.batteryLow, true): "Low battery on last ride"
        case (.linkUnreliable, false): "Unreliable connection — check battery or mount"
        case (.linkUnreliable, true): "Unreliable connection on last ride — check battery or mount"
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
