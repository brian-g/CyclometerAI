import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

/// S12.1 Strava Account (#629): connect, reconnect, disconnect, and what the screen reads.
@MainActor
@Suite("AccountsFeature")
struct AccountsFeatureTests {
    static let connectedAt = Date(timeIntervalSince1970: 1_795_996_800)
    static let ada = StravaAthlete(name: "Ada Lovelace", photoURL: URL(string: "https://example.com/ada.jpg"))

    static func record(
        scopes: Set<String> = Set(StravaConfig.requestedScopes),
        isDisconnected: Bool = false
    ) -> ConnectedService {
        ConnectedService(
            serviceType: .strava,
            keychainIdentifier: StravaConfig.keychainAccount,
            athleteID: "134815",
            grantedScopes: scopes,
            connectedAt: connectedAt,
            isDisconnected: isDisconnected
        )
    }

    /// What `connect` does to the document, as `StravaSession.connect` does: the new record
    /// replaces any earlier one.
    ///
    /// A success waits for `gate` before it writes. Otherwise the write could land while
    /// `send(.connectTapped)` is still running, and TestStore would expect it there, so whether
    /// the test passed would depend on timing. The stream buffers, so the test can open the gate
    /// before or after the script starts waiting.
    enum ConnectScript {
        case succeeds(ConnectedService, gate: AsyncStream<Void>)
        case fails(StravaAuthError)
    }

