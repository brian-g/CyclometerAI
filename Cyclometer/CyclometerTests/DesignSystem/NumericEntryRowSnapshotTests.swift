import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// `NumericEntryRow` (#439) in a `Form`, as S12 shows it. The screen around it stays with
/// `SettingsSnapshotTests`; these pin the row's own states.
final class NumericEntryRowSnapshotTests: XCTestCase {

    /// The width `Design.sketch` draws every screen at, and tall enough for the error caption
    /// under the field.
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 402, height: 160)

    private func row(_ row: NumericEntryRow) -> some View {
        Form { row }
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
            of: view.preferredColorScheme(.light),
            as: .image(layout: canvas),
            named: "\(name)-light", file: file, testName: testName, line: line
        )
        assertSnapshot(
            of: view.preferredColorScheme(.dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark)),
            named: "\(name)-dark", file: file, testName: testName, line: line
        )
    }

    /// Nothing typed: the field shows its placeholder, as an HR override does with none set.
    func testNumericEntryRowPlaceholder() {
        assertBothSchemes(
            row(NumericEntryRow("Resting HR", text: .constant(""), placeholder: "60", unit: "bpm") {}),
            named: "placeholder"
        )
    }

    /// An in-range entry: no caption.
    func testNumericEntryRowValid() {
        assertBothSchemes(
            row(NumericEntryRow("Circumference", text: .constant("2140"), placeholder: "mm", unit: "mm") {}),
            named: "valid"
        )
    }

    /// An out-of-range entry: the caption under the field, in `cyRatingBad` (#429). The
    /// wheel message is a `LocalizedStringResource`, so it wraps the same on every host (#430).
    func testNumericEntryRowError() {
        assertBothSchemes(
            row(NumericEntryRow(
                "Circumference", text: .constant("900"), placeholder: "mm", unit: "mm",
                errorMessage: Text(WheelPreset.outOfRangeMessage)
            ) {}),
            named: "error"
        )
    }
}
