import ComposableArchitecture
import Foundation
import os

// Stream live: Console.app / Xcode console, filter subsystem "xyz.acmeapps.ride".
private let logger = Logger.cyclometer(.accounts)

/// Why a Strava sign-in or token request failed.
enum StravaAuthError: Error, Equatable {
    /// The rider closed sign-in, or came back from the Strava app without finishing it.
    case cancelled
    /// The rider declined on Strava's consent screen.
    case denied
    /// The callback's `state` didn't match the request, or it carried no code.
    case invalidCallback
    /// A sign-in is already showing.
    case inProgress
    /// No Strava account is connected.
    case notConnected
    /// The account is connected but can't sign a request: Strava refused a refresh (the rider
    /// revoked access on strava.com), or its Keychain item is missing (a restored or new iPhone).
    /// S12.1 offers Reconnect.
    case disconnected
    /// The token service or Strava answered with a failure that isn't a refusal. The account
    /// stays connected; a later request tries again.
    case tokenService(status: Int)
}

/// One HTTPS round trip, injected so the session is tested against scripted answers.
struct StravaTransport: Sendable {
    var send: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    /// Ephemeral, so no request or answer, both of which carry tokens, is cached on disk.
    static let live: StravaTransport = {
        let session = URLSession(configuration: .ephemeral)
        return StravaTransport { request in
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return (data, http)
        }
    }()
}

