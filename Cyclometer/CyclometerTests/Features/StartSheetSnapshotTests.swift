import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// S05.1 — the Start sheet's sensor rows.
///
/// Rows, not the whole sheet: `StartSheetView`'s toolbar renders blank inside a
/// `UIHostingController`, so a full-screen reference would be a white rectangle that can
/// never fail. Verified by ladder — a plain `NavigationStack`+`List` renders, and adding
/// the sheet's `.topBarLeading`/`.topBarTrailing` items blanks it.
///
/// What these pin is the change: a paired sensor the app is not connected to is listed
/// and shows its status, and no row carries a pairing action.
///
/// Skipped in CI with the other snapshot suites — references recorded against a local
/// simulator (see `.github/workflows/tests.yml`).
final class StartSheetSnapshotTests: XCTestCase {

    /// Full sheet width. `.sizeThatFits` would collapse the `List`.
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 402, height: 440)

    private func rows(_ sensors: [SensorRow]) -> some View {
        List {
            Section("Sensors") {
                ForEach(sensors) { SensorStatusRow(sensor: $0) }
            }
        }
        // Explicit rather than ambient, so the reference cannot silently encode whatever
        // the host bundle resolved at record time.
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

    /// Two up with battery, two paired and out of range. No row has an action.
    func testMixedConnectionStates() {
        assertBothSchemes(
            rows([
                SensorRow(kind: .radar, name: "Varia RTL515", status: .connected, batteryPercent: 84),
                SensorRow(kind: .heartRate, name: "Wahoo TICKR", status: .connected, batteryPercent: 14),
                SensorRow(kind: .speed, name: "Wahoo RPM", status: .searching),
                SensorRow(kind: .cadence, name: "Wahoo RPM", status: .searching)
            ]),
            named: "mixed"
        )
    }

    /// The sheet on open: paired, and the sheet's own scan still looking for them. The
    /// battery level is withheld with the connection it was read over.
    func testAllPairedNoneConnected() {
        assertBothSchemes(
            rows([
                SensorRow(kind: .radar, name: "Varia RTL515", status: .searching, batteryPercent: 84),
                SensorRow(kind: .heartRate, name: "Wahoo TICKR", status: .searching)
            ]),
            named: "allSearching"
        )
    }

    /// A record written before the peripheral advertised a name.
    func testUnnamedRecord() {
        assertBothSchemes(
            rows([SensorRow(kind: .cadence, name: nil, status: .searching)]),
            named: "unnamed"
        )
    }
}
