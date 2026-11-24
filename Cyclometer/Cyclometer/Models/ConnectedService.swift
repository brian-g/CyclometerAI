import Foundation

/// A connected third-party account (DataModel.md §3.8, PRD §8.12). A `Codable` value in the
/// AppPreferences document, following `PairedSensor` (#67), rather than the SwiftData `@Model`
/// §3.8 first sketched: one record per service, never queried, and owned by the document.
///
/// A record exists from connect until disconnect. Its OAuth tokens live in the Keychain under
/// `keychainIdentifier` and never touch the document, so they don't travel in a backup. The record
/// does (the document is in Documents, which is backed up), so on a restored or new iPhone it
/// arrives without its tokens: its writer, `StravaAuthClient` (#626), must treat a missing
/// Keychain item as `isDisconnected`, or S12 shows an account as connected that can't sign a
/// request, and the rider is never asked to reconnect.
///
/// Decoded by the synthesized decoder, which throws on a missing key, `isDisconnected`'s default
/// included. A field added later must be optional or decoded by hand, or every saved record fails
/// to decode and every rider is silently disconnected.
struct ConnectedService: Codable, Equatable, Sendable, Identifiable {
    /// One record per service (OQDM7).
    var id: ExternalService { serviceType }
    var serviceType: ExternalService
    /// The Keychain item's `kSecAttrAccount`.
    var keychainIdentifier: String
    /// Strava's athlete id; the routes endpoint needs it.
    var athleteID: String
    /// The athlete's name, shown on S12, S12.1 and S10.
    var accountDisplayName: String?
    /// The scopes the rider granted, from the OAuth callback. A feature whose scope is missing
    /// is hidden and named on S12.1 rather than failing (PRD §8.12).
    var grantedScopes: Set<String>
    var connectedAt: Date
    /// The service refused a refresh (the rider revoked access on its site), or the Keychain item
    /// is missing (a restored or new iPhone). S12.1 says so and offers Reconnect.
    var isDisconnected: Bool = false
}

/// A service a ride can sync to or an account can connect. Persisted by raw value in
/// `RideSyncRecord` and `ConnectedService`, so a new service is a new case and needs no migration;
/// never rename one.
enum ExternalService: String, Codable, Sendable, CaseIterable {
    case strava
    case rideWithGPS
    case tribosDotStudio
    case komoot
}

/// A row in S10's Sync To section: Apple Health or a connected service. The key of
/// `AppPreferences.syncDestinationDefaults`, the rider's last choice for each.
///
/// Stored as a string (`"appleHealth"`, or the service's raw value) rather than the synthesized
/// enum encoding, which would turn a dictionary keyed by it into an alternating `[key, value, …]`
/// array. As a string the map is a plain JSON object, and a destination this build doesn't know,
/// written by a newer one, is dropped alone instead of failing the whole map.
enum SyncDestination: Hashable, Sendable {
    case appleHealth
    case service(ExternalService)
}

extension SyncDestination: RawRepresentable, Codable, CodingKeyRepresentable {
    private static let appleHealthRawValue = "appleHealth"

    init?(rawValue: String) {
        if rawValue == Self.appleHealthRawValue {
            self = .appleHealth
        } else if let service = ExternalService(rawValue: rawValue) {
            self = .service(service)
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .appleHealth: Self.appleHealthRawValue
        case .service(let service): service.rawValue
        }
    }
}
