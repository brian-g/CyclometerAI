import ComposableArchitecture
import Foundation
import os
import Security

// Stream live: Console.app / Xcode console, filter subsystem "xyz.acmeapps.ride".
private let logger = Logger.cyclometer(.accounts)

/// TCA dependency for the iOS Keychain (TCA.md §4.15): one generic-password item per account,
/// holding a connected service's OAuth tokens (DataModel.md §3.8).
///
/// Items are `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: readable in the background
/// once the iPhone has been unlocked since boot, and never in a backup or on another device,
/// so a restored or new iPhone reconnects (PRD §8.12).
struct KeychainClient: Sendable {
    /// The item's data, or nil when there is none. Any other failure throws, notably reading
    /// before the first unlock since boot: that is not a missing item, and treating it as one
    /// would mark a working account disconnected.
    var read: @Sendable (_ account: String) throws -> Data?
    /// Replaces the item's data, adding the item when there is none.
    var write: @Sendable (_ account: String, _ data: Data) throws -> Void
    /// Removes the item. A missing item is not an error.
    var delete: @Sendable (_ account: String) throws -> Void
}

struct KeychainError: Error, Equatable {
    var status: OSStatus
    var operation: String
}

/// A connected service's tokens, JSON-encoded into its Keychain item (DataModel.md §3.8). Never
/// stored anywhere else.
struct OAuthTokens: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

extension KeychainClient: DependencyKey {
    /// `kSecAttrService` of every item the app writes, so its items never collide with another
    /// app's in a shared access group, and one query finds them all.
    static let service = "xyz.acmeapps.ride.oauth"

    static let liveValue = KeychainClient(
        read: { account in
            var query = baseQuery(account)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            switch status {
            case errSecSuccess:
                return result as? Data
            case errSecItemNotFound:
                return nil
            default:
                throw failure(status, "read")
            }
        },
        write: { account, data in
            // Update first, so a rewrite keeps the item's identity, then add when there is
            // none. The accessibility goes on both, so an item from an earlier build with a
            // different class is brought in line by its next write.
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            let updated = SecItemUpdate(baseQuery(account) as CFDictionary, attributes as CFDictionary)
            switch updated {
            case errSecSuccess:
                return
            case errSecItemNotFound:
                let added = SecItemAdd(baseQuery(account).merging(attributes) { $1 } as CFDictionary, nil)
                guard added == errSecSuccess else { throw failure(added, "add") }
            default:
                throw failure(updated, "update")
            }
        },
        delete: { account in
            let status = SecItemDelete(baseQuery(account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw failure(status, "delete")
            }
        }
    )

    /// A fresh in-memory Keychain per test, so no test sees another's items.
    static var testValue: KeychainClient { .inMemory() }
    static var previewValue: KeychainClient { .inMemory() }

    /// A Keychain held in memory. `items` lets a test seed or inspect it.
    static func inMemory(_ items: LockIsolated<[String: Data]> = LockIsolated([:])) -> KeychainClient {
        KeychainClient(
            read: { account in items.value[account] },
            write: { account, data in items.withValue { $0[account] = data } },
            delete: { account in items.withValue { $0[account] = nil } }
        )
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func failure(_ status: OSStatus, _ operation: String) -> KeychainError {
        logger.error("keychain \(operation, privacy: .public) failed: \(status, privacy: .public)")
        return KeychainError(status: status, operation: operation)
    }
}

extension DependencyValues {
    var keychain: KeychainClient {
        get { self[KeychainClient.self] }
        set { self[KeychainClient.self] = newValue }
    }
}
