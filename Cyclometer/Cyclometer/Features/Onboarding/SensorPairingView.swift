import ComposableArchitecture
import SwiftUI

/// S02 placeholder — the real S11-shared sensor list lands with #107.
struct SensorPairingView: View {
    @Bindable var store: StoreOf<SensorPairingFeature>

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Text("ADD SENSORS")
                .font(.title.bold())
                .foregroundStyle(Color.cyTextPrimary)
            Text("Nearby sensors, tap to pair, pull to refresh.")
                .font(.subheadline)
                .foregroundStyle(Color.cyTextSecondary)
            Text("The S11 device list lands here (#107).")
                .font(.caption)
                .foregroundStyle(Color.cyTextTertiary)
            Spacer()
            Button {
                store.send(.nextButtonTapped)
            } label: {
                Text("Next")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyPrimary)
        }
        .padding(Spacing.lg)
    }
}

#Preview {
    SensorPairingView(store: Store(initialState: SensorPairingFeature.State()) { SensorPairingFeature() })
}
