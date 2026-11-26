import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// `StravaAuthClient`'s live logic (#626, PRD §8.12) against a scripted token service, an
/// in-memory Keychain and an in-memory AppPreferences document. The presenter, which only shows
/// Strava's page, is replaced by a closure returning the redirect.
@Suite("StravaSession")
struct StravaSessionTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let account = StravaConfig.keychainAccount

    // MARK: - Fixtures

    /// The token service: a scripted answer per endpoint, and every call it received.
    final class TokenService: Sendable {
        struct Call: Equatable {
            var endpoint: String
            var body: [String: String]
        }

        let calls = LockIsolated<[Call]>([])
        let answers: LockIsolated<[String: (status: Int, body: Data)]>
        /// Holds each answer back, so concurrent callers overlap a refresh in flight.
        let latency: Duration

        init(_ answers: [String: (status: Int, body: Data)] = [:], latency: Duration = .zero) {
            self.answers = LockIsolated(answers)
            self.latency = latency
        }

        func calls(to endpoint: String) -> [Call] {
            calls.value.filter { $0.endpoint == endpoint }
        }

        var transport: StravaTransport {
            StravaTransport { [self] request in
                let url = try #require(request.url)
                let body = try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody))
                calls.withValue { $0.append(Call(endpoint: url.lastPathComponent, body: body)) }
                if latency > .zero { try await Task.sleep(for: latency) }
                let answer = answers.value[url.lastPathComponent] ?? (500, Data())
                return (answer.body, HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: nil, headerFields: nil)!)
            }
        }
    }

    /// Strava's `oauth/token` answer as the token service passes it through.
    static func tokenAnswer(access: String, refresh: String, expiresAt: Date, athlete: Bool = false) -> (status: Int, body: Data) {
        var json: [String: Any] = [
            "token_type": "Bearer",
            "access_token": access,
            "refresh_token": refresh,
            "expires_at": Int(expiresAt.timeIntervalSince1970),
            "expires_in": 21_600,
        ]
        if athlete {
            json["athlete"] = ["id": 12_345, "firstname": "Ada", "lastname": "Lovelace", "city": "London"]
        }
        return (200, try! JSONSerialization.data(withJSONObject: json))
    }

    static let record = ConnectedService(
        serviceType: .strava,
        keychainIdentifier: account,
        athleteID: "12345",
        grantedScopes: ["read", "activity:write"],
        connectedAt: now.addingTimeInterval(-86_400)
    )

    static func stored(_ tokens: OAuthTokens) -> LockIsolated<[String: Data]> {
        LockIsolated([account: try! JSONEncoder().encode(tokens)])
    }

    static func tokens(in keychain: LockIsolated<[String: Data]>) throws -> OAuthTokens? {
        try keychain.value[account].map { try JSONDecoder().decode(OAuthTokens.self, from: $0) }
    }

    static func makeSession(
        service: TokenService,
        keychain: LockIsolated<[String: Data]> = LockIsolated([:]),
        preferences: Shared<AppPreferences>,
        authorize: @escaping StravaSession.Authorize = { _ in throw StravaAuthError.cancelled },
        clearCaches: @escaping @Sendable () async throws -> Void = {}
    ) -> StravaSession {
        StravaSession(
            transport: service.transport,
            keychain: .inMemory(keychain),
            now: { now },
            preferences: preferences,
            authorize: authorize,
            clearCaches: clearCaches
        )
    }

    static func connected(_ record: ConnectedService = record) -> Shared<AppPreferences> {
        var preferences = AppPreferences()
        preferences.connectedServices = [record]
        return Shared(value: preferences)
    }

    static func redirect(_ query: String) -> URL {
        URL(string: "\(StravaConfig.redirectURI)?\(query)")!
    }

    // MARK: - Access token

    @Test("A token with five minutes or more left is used as is, without a refresh")
    func freshTokenIsUsedAsIs() async throws {
        let service = TokenService()
        let session = Self.makeSession(
            service: service,
            keychain: Self.stored(OAuthTokens(accessToken: "a1", refreshToken: "r1", expiresAt: Self.now.addingTimeInterval(300))),
            preferences: Self.connected()
        )

        #expect(try await session.accessToken() == "a1")
        #expect(service.calls.value.isEmpty)
    }

    /// Strava rotates the refresh token, so a second concurrent refresh would present a dead one
    /// and read as revoked. Whatever the interleaving, one refresh: a caller arriving during it
    /// joins it, and one arriving after finds the fresh token in the Keychain.
    @Test("Ten concurrent requests for an expiring token refresh once, and the rotated token is stored")
    func concurrentRequestsRefreshOnce() async throws {
        let service = TokenService(
            ["refresh": Self.tokenAnswer(access: "a2", refresh: "r2", expiresAt: Self.now.addingTimeInterval(21_600))],
            latency: .milliseconds(50)
        )
        let keychain = Self.stored(OAuthTokens(accessToken: "a1", refreshToken: "r1", expiresAt: Self.now.addingTimeInterval(299)))
        let session = Self.makeSession(service: service, keychain: keychain, preferences: Self.connected())

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<10 { group.addTask { try await session.accessToken() } }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(tokens == Array(repeating: "a2", count: 10))
        #expect(service.calls.value == [TokenService.Call(endpoint: "refresh", body: ["refresh_token": "r1"])])
        #expect(try Self.tokens(in: keychain) == OAuthTokens(
            accessToken: "a2", refreshToken: "r2", expiresAt: Self.now.addingTimeInterval(21_600)
        ))
    }

    // MARK: - Refresh after a 401

    @Test("A token Strava rejected is refreshed although the clock says it's fresh")
    func rejectedTokenIsRefreshed() async throws {
        let service = TokenService(
            ["refresh": Self.tokenAnswer(access: "a2", refresh: "r2", expiresAt: Self.now.addingTimeInterval(21_600))]
        )
        let keychain = Self.stored(OAuthTokens(accessToken: "a1", refreshToken: "r1", expiresAt: Self.now.addingTimeInterval(3_600)))
        let session = Self.makeSession(service: service, keychain: keychain, preferences: Self.connected())

        #expect(try await session.refreshAccessToken(rejected: "a1") == "a2")
        #expect(service.calls.value == [TokenService.Call(endpoint: "refresh", body: ["refresh_token": "r1"])])
        #expect(try Self.tokens(in: keychain)?.refreshToken == "r2")
    }

    @Test("Ten concurrent requests rejected with the same token refresh once")
    func concurrentRejectionsRefreshOnce() async throws {
        let service = TokenService(
            ["refresh": Self.tokenAnswer(access: "a2", refresh: "r2", expiresAt: Self.now.addingTimeInterval(21_600))],
            latency: .milliseconds(50)
        )
        let keychain = Self.stored(OAuthTokens(accessToken: "a1", refreshToken: "r1", expiresAt: Self.now.addingTimeInterval(3_600)))
        let session = Self.makeSession(service: service, keychain: keychain, preferences: Self.connected())

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<10 { group.addTask { try await session.refreshAccessToken(rejected: "a1") } }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(tokens == Array(repeating: "a2", count: 10))
        #expect(service.calls(to: "refresh").count == 1)
    }

    @Test("A rejection of a token already replaced returns the stored one without refreshing")
    func staleRejectionUsesStoredToken() async throws {
        let service = TokenService()
        let session = Self.makeSession(
            service: service,
            keychain: Self.stored(OAuthTokens(accessToken: "a2", refreshToken: "r2", expiresAt: Self.now.addingTimeInterval(21_600))),
            preferences: Self.connected()
        )

        #expect(try await session.refreshAccessToken(rejected: "a1") == "a2")
        #expect(service.calls.value.isEmpty)
    }

    @Test("A refresh after a 401 that Strava refuses marks the account disconnected")
    func refusedForcedRefreshDisconnects() async throws {
        let preferences = Self.connected()
        let session = Self.makeSession(
            service: TokenService(["refresh": (400, Data())]),
            keychain: Self.stored(OAuthTokens(accessToken: "a1", refreshToken: "r1", expiresAt: Self.now.addingTimeInterval(3_600))),
            preferences: preferences
        )

        await #expect(throws: StravaAuthError.disconnected) { try await session.refreshAccessToken(rejected: "a1") }
        #expect(preferences.wrappedValue.connectedServices.first?.isDisconnected == true)
    }

    @Test("A refresh Strava refuses marks the account disconnected, and later requests don't call out", arguments: [400, 401])
    func refusedRefreshDisconnects(status: Int) async throws {
        let service = TokenService(["refresh": (status, Data(#"{"message":"Bad Request"}"#.utf8))])
        let preferences = Self.connected()
        let session = Self.makeSession(
            service: service,
            keychain: Self.stored(OAuthTokens(accessToken: "a1", refreshToken: "r1", expiresAt: Self.now)),
            preferences: preferences
        )

        await #expect(throws: StravaAuthError.disconnected) { try await session.accessToken() }
        #expect(preferences.wrappedValue.connectedServices.first?.isDisconnected == true)

        await #expect(throws: StravaAuthError.disconnected) { try await session.accessToken() }
        #expect(service.calls.value.count == 1)
    }

    @Test("A failure that isn't a refusal leaves the account connected")
    func transientFailureStaysConnected() async throws {
        let service = TokenService(["refresh": (502, Data())])
        let preferences = Self.connected()
        let session = Self.makeSession(
            service: service,
            keychain: Self.stored(OAuthTokens(accessToken: "a1", refreshToken: "r1", expiresAt: Self.now)),
            preferences: preferences
        )

        await #expect(throws: StravaAuthError.tokenService(status: 502)) { try await session.accessToken() }
        #expect(preferences.wrappedValue.connectedServices.first?.isDisconnected == false)
    }

    /// The record travels in a backup and the tokens don't, so a restored or new iPhone has the
    /// record alone (#628 review). It must read as disconnected, so S12 offers Reconnect.
    @Test("A record without its Keychain item is disconnected, with no network call")
    func recordWithoutKeychainItemDisconnects() async throws {
        let service = TokenService()
        let preferences = Self.connected()
        let session = Self.makeSession(service: service, preferences: preferences)

        await #expect(throws: StravaAuthError.disconnected) { try await session.accessToken() }
        #expect(preferences.wrappedValue.connectedServices.first?.isDisconnected == true)
        #expect(service.calls.value.isEmpty)
    }

    @Test("With no record, a request is not connected")
    func noRecordIsNotConnected() async throws {
        let session = Self.makeSession(service: TokenService(), preferences: Shared(value: AppPreferences()))

        await #expect(throws: StravaAuthError.notConnected) { try await session.accessToken() }
    }

    // MARK: - Connect

    @Test("Connect exchanges the code, stores the tokens and saves the record with the granted scopes")
    func connectSavesTokensAndRecord() async throws {
        let service = TokenService(
            ["token": Self.tokenAnswer(access: "a1", refresh: "r1", expiresAt: Self.now.addingTimeInterval(21_600), athlete: true)]
        )
        let keychain = LockIsolated<[String: Data]>([:])
        // A disconnected record from before: Reconnect replaces it.
        var stale = Self.record
        stale.isDisconnected = true
        let preferences = Self.connected(stale)
        let session = Self.makeSession(
            service: service,
            keychain: keychain,
            preferences: preferences,
            authorize: { state in Self.redirect("state=\(state)&code=abc&scope=read,activity:write") }
        )

        let record = try await session.connect()

        #expect(record == ConnectedService(
            serviceType: .strava,
            keychainIdentifier: Self.account,
            athleteID: "12345",
            grantedScopes: ["read", "activity:write"],
            connectedAt: Self.now
        ))
        #expect(preferences.wrappedValue.connectedServices == [record])
        #expect(service.calls.value == [TokenService.Call(endpoint: "token", body: ["code": "abc"])])
        #expect(try Self.tokens(in: keychain) == OAuthTokens(
            accessToken: "a1", refreshToken: "r1", expiresAt: Self.now.addingTimeInterval(21_600)
        ))
    }

    @Test("Declining on Strava's consent screen saves nothing")
    func connectDenied() async throws {
        let service = TokenService()
        let preferences = Shared(value: AppPreferences())
        let keychain = LockIsolated<[String: Data]>([:])
        let session = Self.makeSession(
            service: service,
            keychain: keychain,
            preferences: preferences,
            authorize: { state in Self.redirect("state=\(state)&error=access_denied") }
        )

        await #expect(throws: StravaAuthError.denied) { try await session.connect() }
        #expect(service.calls.value.isEmpty)
        #expect(preferences.wrappedValue.connectedServices.isEmpty)
        #expect(keychain.value.isEmpty)
    }

    @Test("A redirect whose state doesn't match the request is rejected before any exchange")
    func connectRejectsForeignState() async throws {
        let service = TokenService()
        let session = Self.makeSession(
            service: service,
            preferences: Shared(value: AppPreferences()),
            authorize: { _ in Self.redirect("state=someone-else&code=abc&scope=read") }
        )

        await #expect(throws: StravaAuthError.invalidCallback) { try await session.connect() }
        #expect(service.calls.value.isEmpty)
    }

    @Test("A failed exchange saves nothing")
    func connectExchangeFails() async throws {
        let preferences = Shared(value: AppPreferences())
        let keychain = LockIsolated<[String: Data]>([:])
        let session = Self.makeSession(
            service: TokenService(["token": (400, Data(#"{"message":"Bad Request"}"#.utf8))]),
            keychain: keychain,
            preferences: preferences,
            authorize: { state in Self.redirect("state=\(state)&code=abc&scope=read") }
        )

        await #expect(throws: StravaAuthError.tokenService(status: 400)) { try await session.connect() }
        #expect(preferences.wrappedValue.connectedServices.isEmpty)
        #expect(keychain.value.isEmpty)
    }

    // MARK: - Disconnect

    @Test("Disconnect revokes the token, and removes the Keychain item, the record and the cached data")
    func disconnectRemovesEverything() async throws {
        let service = TokenService(["revoke": (200, Data())])
        let keychain = Self.stored(OAuthTokens(accessToken: "a1", refreshToken: "r1", expiresAt: Self.now.addingTimeInterval(3_600)))
        let preferences = Self.connected()
        let clears = LockIsolated(0)
        let session = Self.makeSession(
            service: service, keychain: keychain, preferences: preferences,
            clearCaches: { clears.withValue { $0 += 1 } }
        )

        try await session.disconnect()

        #expect(service.calls.value == [TokenService.Call(endpoint: "revoke", body: ["token": "r1"])])
        #expect(keychain.value.isEmpty)
        #expect(preferences.wrappedValue.connectedServices.isEmpty)
        #expect(clears.value == 1)
    }

    @Test("A failed revoke still disconnects")
    func disconnectSurvivesFailedRevoke() async throws {
        let keychain = Self.stored(OAuthTokens(accessToken: "a1", refreshToken: "r1", expiresAt: Self.now.addingTimeInterval(3_600)))
        let preferences = Self.connected()
        let clears = LockIsolated(0)
        let session = Self.makeSession(
            service: TokenService(["revoke": (502, Data())]), keychain: keychain, preferences: preferences,
            clearCaches: { clears.withValue { $0 += 1 } }
        )

        try await session.disconnect()

        #expect(keychain.value.isEmpty)
        #expect(preferences.wrappedValue.connectedServices.isEmpty)
        #expect(clears.value == 1)
    }

    // MARK: - Config

    @Test("The authorize URL carries the client id, redirect, every scope and the state")
    func authorizeURL() throws {
        let url = StravaConfig.webAuthorizeURL(state: "s1")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        #expect(url.host() == "www.strava.com")
        #expect(url.path() == "/oauth/mobile/authorize")
        #expect(query["client_id"] == "300241")
        #expect(query["redirect_uri"] == "cyclometer://acmeapps.xyz/strava")
        #expect(query["response_type"] == "code")
        #expect(query["scope"] == "read,read_all,profile:read_all,activity:read_all,activity:write")
        #expect(query["state"] == "s1")
        #expect(StravaConfig.appAuthorizeURL(state: "s1").absoluteString.hasPrefix("strava://oauth/mobile/authorize?"))
    }

    @Test("Only Strava's redirect is taken as one")
    func recognisesTheRedirect() {
        #expect(StravaConfig.isRedirect(Self.redirect("state=s&code=c")))
        #expect(!StravaConfig.isRedirect(URL(string: "cyclometer://acmeapps.xyz/other")!))
        #expect(!StravaConfig.isRedirect(URL(string: "https://acmeapps.xyz/strava")!))
        #expect(!StravaConfig.isRedirect(URL(filePath: "/tmp/route.gpx")))
    }
}