/// The live `StravaAuthClient`'s state (TCA.md §4.15, PRD §8.12): signs in, keeps the tokens in
/// the Keychain, refreshes them, and owns Strava's `ConnectedService` record in the
/// AppPreferences document.
///
/// An actor so refreshes are serialized. Strava rotates the refresh token on a refresh and the old
/// one stops working at once, so two concurrent refreshes would race: the loser presents a dead
/// token and the account reads as revoked. Instead every caller that finds the token expiring
/// awaits the one refresh in flight, and the rotated token is in the Keychain before any of them
/// gets the new access token.
actor StravaSession {
    /// Shows Strava's consent screen for a request carrying `state` and returns the redirect URL
    /// it came back with. `StravaAuthPresenter` in the app; a script in tests.
    typealias Authorize = @Sendable (_ state: String) async throws -> URL

    private let transport: StravaTransport
    private let keychain: KeychainClient
    private let now: @Sendable () -> Date
    private let preferences: Shared<AppPreferences>
    private let authorize: Authorize
    private let clearCaches: @Sendable () async throws -> Void

    /// The refresh in flight, which every caller needing a fresh token awaits.
    private var refreshTask: Task<OAuthTokens, any Error>?

    init(
        transport: StravaTransport,
        keychain: KeychainClient,
        now: @escaping @Sendable () -> Date,
        preferences: Shared<AppPreferences>,
        authorize: @escaping Authorize,
        clearCaches: @escaping @Sendable () async throws -> Void
    ) {
        self.transport = transport
        self.keychain = keychain
        self.now = now
        self.preferences = preferences
        self.authorize = authorize
        self.clearCaches = clearCaches
    }

    // MARK: - Connect

    /// Signs in, exchanges the code through the token service, writes the tokens to the Keychain
    /// and then saves the record, so a record never names an item that was never written.
    /// Replaces an earlier record, which is how Reconnect clears `isDisconnected`.
    func connect() async throws -> ConnectedService {
        let state = UUID().uuidString
        let callback = try await authorize(state)
        let (code, scopes) = try Self.authorization(from: callback, expectedState: state)

        let (data, status) = try await post("token", ["code": code])
        guard status == 200 else { throw StravaAuthError.tokenService(status: status) }
        let exchange = try Self.decodeTokens(data)
        guard let athlete = exchange.athlete else {
            logger.error("Strava's token exchange answered without an athlete")
            throw StravaAuthError.tokenService(status: status)
        }

        // A refresh from an earlier connection, still in flight, would write its tokens over
        // these when it lands.
        await settleRefresh()
        try keychain.write(StravaConfig.keychainAccount, Self.encode(exchange.tokens))
        let record = ConnectedService(
            serviceType: .strava,
            keychainIdentifier: StravaConfig.keychainAccount,
            athleteID: String(athlete.id),
            grantedScopes: scopes,
            connectedAt: now()
        )
        preferences.withLock { preferences in
            preferences.connectedServices.removeAll { $0.serviceType == .strava }
            preferences.connectedServices.append(record)
        }
        logger.info("connected Strava, scopes \(scopes.sorted().joined(separator: ","), privacy: .public)")
        return record
    }

    // MARK: - Access token

    /// A token to sign one Strava request: the stored one while it has five minutes or more
    /// left, otherwise a refreshed one.
    func accessToken() async throws -> String {
        let tokens = try usableTokens()
        if tokens.expiresAt.timeIntervalSince(now()) >= StravaConfig.refreshMargin {
            return tokens.accessToken
        }
        return try await refreshedTokens(from: tokens).accessToken
    }

    /// A token to replace `rejected`, which Strava answered with a 401 although the clock says it
    /// is still good. When the stored token is no longer `rejected`, another request has
    /// refreshed since, and that token is returned without refreshing again: concurrent 401s
    /// rotate the refresh token once.
    func refreshAccessToken(rejected: String) async throws -> String {
        let tokens = try usableTokens()
        guard tokens.accessToken == rejected else { return tokens.accessToken }
        return try await refreshedTokens(from: tokens).accessToken
    }

    /// The stored tokens, when the account can sign a request.
    private func usableTokens() throws -> OAuthTokens {
        guard let record = stravaRecord else { throw StravaAuthError.notConnected }
        guard !record.isDisconnected else { throw StravaAuthError.disconnected }
        // The record travels in a backup and the tokens don't (DataModel.md §3.8), so on a
        // restored or new iPhone it arrives without them. Flagged, S12 offers Reconnect rather
        // than showing an account that silently can't sign anything.
        guard let tokens = try storedTokens() else {
            logger.notice("Strava's record has no usable Keychain item; marking it disconnected")
            markDisconnected()
            throw StravaAuthError.disconnected
        }
        return tokens
    }

    /// Joins the refresh in flight, or starts one. The task is unstructured so a caller that is
    /// cancelled doesn't cancel the refresh: a rotated token Strava has already issued must still
    /// be written, or the next refresh presents a dead one.
    private func refreshedTokens(from tokens: OAuthTokens) async throws -> OAuthTokens {
        if let refreshTask { return try await refreshTask.value }
        let task = Task { try await self.refresh(tokens) }
        refreshTask = task
        defer { if refreshTask == task { refreshTask = nil } }
        return try await task.value
    }

    private func refresh(_ tokens: OAuthTokens) async throws -> OAuthTokens {
        let (data, status) = try await post("refresh", ["refresh_token": tokens.refreshToken])
        switch status {
        case 200:
            let refreshed = try Self.decodeTokens(data).tokens
            // Written before any caller sees the new access token: the old refresh token is
            // already dead.
            try keychain.write(StravaConfig.keychainAccount, Self.encode(refreshed))
            return refreshed
        case 400, 401:
            // Strava refused the refresh token: the rider revoked access on strava.com, or
            // deauthorized the app. The tokens stay until the rider disconnects or reconnects.
            logger.notice("Strava refused a refresh (\(status, privacy: .public)); marking it disconnected")
            markDisconnected()
            throw StravaAuthError.disconnected
        default:
            throw StravaAuthError.tokenService(status: status)
        }
    }

    // MARK: - Disconnect

    /// Removes the Keychain item, the record and the Strava data cached on rides and routes, and
    /// revokes the token through the token service (PRD §8.12).
    ///
    /// The item and record go before the revoke, so no request made while it is in flight can
    /// start a refresh with the token being revoked and write its answer back. The revoke is best
    /// effort: the rider asked to disconnect, and a failed revoke must not leave the account
    /// connected. Every step runs even when an earlier one fails; the first failure is thrown.
    func disconnect() async throws {
        await settleRefresh()
        let tokens = try? storedTokens()
        var firstError: (any Error)?

        do {
            try keychain.delete(StravaConfig.keychainAccount)
        } catch {
            firstError = error
        }
        preferences.withLock { $0.connectedServices.removeAll { $0.serviceType == .strava } }

        if let tokens {
            do {
                // Revoking either token revokes the other.
                let (_, status) = try await post("revoke", ["token": tokens.refreshToken])
                if status != 200 { logger.notice("Strava revoke answered \(status, privacy: .public); disconnected anyway") }
            } catch {
                logger.notice("Strava revoke failed: \(error.localizedDescription, privacy: .public); disconnected anyway")
            }
        }

        do {
            try await clearCaches()
        } catch {
            firstError = firstError ?? error
        }
        logger.info("disconnected Strava")
        if let firstError { throw firstError }
    }

    // MARK: - Helpers

    private var stravaRecord: ConnectedService? {
        preferences.wrappedValue.connectedServices.first { $0.serviceType == .strava }
    }

    private func markDisconnected() {
        preferences.withLock { preferences in
            guard let index = preferences.connectedServices.firstIndex(where: { $0.serviceType == .strava }) else { return }
            preferences.connectedServices[index].isDisconnected = true
        }
    }

    /// The stored tokens; nil when there is no item, or one this build can't read, either of
    /// which leaves nothing to sign with. A Keychain failure (before the first unlock) throws.
    private func storedTokens() throws -> OAuthTokens? {
        guard let data = try keychain.read(StravaConfig.keychainAccount) else { return nil }
        do {
            return try JSONDecoder().decode(OAuthTokens.self, from: data)
        } catch {
            logger.error("Strava's Keychain item doesn't decode: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Waits out any refresh in flight, including one started while waiting.
    private func settleRefresh() async {
        while let task = refreshTask {
            _ = try? await task.value
            if refreshTask == task { refreshTask = nil }
        }
    }

    /// POSTs a JSON body to one token service endpoint. Logs the status of a failure, never a
    /// body: both directions carry codes and tokens.
    private func post(_ endpoint: String, _ body: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: AppLinks.stravaTokenService.appending(path: endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await transport.send(request)
        if !(200..<300).contains(response.statusCode) {
            logger.error("strava \(endpoint, privacy: .public): \(response.statusCode, privacy: .public)")
        }
        return (data, response.statusCode)
    }

    /// The code and granted scopes from Strava's redirect. The state is checked first, so a
    /// redirect this sign-in didn't start is rejected whatever else it carries.
    static func authorization(from callback: URL, expectedState: String) throws -> (code: String, scopes: Set<String>) {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        guard value("state") == expectedState else {
            logger.error("Strava's redirect carried an unexpected state")
            throw StravaAuthError.invalidCallback
        }
        if value("error") == "access_denied" { throw StravaAuthError.denied }
        guard let code = value("code"), !code.isEmpty else { throw StravaAuthError.invalidCallback }
        let scopes = Set((value("scope") ?? "").split(separator: ",").map(String.init))
        return (code, scopes)
    }

    private static func encode(_ tokens: OAuthTokens) throws -> Data {
        try JSONEncoder().encode(tokens)
    }

    private static func decodeTokens(_ data: Data) throws -> TokenResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TokenResponse.self, from: data)
    }
}

/// Strava's `oauth/token` answer, passed through by the token service. The code exchange
/// includes the athlete; a refresh doesn't.
private struct TokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String
    /// Seconds since 1970.
    var expiresAt: TimeInterval
    var athlete: Athlete?

    var tokens: OAuthTokens {
        OAuthTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: Date(timeIntervalSince1970: expiresAt))
    }

    /// Only the id is kept; the name and photo are fetched when S12.1 shows them (PRD §8.12).
    struct Athlete: Decodable {
        var id: Int64
    }
}
