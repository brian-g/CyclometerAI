import XCTest
import SnapshotTesting
import SwiftUI
import ComposableArchitecture
@testable import Cyclometer

/// S12.1 Strava Account (#629), against Design.sketch "12.1 - Strava: not connected/disconnected
/// by strava" and "12.1 - Strava: connected", at the iPhone 17 Pro frame Sketch draws.
///
/// The athlete is seeded rather than fetched: a snapshot never awaits `.task`. With no photo URL,
/// the photo is its placeholder, so no reference depends on the network. The behaviour behind
/// these states belongs to `AccountsFeatureTests`.
///
/// Skipped in CI along with the other snapshot suites (see `.github/workflows/tests.yml`).
final class StravaAccountSnapshotTests: XCTestCase {

    /// Same device as `SettingsSnapshotTests`.
    private let device = ViewImageConfig(
        safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
        size: CGSize(width: 402, height: 874),
        traits: UITraitCollection { traits in
            traits.horizontalSizeClass = .compact
            traits.verticalSizeClass = .regular
            traits.displayScale = 3
        }
    )

    private static let connectedAt = Date(timeIntervalSince1970: 1_795_996_800)

    private static func record(
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

    private static let ada = StravaAthlete(name: "Ada Lovelace", photoURL: nil)

    // MARK: Harness

    /// Each store gets its own in-memory file system, seeded in the same scope. The Strava mock
    /// answers the athlete already seeded, so a `.task` that lands mid-render changes nothing.
    private func screen(record: ConnectedService?, athlete: StravaAthlete? = nil, uploads: [StravaWorkItem] = []) -> some View {
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.connectedServices = record.map { [$0] } ?? [] }
            var state = AccountsFeature.State()
            state.athlete = athlete
            state.fetchedUploads = uploads
            return Store(initialState: state) {
                AccountsFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
                $0.strava = .mock(athlete: athlete ?? StravaAthlete(name: nil, photoURL: nil))
                $0.stravaAuth = .testValue
                // Answers the uploads already seeded, for the athlete's reason.
                $0.persistenceClient = .mock(ridesWithStravaWork: uploads)
            }
        }
        return NavigationStack {
            AccountsView(store: store)
        }
        .tint(Color.cyPrimary)
        // "Connected since" is a date, and `connectedAt` is midnight UTC: unpinned, a machine east
        // of UTC (or a runner on UTC) records the next day. Chicago, as the other date-bearing suites.
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(identifier: "America/Chicago")!)
    }

    private func assertBothSchemes(
        _ view: some View,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        assertSnapshot(
            of: UIHostingController(rootView: view.preferredColorScheme(.light)),
            as: .image(on: device, traits: .snapshot()),
            named: "\(name)-light", file: file, testName: testName, line: line
        )
        assertSnapshot(
            of: UIHostingController(rootView: view.preferredColorScheme(.dark)),
            as: .image(on: device, traits: .snapshot(.dark)),
            named: "\(name)-dark", file: file, testName: testName, line: line
        )
    }

    // MARK: Tests

    /// Strava's Connect button alone, centred.
    func testStravaAccountNotConnected() {
        assertBothSchemes(screen(record: nil), named: "notConnected")
    }

    /// Strava revoked access: the same as not connected (UX §S12.1).
    func testStravaAccountDisconnectedByStrava() {
        assertBothSchemes(screen(record: Self.record(isDisconnected: true)), named: "disconnectedByStrava")
    }

    /// Name, photo placeholder, Connected since, Disconnect and Powered by Strava; every scope
    /// granted, so no Permissions section.
    func testStravaAccountConnected() {
        assertBothSchemes(screen(record: Self.record(), athlete: Self.ada), named: "connected")
    }

    /// The Uploads section (#632): one ride processing, one waiting offline, one failed with Retry.
    func testStravaAccountUploads() {
        let uploads = [
            StravaWorkItem(rideId: UUID(), title: "River hill loop",
                           record: RideSyncRecord(service: .strava, status: .processing, remoteUploadId: "1")),
            StravaWorkItem(rideId: UUID(), title: "Gnarly",
                           record: RideSyncRecord(service: .strava, status: .pending, errorMessage: SyncReason.offline)),
            StravaWorkItem(rideId: UUID(), title: "Gravel loop",
                           record: RideSyncRecord(service: .strava, status: .failed, errorMessage: "The file was empty.")),
        ]
        assertBothSchemes(screen(record: Self.record(), athlete: Self.ada, uploads: uploads), named: "uploads")
    }

    /// Before the athlete arrives, or offline: "Strava" in place of the name.
    func testStravaAccountConnectedBeforeName() {
        assertBothSchemes(screen(record: Self.record()), named: "connectedBeforeName")
    }

    /// The rider unticked uploads and private activities: Permissions names both, with Reconnect.
    func testStravaAccountScopesUnticked() {
        assertBothSchemes(
            screen(record: Self.record(scopes: ["read", "read_all", "profile:read_all"]), athlete: Self.ada),
            named: "scopesUnticked"
        )
    }
}
