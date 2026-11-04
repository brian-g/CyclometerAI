import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// #461 — W20 ETA, on a fixed clock: 15:42 UTC, in a US locale on its 12- or 24-hour cycle.
final class ETAWidgetSnapshotTests: XCTestCase {

    // Grid slot a 1×1 receives: half-width single row, 196×96.
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 196, height: 96)

    private let afternoon = Date(timeIntervalSince1970: 15 * 3_600 + 42 * 60)

    private func makeETA(
        arrival: Date?,
        hourCycle: Locale.HourCycle = .oneToTwelve,
        scheme: ColorScheme = .light
    ) -> some View {
        var components = Locale.Components(identifier: "en_US")
        components.hourCycle = hourCycle
        return ETAWidget(arrival: arrival)
            .frame(width: 196, height: 96)
            .environment(\.locale, Locale(components: components))
            .environment(\.timeZone, TimeZone(identifier: "UTC")!)
            .preferredColorScheme(scheme)
    }

    func testETATwelveHour() {
        assertSnapshot(of: makeETA(arrival: afternoon), as: .image(layout: canvas))
    }

    func testETATwentyFourHour() {
        assertSnapshot(of: makeETA(arrival: afternoon, hourCycle: .zeroToTwentyThree), as: .image(layout: canvas))
    }

    /// No route, no moving average yet, and a complete route all read the same "—".
    func testETANoArrival() {
        assertSnapshot(of: makeETA(arrival: nil), as: .image(layout: canvas))
    }

    func testETATwelveHourDark() {
        assertSnapshot(
            of: makeETA(arrival: afternoon, scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }

    func testETANoArrivalDark() {
        assertSnapshot(
            of: makeETA(arrival: nil, scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }
}
