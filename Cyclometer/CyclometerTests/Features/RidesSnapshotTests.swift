import XCTest
import SnapshotTesting
import SwiftUI
import ComposableArchitecture
@testable import Cyclometer

/// S14 — Ride History, at the width `Design.sketch` draws the frame at (#248).
///
/// Thumbnails are stand-in images drawn from `cy*` tokens, not real map snapshots: those need
/// map tiles from the network and wouldn't reproduce between runs. What's pinned here is the
/// row around the image — its frame, rounding, and the placeholder when there isn't one.
///
/// Skipped in CI along with the other snapshot suites — the references were recorded
/// against a local simulator (see `.github/workflows/tests.yml`).
@MainActor
final class RidesSnapshotTests: XCTestCase {

    /// The iPhone 17 Pro, as in `RoutesSnapshotTests`: a device config rather than a bare
    /// `.fixed` canvas, so the large title takes its margin from the window.
    private let device = ViewImageConfig(
        safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
        size: CGSize(width: 402, height: 874),
        traits: UITraitCollection(traitsFrom: [
            UITraitCollection(horizontalSizeClass: .compact),
            UITraitCollection(verticalSizeClass: .regular),
            UITraitCollection(displayScale: 3)
        ])
    )

    /// Wednesday 23 September 2026, noon, in whatever time zone the simulator is in. Built
    /// from components in the current calendar, as every ride date below is, so the row text
    /// comes out the same wherever the suite runs.
    private static let now = localDate(2026, 9, 23, 12, 0)

    private static func localDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: Fixtures

    /// A stand-in for a stored thumbnail: a trace in `cyMapTravelPath` over `cyBgSecondary`,
    /// each resolved for the appearance it stands in for, like the real capture.
    private static func thumbnail(_ style: UIUserInterfaceStyle) -> UIImage {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let size = CGSize(width: Spacing.rideThumbnail, height: Spacing.rideThumbnail)
        let format = UIGraphicsImageRendererFormat()
        format.scale = RideMapThumbnail.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(Color.cyBgSecondary).resolvedColor(with: traits).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 10, y: 44))
            path.addLine(to: CGPoint(x: 22, y: 14))
            path.addLine(to: CGPoint(x: 40, y: 30))
            path.addLine(to: CGPoint(x: 46, y: 10))
            path.lineWidth = Spacing.strokeMapThumbnail
            UIColor(Color.cyMapTravelPath).resolvedColor(with: traits).setStroke()
            path.stroke()
        }
    }

    /// One of each date form, and the row's two edge cases: no thumbnail (a ride from before
    /// #177, or with no GPS track) and no title yet (#249's rename field hasn't shipped).
    private static let rides: [RideListSummary] = [
        RideListSummary(id: UUID(), title: "All Around the Bush", startedAt: localDate(2026, 9, 23, 7, 45),
                        distanceMeters: 22_370, durationSeconds: 2_721),
        RideListSummary(id: UUID(), title: "River hill loop", startedAt: localDate(2026, 9, 22, 14, 5),
                        distanceMeters: 36_050, durationSeconds: 4_712),
        RideListSummary(id: UUID(), title: "", startedAt: localDate(2026, 9, 20, 9, 10),
                        distanceMeters: 8_047, durationSeconds: 1_260),
        RideListSummary(id: UUID(), title: "Door County Century Weekend Ride", startedAt: localDate(2025, 8, 30, 6, 30),
                        distanceMeters: 161_000, durationSeconds: 21_845)
    ]

    /// Every row's image as already loaded, except the third, which has none.
    private static var thumbnails: [UUID: RidesFeature.Thumbnail] {
        let images = RideThumbnailImages(light: thumbnail(.light), dark: thumbnail(.dark))
        return Dictionary(uniqueKeysWithValues: rides.enumerated().map { index, ride in
            (ride.id, index == 2 ? .missing : .loaded(images))
        })
    }

    // MARK: Harness

    /// Imperial, pinned through the S12 preference the row reads its units from.
    private func screen(rides: [RideListSummary]) -> some View {
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.preferredUnit = .imperial }
            // Seeded rather than left to `.task`: a snapshot never awaits an effect, and the
            // state worth pinning is the one after the first read.
            var state = RidesFeature.State()
            state.rides = rides
            // Seeded like the list: the rows' own reads are effects, never awaited here.
            state.thumbnails = Self.thumbnails.filter { id, _ in rides.contains { $0.id == id } }
            state.hasLoaded = true
            return Store(initialState: state) {
                RidesFeature()
            } withDependencies: {
                $0.persistenceClient = .mock(rides: rides)
                $0.defaultFileStorage = storage
            }
        }
        return NavigationStack {
            RidesView(store: store, onStartRide: {}, now: Self.now)
        }
        // Explicit rather than ambient: a reference recorded against whatever the host
        // bundle resolved would silently encode that instead of the token.
        .tint(Color.cyPrimary)
    }

    /// `testName` defaults to the *caller's* `#function`, so references are filed under the
    /// test that asked for them rather than under this helper.
    private func assertBothSchemes(
        _ view: some View,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        assertSnapshot(
            of: UIHostingController(rootView: view.preferredColorScheme(.light)),
            as: .image(on: device),
            named: "\(name)-light", file: file, testName: testName, line: line
        )
        assertSnapshot(
            of: UIHostingController(rootView: view.preferredColorScheme(.dark)),
            as: .image(on: device, traits: .init(userInterfaceStyle: .dark)),
            named: "\(name)-dark", file: file, testName: testName, line: line
        )
    }

    // MARK: Tests
    //
    // Named for this screen rather than `testEmptyState` like the sibling suites: every
    // reference PNG is copied flat into the test bundle, so a file name shared with
    // `RoutesSnapshotTests` fails the build with "Multiple commands produce".

    func testPopulatedRideHistory() {
        assertBothSchemes(screen(rides: Self.rides), named: "populated")
    }

    /// No rides yet: §S14's `ContentUnavailableView` and its Start New Ride action.
    func testEmptyRideHistory() {
        assertBothSchemes(screen(rides: []), named: "empty")
    }
}
