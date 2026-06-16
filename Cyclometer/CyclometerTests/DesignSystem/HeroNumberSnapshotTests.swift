// Before this file can compile, add the swift-snapshot-testing package in Xcode:
//   File → Add Package Dependencies
//   URL: https://github.com/pointfreeco/swift-snapshot-testing
//   Version: up-to-next-major from 1.17.0
//   Add "SnapshotTesting" product to the CyclometerTests target

import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

final class HeroNumberSnapshotTests: XCTestCase {

    private func wrap(_ view: some View, scheme: ColorScheme = .light) -> some View {
        view
            .padding()
            .background(Color(.systemBackground))
            .preferredColorScheme(scheme)
            .environment(\.sizeCategory, .medium)
    }

    // MARK: - Light mode

    func testLargeLight() {
        assertSnapshot(
            of: wrap(HeroNumber(28.4, unit: "mph")),
            as: .image(layout: .sizeThatFits)
        )
    }

    func testMediumLight() {
        assertSnapshot(
            of: wrap(HeroNumber(28.4, unit: "mph").heroNumberSize(.medium)),
            as: .image(layout: .sizeThatFits)
        )
    }

    func testSmallLight() {
        assertSnapshot(
            of: wrap(HeroNumber(28.4, unit: "mph").heroNumberSize(.small)),
            as: .image(layout: .sizeThatFits)
        )
    }

    // MARK: - Dark mode

    func testLargeDark() {
        assertSnapshot(
            of: wrap(HeroNumber(28.4, unit: "mph"), scheme: .dark),
            as: .image(layout: .sizeThatFits)
        )
    }

    func testMediumDark() {
        assertSnapshot(
            of: wrap(HeroNumber(28.4, unit: "mph").heroNumberSize(.medium), scheme: .dark),
            as: .image(layout: .sizeThatFits)
        )
    }

    func testSmallDark() {
        assertSnapshot(
            of: wrap(HeroNumber(28.4, unit: "mph").heroNumberSize(.small), scheme: .dark),
            as: .image(layout: .sizeThatFits)
        )
    }

    // MARK: - Edge cases

    func testEmptyState() {
        assertSnapshot(
            of: wrap(HeroNumber("—", unit: "mph")),
            as: .image(layout: .sizeThatFits)
        )
    }

    func testCustomColor() {
        assertSnapshot(
            of: wrap(HeroNumber(28.4, unit: "mph").foregroundColor(.accentColor)),
            as: .image(layout: .sizeThatFits)
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
            as: .image(layout: .sizeThatFits)
        )
    }
}