    /// Each store gets its own in-memory file system, seeded in the same scope (the
    /// `SettingsFeatureTests.makeStore` idiom). The scripted `connect` writes through the same
    /// `Shared`, as the live client writes the document the feature reads.
    private func makeStore(
        record: ConnectedService?,
        connect: ConnectScript = .fails(.cancelled),
        strava: StravaClient = .mock(athlete: ada),
        initialState: (inout AccountsFeature.State) -> Void = { _ in }
    ) -> TestStoreOf<AccountsFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.connectedServices = record.map { [$0] } ?? [] }
            var auth = StravaAuthClient.testValue
            auth.connect = { [preferences = $preferences] in
                switch connect {
                case .succeeds(let record, let gate):
                    for await _ in gate { break }
                    preferences.withLock { $0.connectedServices = [record] }
                    return record
                case .fails(let error):
                    throw error
                }
            }
            var state = AccountsFeature.State()
            initialState(&state)
            return TestStore(initialState: state) {
                AccountsFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
                $0.stravaAuth = auth
                $0.strava = strava
            }
        }
    }

    // MARK: - Appearing

    @Test("Appearing connected fetches the athlete's name and photo")
    func appearingConnectedFetchesAthlete() async {
        let store = makeStore(record: Self.record())

        await store.send(.task)
        await store.receive(\.athleteFetched) { $0.athlete = Self.ada }
    }

    @Test("Appearing with no account fetches nothing")
    func appearingNotConnectedFetchesNothing() async {
        let store = makeStore(record: nil)
        await store.send(.task)
    }

    /// Strava revoked access: the screen shows Connect, and a fetch would only be refused.
    @Test("Appearing with an account Strava revoked fetches nothing")
    func appearingDisconnectedFetchesNothing() async {
        let store = makeStore(record: Self.record(isDisconnected: true))
        #expect(store.state.account == nil)
        await store.send(.task)
    }

    @Test("A failed athlete fetch leaves the placeholder")
    func athleteFetchFailureKeepsPlaceholder() async {
        var strava = StravaClient.mock()
        strava.athlete = { throw URLError(.notConnectedToInternet) }
        let store = makeStore(record: Self.record(), strava: strava)

        await store.send(.task)
        await store.receive(\.athleteFetched)
        #expect(store.state.athlete == nil)
    }

    // MARK: - Connect

    @Test("Connecting saves the account and fetches the athlete")
    func connectSucceeds() async {
        let (gate, openGate) = AsyncStream.makeStream(of: Void.self)
        let store = makeStore(record: nil, connect: .succeeds(Self.record(), gate: gate))

        await store.send(.connectTapped) { $0.isConnecting = true }
        openGate.yield()
        await store.receive(\.connectFinished) {
            $0.isConnecting = false
            $0.$preferences.withLock { $0.connectedServices = [Self.record()] }
        }
        await store.receive(\.delegate.connected)
        await store.receive(\.athleteFetched) { $0.athlete = Self.ada }
        #expect(store.state.account == Self.record())
    }

    @Test("Closing sign-in, or declining on Strava, says nothing", arguments: [StravaAuthError.cancelled, .denied])
    func connectCancelled(error: StravaAuthError) async {
        let store = makeStore(record: nil, connect: .fails(error))

        await store.send(.connectTapped) { $0.isConnecting = true }
        await store.receive(\.connectFinished) { $0.isConnecting = false }
    }

    @Test("A failed connect says so")
    func connectFails() async {
        let store = makeStore(record: nil, connect: .fails(.tokenService(status: 502)))

        await store.send(.connectTapped) { $0.isConnecting = true }
        await store.receive(\.connectFinished) {
            $0.isConnecting = false
            $0.alert = .stravaConnectFailed
        }
    }

    @Test("A tap while sign-in is showing doesn't start another")
    func connectWhileConnectingIsIgnored() async {
        let store = makeStore(record: nil) { $0.isConnecting = true }
        await store.send(.connectTapped)
    }

    /// Reconnect is Connect: the new record replaces the one Strava revoked.
    @Test("Reconnecting replaces an account Strava revoked")
    func reconnectReplacesDisconnectedAccount() async {
        let (gate, openGate) = AsyncStream.makeStream(of: Void.self)
        let store = makeStore(record: Self.record(isDisconnected: true), connect: .succeeds(Self.record(), gate: gate))

        await store.send(.connectTapped) { $0.isConnecting = true }
        openGate.yield()
        await store.receive(\.connectFinished) {
            $0.isConnecting = false
            $0.$preferences.withLock { $0.connectedServices = [Self.record()] }
        }
        await store.receive(\.delegate.connected)
        await store.receive(\.athleteFetched) { $0.athlete = Self.ada }
    }

    /// From the Permissions section, after the rider unticked a scope.
    @Test("Reconnecting with every scope empties the Permissions section")
    func reconnectGrantsMissingScope() async {
        let (gate, openGate) = AsyncStream.makeStream(of: Void.self)
        let store = makeStore(record: Self.record(scopes: ["read", "read_all"]), connect: .succeeds(Self.record(), gate: gate))
        #expect(store.state.missingPermissions.map(\.scope) == ["activity:write", "activity:read_all"])

        await store.send(.connectTapped) { $0.isConnecting = true }
        openGate.yield()
        await store.receive(\.connectFinished) {
            $0.isConnecting = false
            $0.$preferences.withLock { $0.connectedServices = [Self.record()] }
        }
        await store.receive(\.delegate.connected)
        await store.receive(\.athleteFetched) { $0.athlete = Self.ada }
        #expect(store.state.missingPermissions.isEmpty)
    }

    // MARK: - Disconnect

    @Test("Confirming Disconnect hands it to Settings")
    func disconnectConfirmed() async {
        let store = makeStore(record: Self.record())

        await store.send(.disconnectTapped) { $0.alert = .confirmDisconnect }
        await store.send(.alert(.presented(.confirmDisconnect))) { $0.alert = nil }
        await store.receive(\.delegate.disconnectConfirmed)
    }

    @Test("Cancelling Disconnect keeps the account")
    func disconnectCancelled() async {
        let store = makeStore(record: Self.record())

        await store.send(.disconnectTapped) { $0.alert = .confirmDisconnect }
        await store.send(.alert(.dismiss)) { $0.alert = nil }
        #expect(store.state.account == Self.record())
    }

    // MARK: - Permissions

    @Test("Each unticked scope is named, in order; read and profile:read_all never are")
    func missingPermissions() {
        #expect(StravaPermission.missing(from: []).map(\.scope) == ["activity:write", "activity:read_all", "read_all"])
        #expect(StravaPermission.missing(from: ["read", "activity:read_all"]).map(\.scope) == ["activity:write", "read_all"])
        #expect(StravaPermission.missing(from: Set(StravaConfig.requestedScopes)).isEmpty)
    }

    /// A permission for a scope the app never asks for could never be granted by Reconnect.
    @Test("Every named permission is one the app requests")
    func permissionsAreRequested() {
        #expect(Set(StravaPermission.all.map(\.scope)).isSubset(of: Set(StravaConfig.requestedScopes)))
    }

    @Test("A revoked account names no permissions")
    func revokedAccountNamesNoPermissions() async {
        let store = makeStore(record: Self.record(scopes: ["read"], isDisconnected: true))
        #expect(store.state.missingPermissions.isEmpty)
    }
}
