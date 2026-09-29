import ComposableArchitecture
import SwiftUI

/// Presented by `AppFeature` as a full-bleed, non-dismissible overlay (#105) — the
/// opaque background here is what occludes the tab structure underneath.
struct OnboardingView: View {
    @Bindable var store: StoreOf<OnboardingFeature>
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        ZStack {
            Color.cyBgPrimary.ignoresSafeArea()

            // Increase Contrast falls back to the flat color above (#328) — a mesh
            // gradient works against high-contrast legibility, so it isn't drawn at all.
            if colorSchemeContrast == .standard {
                AnimatedMeshBackground().ignoresSafeArea()
            }

            switch store.step {
            case .welcome:
                WelcomeView(store: store.scope(state: \.welcome, action: \.welcome))
            case .sensorPairing:
                SensorPairingView(store: store.scope(state: \.sensorPairing, action: \.sensorPairing))
            }
        }
        .task { await store.send(.task).finish() }
    }
}

#Preview {
    OnboardingView(
        store: Store(initialState: OnboardingFeature.State(step: .welcome)) {
            OnboardingFeature()
        }
    )
}
