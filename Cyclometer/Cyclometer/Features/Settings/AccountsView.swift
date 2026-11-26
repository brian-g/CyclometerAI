import SwiftUI
import ComposableArchitecture

/// S12.1 Strava Account (UX.md §S12.1, Design.sketch "12.1 - Strava"), #629.
///
/// Strava's marks are its own unaltered assets (`Assets.xcassets/strava`), and Strava orange
/// appears only inside them (PRD §8.12 branding).
struct AccountsView: View {
    @Bindable var store: StoreOf<AccountsFeature>

    var body: some View {
        Group {
            if let account = store.account {
                ConnectedContent(store: store, account: account)
            } else {
                NotConnectedContent(store: store)
            }
        }
        .navigationTitle("Strava")
        // Not awaited: the athlete fetch is cancelled with the screen when it is popped.
        .task { store.send(.task) }
        .alert($store.scope(state: \.alert, action: \.alert))
    }
}

/// Also what a disconnected account shows: Strava's button alone, with no explanation or footer.
private struct NotConnectedContent: View {
    let store: StoreOf<AccountsFeature>

    var body: some View {
        ConnectWithStravaButton(store: store)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
    }
}

private struct ConnectedContent: View {
    let store: StoreOf<AccountsFeature>
    let account: ConnectedService

    var body: some View {
        Form {
            Section {
                AthleteCard(athlete: store.athlete, connectedAt: account.connectedAt)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                Button("Disconnect", role: .destructive) { store.send(.disconnectTapped) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.cyDestructive)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            if !store.missingPermissions.isEmpty {
                Section("Permissions") {
                    ForEach(store.missingPermissions) { permission in
                        Text(permission.explanation)
                    }
                    Button("Reconnect") { store.send(.connectTapped) }
                        .disabled(store.isConnecting)
                }
            }

            Section {
                Image(.stravaPoweredBy)
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, Spacing.xl)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Powered by Strava")
            }
            .listRowBackground(Color.clear)
        }
    }
}

/// The photo, the name and the connection date, on the screen's background as Sketch draws them.
private struct AthleteCard: View {
    let athlete: StravaAthlete?
    let connectedAt: Date

    /// Design.sketch "12.1 - Strava: connected".
    @ScaledMetric(relativeTo: .title2) private var photoSide: CGFloat = 64

    var body: some View {
        HStack(spacing: Spacing.md) {
            AthletePhoto(url: athlete?.photoURL)
                .frame(width: photoSide, height: photoSide)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // "Strava" until the name arrives, or when it can't (UX §S12.1).
                Text(athlete?.name ?? "Strava")
                    .font(.title2)
                    .foregroundStyle(Color.cyTextPrimary)
                Text("Connected since: \(connectedAt.formatted(date: .numeric, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(Color.cyTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Loads through a session with no URL cache, so the photo never reaches the disk (PRD §8.12:
/// the athlete's photo is never stored).
private struct AthletePhoto: View {
    let url: URL?

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .asyncImageURLSession(Self.session)
        .clipShape(.rect)
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.cyBgTertiary)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.title)
                    .foregroundStyle(Color.cyTextTertiary)
            }
    }
}

/// Strava's own "Connect with Strava" button, unaltered, at its 48 pt height.
private struct ConnectWithStravaButton: View {
    let store: StoreOf<AccountsFeature>

    var body: some View {
        Button { store.send(.connectTapped) } label: {
            Image(.stravaConnectButton)
        }
        .buttonStyle(.plain)
        .disabled(store.isConnecting)
        .accessibilityLabel("Connect with Strava")
    }
}

// MARK: - Previews

private func previewStore(
    account: ConnectedService?,
    athlete: StravaAthlete? = nil
) -> StoreOf<AccountsFeature> {
    var state = AccountsFeature.State()
    state.$preferences.withLock { $0.connectedServices = account.map { [$0] } ?? [] }
    state.athlete = athlete
    return Store(initialState: state) {
        AccountsFeature()
    } withDependencies: {
        $0.strava = .mock(athlete: athlete ?? StravaAthlete(name: nil, photoURL: nil))
    }
}

private func previewAccount(scopes: Set<String> = Set(StravaConfig.requestedScopes), isDisconnected: Bool = false) -> ConnectedService {
    ConnectedService(
        serviceType: .strava,
        keychainIdentifier: StravaConfig.keychainAccount,
        athleteID: "134815",
        grantedScopes: scopes,
        connectedAt: Date(timeIntervalSince1970: 1_795_996_800),
        isDisconnected: isDisconnected
    )
}

#Preview("Not connected") {
    NavigationStack { AccountsView(store: previewStore(account: nil)) }
}

#Preview("Disconnected by Strava") {
    NavigationStack { AccountsView(store: previewStore(account: previewAccount(isDisconnected: true))) }
}

#Preview("Connected") {
    NavigationStack {
        AccountsView(store: previewStore(account: previewAccount(), athlete: StravaAthlete(name: "Ada Lovelace", photoURL: nil)))
    }
}

#Preview("Connected, before the name arrives") {
    NavigationStack { AccountsView(store: previewStore(account: previewAccount())) }
}

#Preview("Connected, scopes unticked") {
    NavigationStack {
        AccountsView(store: previewStore(
            account: previewAccount(scopes: ["read", "profile:read_all"]),
            athlete: StravaAthlete(name: "Ada Lovelace", photoURL: nil)
        ))
    }
}

#Preview("Connected, dark") {
    NavigationStack {
        AccountsView(store: previewStore(account: previewAccount(), athlete: StravaAthlete(name: "Ada Lovelace", photoURL: nil)))
    }
    .preferredColorScheme(.dark)
}
