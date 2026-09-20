import ComposableArchitecture
import SwiftUI

/// S01 — Welcome and permissions.
struct WelcomeView: View {
    @Bindable var store: StoreOf<WelcomeFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Scrolled rather than squeezed: a plain VStack hands the copy whatever
            // vertical space is left over, and SwiftUI answers a too-short proposal by
            // truncating each paragraph to one line instead of wrapping it (#254). The
            // scroll view proposes the copy's ideal height, so it always wraps in full;
            // at default type on a full-size phone nothing actually scrolls.
            ScrollView {
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
                }
                // Every Text above is multi-line at some type size; without this they
                // each collapse to a truncated single line when space runs short.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            if !store.state.isNextEnabled {
                Text("You must give permissions to use Bluetooth, Location, and Motion. HealthKit is optional.")
                    .font(.subheadline)
                    .foregroundStyle(Color.cyTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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

#Preview("Welcome — needs permissions") {
    WelcomeView(
        store: Store(initialState: WelcomeFeature.State()) {
            WelcomeFeature()
        } withDependencies: {
            $0.permissionsClient = .mock(initial: [.bluetooth: .granted])
        }
    )
}

#Preview("Welcome — all granted") {
    WelcomeView(
        store: Store(initialState: WelcomeFeature.State()) {
            WelcomeFeature()
        } withDependencies: {
            $0.permissionsClient = .mock(initial: [
                .bluetooth: .granted,
                .locationWhenInUse: .granted,
                .motion: .granted,
                .health: .granted
            ])
        }
    )
}
