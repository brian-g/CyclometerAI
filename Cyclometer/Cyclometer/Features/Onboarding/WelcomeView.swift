import ComposableArchitecture
import SwiftUI

/// S01 — Welcome and permissions.
struct WelcomeView: View {
    @Bindable var store: StoreOf<WelcomeFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack() {
                Text("Welcome to Cyclometer").font(Font.largeTitle.bold())
                Spacer()
                Image("cyclometer.rider").resizable().frame(width:75, height: 75).aspectRatio(contentMode: .fill)
                    
            }
            Text("Ride faster. Arrive safer.")
                .font(.title2)
                .foregroundStyle(Color.cyTextPrimary)

            Text("""
            Real-time radar, metrics, and intelligence — built for cyclists who take the road seriously.

            Let's get started, first we need you to grant some permissions. Tap on each item to grant permission. When completed, tap Next.
            """)
                .font(.body)
                .foregroundStyle(Color.cyTextPrimary)

            VStack(spacing: Spacing.md) {
                ForEach(PermissionDomain.allCases, id: \.self) { domain in
                    PermissionRow(title: Self.label(for: domain), state: store.state.state(for: domain))
                        .contentShape(.rect)
                        .onTapGesture { store.send(.rowTapped(domain)) }
                }
            }

            Spacer()

            if !store.state.isNextEnabled {
                Text("You must give permissions to use Bluetooth, Location, and Motion. HealthKit is optional.")
                    .font(.subheadline)
                    .foregroundStyle(Color.cyTextSecondary)
            }

            Button {
                store.send(.nextButtonTapped)
            } label: {
                Text("Next")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyPrimary)
            .disabled(!store.state.isNextEnabled)
        }
        .padding(Spacing.lg)
        .task { await store.send(.task).finish() }
    }

    private static func label(for domain: PermissionDomain) -> String {
        switch domain {
        case .bluetooth: "Bluetooth"
        case .locationWhenInUse: "Location"
        case .motion: "Motion and Fitness"
        case .health: "HealthKit"
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let state: PermissionState

    var body: some View {
        HStack(spacing: Spacing.md) {
            PermissionStatusOval(state: state)
            Text(title)
                .font(.title3)
                .foregroundStyle(Color.cyTextPrimary)
            Spacer()
        }
        .frame(minHeight: Spacing.tapTarget)
    }
}

private struct PermissionStatusOval: View {
    let state: PermissionState

    private var isBlocked: Bool { state == .denied || state == .restricted }

    private var symbolName: String {
        if state.isGranted { "checkmark.circle.fill" }
        else if isBlocked { "xmark.circle.fill" }
        else { "circle" } // resting/neutral — notDetermined and unavailable both render this
    }

    var body: some View {
        Image(systemName: symbolName)
            .font(.largeTitle)
            .foregroundStyle(isBlocked ? .cyDestructive : .cyPrimary)
            .frame(width: Spacing.xxl, height: Spacing.xxl) // 36pt — Spacing.xxl is already "sensor icon size"
    }
}

#Preview {
    WelcomeView(store: Store(initialState: WelcomeFeature.State()) { WelcomeFeature() })
}
