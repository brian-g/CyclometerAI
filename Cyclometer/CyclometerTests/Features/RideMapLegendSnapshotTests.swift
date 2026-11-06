import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// The S15 map sheet's route-coloring legend (#537), by coloring, at phone width. The map
/// behind it is never snapshotted (a live `Map` can't be pinned), so it sits on a flat tertiary
/// background; the colors' placement on the route is pinned by `RouteColoringTests`.
final class RideMapLegendSnapshotTests: XCTestCase {

    private static let width: CGFloat = 402
    private let canvas: SwiftUISnapshotLayout = .fixed(width: width, height: 120)
    private let zones = [60...123, 124...143, 144...162, 163...181, 182...200]

    /// A 5–10 m/s ride, so the speed bands are the ones `RouteColoringTests` works out.
    private var track: RideMapTrack {
        RideMapTrack(points: RideMapFixtures.points(count: 101, speed: { 5 + Double($0) * 0.05 }))
    }

    private func assertLegend(_ coloring: RouteColoring, unit: UnitSystem, scheme: ColorScheme,
                              testName: String = #function) {
        let scale = RouteColorScale(coloring: coloring, track: track, heartRateZones: zones, cadenceZones: .default)
        assertSnapshot(
            of: ZStack {
                Color.cyBgTertiary
                RideMapLegend(coloring: coloring, unit: scale.legendUnit(unit), entries: scale.legend(unit))
                    .padding(.horizontal, Spacing.lg)
            }
            .frame(width: Self.width, height: 120)
            .environment(\.locale, Locale(identifier: "en_US"))
            .preferredColorScheme(scheme),
            // Glass composites against a real window; offscreen, it isn't drawn.
            as: .image(drawHierarchyInKeyWindow: true, layout: canvas,
                       traits: .init(userInterfaceStyle: scheme == .dark ? .dark : .light)),
            testName: testName
        )
    }

    // Named for this screen — reference PNGs are flat in the test bundle.

    func testRideMapLegendSpeed() { assertLegend(.speed, unit: .imperial, scheme: .light) }
    func testRideMapLegendSpeedMetricDark() { assertLegend(.speed, unit: .metric, scheme: .dark) }
    func testRideMapLegendGrade() { assertLegend(.grade, unit: .imperial, scheme: .light) }
    func testRideMapLegendGradeDark() { assertLegend(.grade, unit: .imperial, scheme: .dark) }
    func testRideMapLegendCadence() { assertLegend(.cadence, unit: .imperial, scheme: .light) }
    func testRideMapLegendCadenceDark() { assertLegend(.cadence, unit: .imperial, scheme: .dark) }
    func testRideMapLegendHeartRate() { assertLegend(.heartRate, unit: .imperial, scheme: .light) }
    func testRideMapLegendHeartRateDark() { assertLegend(.heartRate, unit: .imperial, scheme: .dark) }
}
