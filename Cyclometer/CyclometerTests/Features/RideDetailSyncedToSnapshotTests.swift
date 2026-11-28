import XCTest
import SnapshotTesting
import SwiftUI
import ComposableArchitecture
@testable import Cyclometer

/// S15's Synced To row (#632), each state rendered from a `RideSyncRecord` fixture through
/// `RideDetailFeature.State.syncedTo`, so a reference shows what the reducer decides, not a
/// hand-built row. Design.sketch — S15 - Ride Detail (Alternative) draws only the synced state;
/// the others are UX §S15's.
///
/// The row alone, in an inset-grouped list as S15 draws its cards: the rest of S15 is
/// `RideDetailSnapshotTests`'.
///
/// An unfilled capsule's outline shows a short bar at each end in these references. That's the
/// layer renderer's: drawn in a key window, as the screen draws it, the outline is clean (checked
/// for #632). Not drawn that way here, for the cold-start race key-window snapshots have.
///
/// Skipped in CI along with the other snapshot suites (see `.github/workflows/tests.yml`).
final class RideDetailSyncedToSnapshotTests: XCTestCase {

    private let device = ViewImageConfig(
        safeArea: .zero,
        size: CGSize(width: 402, height: 220),
        traits: UITraitCollection { traits in
            traits.horizontalSizeClass = .compact
            traits.verticalSizeClass = .regular
            traits.displayScale = 3
        }
    )

    private static let summary = RideListSummary(
        id: UUID(), title: "River Loop", startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        distanceMeters: 36_050, durationSeconds: 4_712
    )

    private static let account = ConnectedService(
        serviceType: .strava, keychainIdentifier: StravaConfig.keychainAccount, athleteID: "1",
        grantedScopes: Set(StravaConfig.requestedScopes), connectedAt: .distantPast
    )

    // MARK: Harness

    /// The row for a ride with `record` on Strava and `presence` in Health.
    private func row(
        _ record: RideSyncRecord?,
        presence: HealthWorkoutPresence = .absent,
        connected: Bool = true,
        isStravaActivityDeleted: Bool = false
    ) -> some View {
        let syncedTo = withDependencies {
            $0.defaultFileStorage = .inMemory
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = RideDetailFeature.State(summary: Self.summary)
            state.$preferences.withLock { $0.connectedServices = connected ? [Self.account] : [] }
            state.stats = RideStats(averageSpeedMPS: 6, maxSpeedMPS: 11, stravaRecord: record)
            state.healthPresence = presence
            state.isStravaActivityDeleted = isStravaActivityDeleted
            return state.syncedTo
        }
        return List {
            if let syncedTo {
                SyncedToSection(syncedTo: syncedTo, tap: { _ in }, retry: {})
            }
        }
        .tint(Color.cyPrimary)
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
            as: .image(on: device, traits: .snapshot(.light)),
            named: "\(name)-light", file: file, testName: testName, line: line
        )
        assertSnapshot(
            of: UIHostingController(rootView: view.preferredColorScheme(.dark)),
            as: .image(on: device, traits: .snapshot(.dark)),
            named: "\(name)-dark", file: file, testName: testName, line: line
        )
    }

    // MARK: Tests
    //
    // Named for this screen — reference PNGs are flat in the test bundle.

    /// Sent to both, as Sketch draws it.
    func testRideDetailSyncedToSynced() {
        assertBothSchemes(row(RideSyncRecord(service: .strava, status: .synced, remoteActivityId: "987"), presence: .ours),
                          named: "synced")
    }

    /// Never sent, Strava connected: both grey.
    func testRideDetailSyncedToNeverSent() {
        assertBothSchemes(row(nil), named: "neverSent")
    }

    /// On its way: drawn sent, with no progress (S12.1 shows that).
    func testRideDetailSyncedToProcessing() {
        assertBothSchemes(row(RideSyncRecord(service: .strava, status: .processing, remoteUploadId: "1"), presence: .ours),
                          named: "processing")
    }

    /// Failed: Strava grey, its reason and Retry on the line under the capsules.
    func testRideDetailSyncedToFailed() {
        assertBothSchemes(row(RideSyncRecord(service: .strava, status: .failed, errorMessage: "Strava refused the upload (HTTP 400)"),
                              presence: .ours),
                          named: "failed")
    }

    /// The activity was deleted on Strava: the record is gone, and the line says how to send it again.
    func testRideDetailSyncedToDeletedOnStrava() {
        assertBothSchemes(row(nil, presence: .ours, isStravaActivityDeleted: true), named: "deletedOnStrava")
    }

    /// In Health by an Apple Watch's workout, Strava not connected: Apple Health alone, filled.
    func testRideDetailSyncedToHealthOnly() {
        assertBothSchemes(row(nil, presence: .otherSource, connected: false), named: "healthOnly")
    }

    /// The largest accessibility size: the capsules drop under the label rather than clip.
    func testRideDetailSyncedToAccessibilitySize() {
        let view = row(RideSyncRecord(service: .strava, status: .failed, errorMessage: "The file was empty."), presence: .ours)
        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: ViewImageConfig(safeArea: .zero, size: CGSize(width: 402, height: 420), traits: device.traits),
                       traits: .snapshot { $0.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge }),
            named: "failed-axxxl"
        )
    }
}
