import ComposableArchitecture
import Foundation

/// S12.1 Strava Account (UX.md §S12.1, TCA.md §4.15, #629), pushed from S12's Accounts row.
///
/// Its Uploads section (#632) is the one place an upload's progress shows: each ride on its way to
/// Strava, and each that failed, with Retry. Read as the screen appears, and followed from there
/// by the records the store writes (`liveStravaSyncRecords`).
///
/// Connect and Reconnect are one flow: `StravaAuthClient.connect` replaces any earlier record,
/// which is how Reconnect clears `isDisconnected` or adds a scope the rider unticked. The record
/// arrives through `@Shared(.appPreferences)`, which the client writes. The athlete's name and
/// photo are fetched each time the screen appears and never stored (PRD §8.12).
///
/// Disconnect is confirmed here and run by `SettingsFeature`, which pops this screen first: the
/// client removes the record before it revokes, so a screen waiting on the revoke would show the
/// Connect button until it answered, offline for as long as the request takes to time out.
@Reducer
struct AccountsFeature {
    @Dependency(\.stravaAuth) var stravaAuth
    @Dependency(\.strava) var strava
    @Dependency(\.persistenceClient) var persistenceClient

    private enum CancelID { case athlete, uploads }

    @ObservableState
    struct State: Equatable {
        @Shared(.appPreferences) var preferences
        /// Nil until Strava answers, and when it can't (offline): the card shows the photo's
        /// placeholder and "Strava".
        var athlete: StravaAthlete?
        /// While sign-in is showing, so a second tap doesn't start another.
        var isConnecting = false
        @Presents var alert: AlertState<Action.Alert>?
        /// The rides on their way to Strava or failed, as read when the screen appeared (#632).
        var fetchedUploads: [StravaWorkItem] = []
        /// Strava records written since, laid over `fetchedUploads`.
        @SharedReader(.liveStravaSyncRecords) var liveSyncRecords

        /// The Uploads section's rows (#632): each fetched ride with its record as last written. A
        /// ride that has since reached Strava, or whose record was reset, drops out.
        var uploads: [StravaWorkItem] {
            fetchedUploads.compactMap { item in
                guard let record = liveSyncRecords.record(for: item.rideId, stored: item.record),
                      record.status != .synced else { return nil }
                var item = item
                item.record = record
                return item
            }
        }

        /// The connected account. Nil with no record, and also when Strava revoked access: both show
        /// the Connect button (UX §S12.1).
        var account: ConnectedService? { preferences.stravaAccount }

        /// What the rider unticked on Strava's consent screen, for the Permissions section.
        var missingPermissions: [StravaPermission] {
            account.map { StravaPermission.missing(from: $0.grantedScopes) } ?? []
        }
    }

    enum Action: Equatable {
        case task
        /// Nil when the fetch failed: the card keeps its placeholder.
        case athleteFetched(StravaAthlete?)
        case uploadsFetched([StravaWorkItem])
        /// Retry on a failed upload's row (#632).
        case retryTapped(rideId: UUID)
        /// Connect, and Reconnect in the Permissions section.
        case connectTapped
        case connectFinished(StravaConnectOutcome)
        case disconnectTapped
        case alert(PresentationAction<Alert>)
        case delegate(Delegate)

        @CasePathable
        enum Alert: Equatable {
            case confirmDisconnect
        }

        @CasePathable
        enum Delegate: Equatable {
            /// The rider confirmed Disconnect. The parent pops this screen and disconnects.
            case disconnectConfirmed
            /// A connect or Reconnect finished: uploads waiting on Strava can go (#630). Sent from
            /// here because `StravaSession` writes the record outside any reducer, where the
            /// parent's `.onChange` would never see it change.
            case connected
            /// Send the ride to Strava again (#632): `AppFeature` queues it.
            case uploadToStrava(rideId: UUID)
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                guard state.account != nil else { return .none }
                return refresh()

            case .athleteFetched(let athlete):
                state.athlete = athlete
                return .none

            case .uploadsFetched(let uploads):
                state.fetchedUploads = uploads
                return .none

            case .retryTapped(let rideId):
                guard state.uploads.contains(where: { $0.rideId == rideId && $0.record.status == .failed }) else { return .none }
                return .send(.delegate(.uploadToStrava(rideId: rideId)))

            case .connectTapped:
                guard !state.isConnecting else { return .none }
                state.isConnecting = true
                return .run { [stravaAuth] send in
                    await send(.connectFinished(await stravaAuth.connectOutcome()))
                }

            case .connectFinished(let outcome):
                state.isConnecting = false
                switch outcome {
                case .connected:
                    return .merge(.send(.delegate(.connected)), refresh())
                case .cancelled:
                    return .none
                case .failed:
                    state.alert = .stravaConnectFailed
                    return .none
                }

            case .disconnectTapped:
                state.alert = .confirmDisconnect
                return .none

            case .alert(.presented(.confirmDisconnect)):
                return .send(.delegate(.disconnectConfirmed))

            case .alert, .delegate:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }

    /// What the connected screen reads as it appears: the uploads from the store, then the name and
    /// photo from Strava. One after the other, local first, so the section doesn't wait on the
    /// network and the two land in a fixed order.
    private func refresh() -> Effect<Action> {
        .concatenate(fetchUploads(), fetchAthlete())
    }

    /// The name and photo. A later fetch replaces one still in flight, so Reconnect's answer
    /// can't be overwritten by the appearance's.
    private func fetchAthlete() -> Effect<Action> {
        .run { [strava] send in
            await send(.athleteFetched(try? await strava.athlete()))
        }
        .cancellable(id: CancelID.athlete, cancelInFlight: true)
    }

    /// The Uploads section's rides. A failed read leaves the section as it was: it's logged in
    /// `RidePersistenceActor`.
    private func fetchUploads() -> Effect<Action> {
        .run { [persistenceClient] send in
            guard let uploads = try? await persistenceClient.fetchRidesWithStravaWork() else { return }
            await send(.uploadsFetched(uploads))
        }
        .cancellable(id: CancelID.uploads, cancelInFlight: true)
    }
}

extension AlertState where Action == AccountsFeature.Action.Alert {
    /// UX §S12.1's copy.
    static let confirmDisconnect = AlertState {
        TextState("Disconnect Strava?")
    } actions: {
        ButtonState(role: .destructive, action: .confirmDisconnect) {
            TextState("Disconnect")
        }
        ButtonState(role: .cancel) {
            TextState("Cancel")
        }
    } message: {
        TextState("Rides already uploaded stay on Strava. Segments and Strava routes shown in Cyclometer are removed.")
    }
}

/// A Strava scope the rider can untick on Strava's consent screen, with what it turns off
/// (PRD §8.12: a feature whose scope is missing is hidden and named on S12.1).
///
/// `read` can't be unticked, and `profile:read_all` serves only gear, which waits for Multi-bike,
/// so neither is listed. The quoted names are Strava's consent-screen labels.
struct StravaPermission: Equatable, Identifiable, Sendable {
    let scope: String
    let explanation: String
    var id: String { scope }

    /// In the order the Permissions section lists them.
    static let all: [StravaPermission] = [
        StravaPermission(scope: StravaConfig.uploadScope, explanation: "Uploads need “Upload your activities”."),
        StravaPermission(scope: StravaConfig.privateActivitiesScope, explanation: "Segments on private rides need “View data about your private activities”."),
        StravaPermission(scope: "read_all", explanation: "Private routes and segments need “View data about your private routes, segments, and events”."),
    ]

    static func missing(from granted: Set<String>) -> [StravaPermission] {
        all.filter { !granted.contains($0.scope) }
    }
}
