import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// W14 Ascent, W15 Descent, W16 Grade (1×1), W17 Elevation and W18 Route Elevation (2×1) (#387).
final class ElevationWidgetSnapshotTests: XCTestCase {

    // Grid slots: a 1×1 is half-width, a 2×1 full width, both one row of 96.
    private let oneByOne: SwiftUISnapshotLayout = .fixed(width: 196, height: 96)
    private let twoByOne: SwiftUISnapshotLayout = .fixed(width: 393, height: 96)
    private let history = AltitudeSample.sampleHour.map(\.meters)

    private func make(_ view: some View, width: CGFloat, scheme: ColorScheme = .light) -> some View {
        view
            .frame(width: width, height: 96)
            .preferredColorScheme(scheme)
    }

    private func assertDark(_ view: some View, width: CGFloat, layout: SwiftUISnapshotLayout,
                            file: StaticString = #filePath, testName: String = #function, line: UInt = #line) {
        assertSnapshot(
            of: make(view, width: width, scheme: .dark),
            as: .image(layout: layout, traits: .init(userInterfaceStyle: .dark)),
            file: file, testName: testName, line: line
        )
    }

    // MARK: - 1×1

    func testAscentMetric() {
        assertSnapshot(of: make(ElevationTotalWidget(title: "Ascent", meters: 412, unit: .metric), width: 196),
                       as: .image(layout: oneByOne))
    }

    func testAscentImperial() {
        assertSnapshot(of: make(ElevationTotalWidget(title: "Ascent", meters: 412, unit: .imperial), width: 196),
                       as: .image(layout: oneByOne))
    }

    func testDescentRideStart() {
        assertSnapshot(of: make(ElevationTotalWidget(title: "Descent", meters: 0, unit: .metric), width: 196),
                       as: .image(layout: oneByOne))
    }

    func testAscentDark() {
        assertDark(ElevationTotalWidget(title: "Ascent", meters: 412, unit: .metric), width: 196, layout: oneByOne)
    }

    func testGradeClimb() {
        assertSnapshot(of: make(GradeWidget(percent: 4.4), width: 196), as: .image(layout: oneByOne))
    }

    func testGradeDescent() {
        assertSnapshot(of: make(GradeWidget(percent: -7.6), width: 196), as: .image(layout: oneByOne))
    }

    func testGradeNoReading() {
        assertSnapshot(of: make(GradeWidget(percent: nil), width: 196), as: .image(layout: oneByOne))
    }

    // MARK: - W17

    func testElevationMetric() {
        assertSnapshot(
            of: make(ElevationWidget(altitude: 284, gradePercent: 4.4, history: history, unit: .metric), width: 393),
            as: .image(layout: twoByOne)
        )
    }

    func testElevationImperial() {
        assertSnapshot(
            of: make(ElevationWidget(altitude: 284, gradePercent: -3, history: history, unit: .imperial), width: 393),
            as: .image(layout: twoByOne)
        )
    }

    func testElevationNoReading() {
        assertSnapshot(
            of: make(ElevationWidget(altitude: nil, gradePercent: nil, history: [], unit: .metric), width: 393),
            as: .image(layout: twoByOne)
        )
    }

    func testElevationDark() {
        assertDark(ElevationWidget(altitude: 284, gradePercent: 4.4, history: history, unit: .metric),
                   width: 393, layout: twoByOne)
    }

    // MARK: - W18

    private func route(progress: Double?, profile: [Double]? = AltitudeSample.sampleHour.map(\.meters)) -> RouteElevationWidget {
        RouteElevationWidget(altitude: 284, gradePercent: 4.4, routeProfile: profile, routeProgress: progress,
                             history: history, unit: .metric)
    }

    func testRouteElevationOnRoute() {
        assertSnapshot(of: make(route(progress: 0.4), width: 393), as: .image(layout: twoByOne))
    }

    /// Turn-by-turn off: the route, with nothing marked ridden.
    func testRouteElevationNoProgress() {
        assertSnapshot(of: make(route(progress: nil), width: 393), as: .image(layout: twoByOne))
    }

    /// No route: W17's face.
    func testRouteElevationNoRoute() {
        assertSnapshot(of: make(route(progress: nil, profile: nil), width: 393), as: .image(layout: twoByOne))
    }

    func testRouteElevationDark() {
        assertDark(route(progress: 0.4), width: 393, layout: twoByOne)
    }
}
