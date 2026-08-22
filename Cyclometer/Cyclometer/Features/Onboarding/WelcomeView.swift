import ComposableArchitecture
import SwiftUI

/// S01 placeholder — real permission rows land with #106.
struct WelcomeView: View {
    @Bindable var store: StoreOf<WelcomeFeature>

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Text("WELCOME")
                .font(.title.bold())
                .foregroundStyle(Color.cyTextPrimary)
            Text("Permission requests land here (#106).")
                .font(.subheadline)
                .foregroundStyle(Color.cyTextSecondary)
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
    WelcomeView(store: Store(initialState: WelcomeFeature.State()) { WelcomeFeature() })
}
