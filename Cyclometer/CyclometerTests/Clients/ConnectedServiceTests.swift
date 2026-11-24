import Foundation
import Security
import Testing
@testable import Cyclometer

/// The live Keychain behind a `ConnectedService` (DataModel.md §3.8, §10): its tokens go in under
/// the record's `keychainIdentifier` and come back by it. Each test uses an account of its own,
/// never `StravaConfig.keychainAccount`, so a run can't touch a real connection on the simulator.
@Suite("ConnectedService — Keychain")
struct ConnectedServiceTests {
    let keychain = KeychainClient.liveValue
    let account = "test-\(UUID().uuidString)"

    @Test("Tokens round-trip through the Keychain by the record's identifier")
    func roundTrip() throws {
        defer { try? keychain.delete(account) }
        let tokens = OAuthTokens(accessToken: "a1", refreshToken: "r1", expiresAt: Date(timeIntervalSince1970: 1_800_000_000))

        try keychain.write(account, JSONEncoder().encode(tokens))
        let data = try #require(try keychain.read(account))

        #expect(try JSONDecoder().decode(OAuthTokens.self, from: data) == tokens)
    }

    @Test("A second write replaces the item rather than failing on a duplicate")
    func writeReplaces() throws {
        defer { try? keychain.delete(account) }

        try keychain.write(account, Data("first".utf8))
        try keychain.write(account, Data("second".utf8))

        #expect(try keychain.read(account) == Data("second".utf8))
    }

    @Test("A missing item reads as nil, and deleting one is not an error")
    func missingItem() throws {
        #expect(try keychain.read(account) == nil)
        try keychain.delete(account)

        try keychain.write(account, Data("x".utf8))
        try keychain.delete(account)
        #expect(try keychain.read(account) == nil)
    }

    /// Never in a backup or on another device (PRD §8.12): a restored iPhone reconnects.
    @Test("The item is readable after first unlock, on this device only")
    func accessibility() throws {
        defer { try? keychain.delete(account) }
        try keychain.write(account, Data("x".utf8))

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainClient.service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        #expect(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
        let attributes = try #require(result as? [String: Any])
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }
}
