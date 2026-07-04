import XCTest
import SnapshotTesting
import SwiftUI
import ComposableArchitecture
@testable import Cyclometer

final class StartSheetSnapshotTests: XCTestCase {

    // Full-screen iPhone 17 Pro canvas (logical points).
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 393, height: 852)

    private func makeSheet(scheme: ColorScheme = .light) -> some View {
        StartSheetView(
            store: Store(
                initialState: StartSheetFeature.State(
                    sensors: [
                        SensorRow(kind: .radar, name: "Varia RTL515", status: .connected, batteryPercent: 82),
                        SensorRow(kind: .heartRate, name: "HRM-Dual", status: .connected),
                        SensorRow(kind: .speed, status: .searching),
                        SensorRow(kind: .cadence, status: .notPaired)
                    ]
                )
            ) {
                StartSheetFeature()
            }
        )
        .frame(width: 393, height: 852)
        .preferredColorScheme(scheme)
    }

    func testStartSheetLight() {
        assertSnapshot(of: makeSheet(), as: .image(layout: canvas))
    }

    func testStartSheetDark() {
        assertSnapshot(
            of: makeSheet(scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }
}
