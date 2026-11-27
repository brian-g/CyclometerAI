import ComposableArchitecture
import Foundation
import os

// Stream live: Console.app / Xcode console, filter subsystem "xyz.acmeapps.ride".
private let logger = Logger.cyclometer(.accounts)

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

/// How a connect or Reconnect ended, for the screen that started it: S12.1, or S10's Sync To (#631).
enum StravaConnectOutcome: Equatable, Sendable {
    case connected
    /// The rider closed sign-in or declined on Strava: nothing to say.
    case cancelled
    case failed
}

extension StravaAuthClient {
    /// `connect`, with the rider backing out told apart from a failure, which is logged.
    func connectOutcome() async -> StravaConnectOutcome {
        do {
            _ = try await connect()
            return .connected
        } catch let error as StravaAuthError where error.isRiderCancellation {
            return .cancelled
        } catch is CancellationError {
            // The screen that started it closed mid sign-in: not a failure either.
            return .cancelled
        } catch {
            logger.error("Strava connect failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }
}

extension AlertState {
    /// A connect or Reconnect that failed, for any screen that offers one.
    static var stravaConnectFailed: Self {
        AlertState {
            TextState("Couldn't Connect to Strava")
        } actions: {
            ButtonState(role: .cancel) {
                TextState("OK")
            }
        } message: {
            TextState("Check your connection and try again.")
        }
    }
}

private extension StravaAuthError {
    /// The rider backed out: closed sign-in, came back from the Strava app without finishing, or
    /// declined on the consent screen. Not a failure to report.
    var isRiderCancellation: Bool {
        switch self {
        case .cancelled, .denied: true
        default: false
        }
    }
}
