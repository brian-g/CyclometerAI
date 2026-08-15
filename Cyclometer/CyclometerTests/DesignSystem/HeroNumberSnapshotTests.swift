import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

final class HeroNumberSnapshotTests: XCTestCase {

    private func wrap(
        _ view: some View,
        scheme: ColorScheme = .light,
        sizeCategory: ContentSizeCategory = .medium
    ) -> some View {
        view
            .padding()
            .background(Color(.systemBackground))
            .preferredColorScheme(scheme)
            .environment(\.sizeCategory, sizeCategory)
    }

    // `.sizeThatFits` mis-measures bare SwiftUI views on this simulator/library
    // combination, collapsing the snapshot to a near-empty crop. Fixed canvases
    // render correctly and are generous enough to never clip any size variant.
    private let horizontalCanvas: SwiftUISnapshotLayout = .fixed(width: 400, height: 220)
    private let verticalCanvas: SwiftUISnapshotLayout = .fixed(width: 200, height: 220)
    private let accessibilityCanvas: SwiftUISnapshotLayout = .fixed(width: 500, height: 320)

    // MARK: - Light mode

    func testLargeLight() {
        assertSnapshot(
            of: wrap(HeroNumber(28.4, unit: "mph")),
            as: .image(layout: horizontalCanvas)
        )
    }

    func testMediumLight() {
        assertSnapshot(
            of: wrap(HeroNumber(28.4, unit: "mph").heroNumberSize(.medium)),
            as: .image(layout: horizontalCanvas)
        )
    }

    func testSmallLight() {
        assertSnapshot(
            of: wrap(HeroNumber(28.4, unit: "mph").heroNumberSize(.small)),
            as: .image(layout: horizontalCanvas)
        )
    }

    // MARK: - Dark mode

    func testLargeDark() {
        assertSnapshot(
            of: wrap(HeroNumber(28.4, unit: "mph"), scheme: .dark),
            as: .image(layout: horizontalCanvas, traits: .init(userInterfaceStyle: .dark))
        )
    }

    func testMediumDark() {
        assertSnapshot(
            of: wrap(HeroNumber(28.4, unit: "mph").heroNumberSize(.medium), scheme: .dark),
            as: .image(layout: horizontalCanvas, traits: .init(userInterfaceStyle: .dark))
        )
    }

    func testSmallDark() {
        assertSnapshot(
            of: wrap(HeroNumber(28.4, unit: "mph").heroNumberSize(.small), scheme: .dark),
            as: .image(layout: horizontalCanvas, traits: .init(userInterfaceStyle: .dark))
        )
    }

    // MARK: - Edge cases

    func testEmptyState() {
        assertSnapshot(
            of: wrap(HeroNumber("—", unit: "mph")),
            as: .image(layout: horizontalCanvas)
        )
    }

    // Deliberately a design-system token rather than `.accentColor`. The accent
    // resolves against the host bundle's asset catalog, where `AccentColor` is
    // currently pure white — so this rendered white on `systemBackground` and
    // asserted an invisible number against a reference recorded back when the
    // accent was still the SwiftUI default blue. What the modifier is for is
    // overriding the default `.primary`, and a fixed token tests that without
    // depending on an ambient value no caller here passes.
    func testCustomColor() {
        assertSnapshot(
            of: wrap(HeroNumber(28.4, unit: "mph").valueColor(.cyPrimary)),
            as: .image(layout: horizontalCanvas)
        )
    }

    func testVerticalLayout() {
        assertSnapshot(
            of: wrap(
                HeroNumber(28.4, unit: "avg") {
                    Text("AVG").font(.caption)
                }
                .heroNumberSize(.small)
                .layout(.vertical)
            ),
            as: .image(layout: verticalCanvas)
        )
    }

    func testVerticalLayoutLarge() {
        assertSnapshot(
            of: wrap(
                HeroNumber(28.4, unit: "avg") {
                    Text("AVG").font(.caption)
                }
                .layout(.vertical)
            ),
            as: .image(layout: verticalCanvas)
        )
    }

    // MARK: - Dynamic Type

    func testLargeAccessibilityDynamicType() {
        assertSnapshot(
            of: wrap(HeroNumber(28.4, unit: "mph"), sizeCategory: .accessibilityExtraExtraExtraLarge),
            as: .image(layout: accessibilityCanvas)
        )
    }
}
