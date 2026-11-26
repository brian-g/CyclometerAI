import ComposableArchitecture
import Foundation

/// TCA dependency for connecting Strava (TCA.md §4.15, PRD §8.12): sign-in through the Strava app
/// or an `ASWebAuthenticationSession`, the code exchange through the token service, and the tokens
/// after that. It owns Strava's `ConnectedService` record in the AppPreferences document: connect
/// saves it, a refused refresh flags `isDisconnected`, and disconnect removes it. Features read the
/// record through `@Shared(.appPreferences)`.
///
/// The live value is a `StravaSession` actor, which serializes refreshes.
struct StravaAuthClient: Sendable {
    /// Signs in, exchanges the code and saves the tokens and record. Returns the record.
    var connect: @Sendable () async throws -> ConnectedService
    /// A token to sign one Strava request, refreshed first when under five minutes are left.
    /// Throws `StravaAuthError.disconnected` when the account can't sign anything.
    var accessToken: @Sendable () async throws -> String
    /// A token to replace `rejected` after Strava answered it with a 401: refreshed, unless
    /// another request already replaced it. `StravaClient` retries once with it.
    var refreshAccessToken: @Sendable (_ rejected: String) async throws -> String
    /// Revokes the token, and removes the Keychain item, the record and Strava's cached ride and
    /// route data.
    var disconnect: @Sendable () async throws -> Void
    /// Hands Strava's redirect from the Strava app to the sign-in waiting for it. False when `url`
    /// isn't that redirect.
    var handleRedirect: @MainActor @Sendable (URL) -> Bool
}

extension StravaAuthClient: DependencyKey {
    static let liveValue: StravaAuthClient = {
        let presenter = StravaAuthPresenter()
        let session = StravaSession(
            transport: .live,
            keychain: .liveValue,
            now: { Date() },
            preferences: Shared(.appPreferences),
            authorize: { state in try await presenter.authorize(state: state) },
            clearCaches: { try await PersistenceClient.liveValue.clearStravaCaches() }
        )
        return StravaAuthClient(
            connect: { try await session.connect() },
            accessToken: { try await session.accessToken() },
            refreshAccessToken: { try await session.refreshAccessToken(rejected: $0) },
            disconnect: { try await session.disconnect() },
            handleRedirect: { presenter.handleRedirect($0) }
        )
    }()

    /// Not connected, and nothing to sign in to. Tests script what they need.
    static let testValue = StravaAuthClient(
        connect: { throw StravaAuthError.cancelled },
        accessToken: { throw StravaAuthError.notConnected },
        refreshAccessToken: { _ in throw StravaAuthError.notConnected },
        disconnect: {},
        handleRedirect: { _ in false }
    )

    static let previewValue: StravaAuthClient = testValue
}

extension DependencyValues {
    var stravaAuth: StravaAuthClient {
        get { self[StravaAuthClient.self] }
        set { self[StravaAuthClient.self] = newValue }
    }
}
