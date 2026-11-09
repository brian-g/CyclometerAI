import XCTest
import SnapshotTesting
import SwiftUI
import ComposableArchitecture
@testable import Cyclometer

/// S05.1 — the Start sheet's rows — and S05.2, the Route picker it pushes (#196).
///
/// Rows, not the whole sheet: `StartSheetView`'s toolbar renders blank inside a
/// `UIHostingController`, so a full-screen reference would be a white rectangle that can
/// never fail. Verified by ladder — a plain `NavigationStack`+`List` renders, and adding
/// the sheet's `.topBarLeading`/`.topBarTrailing` items blanks it.
///
/// What the sensor cases pin is the change that introduced them: a paired sensor the app is
/// not connected to is listed and shows its status, and no row carries a pairing action.
///
/// Skipped in CI with the other snapshot suites — references recorded against a local
/// simulator (see `.github/workflows/tests.yml`).
final class StartSheetSnapshotTests: XCTestCase {

    /// Full sheet width. `.sizeThatFits` would collapse the `List`.
    private let canvas: SwiftUISnapshotLayout = .fixed(width: 402, height: 440)

    /// One Ride Setup row, under an empty navigation bar.
    private let routeRowCanvas: SwiftUISnapshotLayout = .fixed(width: 402, height: 200)

    /// The None section and all four preview routes.
    private let pickerCanvas: SwiftUISnapshotLayout = .fixed(width: 402, height: 600)

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

    /// `layout` defaults to `canvas`, the sensor rows' size.
    private func assertBothSchemes(
        _ view: some View,
        named name: String,
        layout: SwiftUISnapshotLayout? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let layout = layout ?? canvas
        assertSnapshot(
            of: view.preferredColorScheme(.light),
            as: .image(layout: layout),
            named: "\(name)-light", file: file, testName: testName, line: line
        )
        assertSnapshot(
            of: view.preferredColorScheme(.dark),
            as: .image(layout: layout, traits: .init(userInterfaceStyle: .dark)),
            named: "\(name)-dark", file: file, testName: testName, line: line
        )
    }

    // MARK: Sensors

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

    /// The last ride flagged two sensors (#391). The warning sits full width under its row,
    /// whatever the status — the searching one may be the dead cell — and a sensor reading
    /// 95% at rest still carries the low-battery warning its last ride earned.
    func testSensorWarnings() {
        assertBothSchemes(
            rows([
                SensorRow(kind: .radar, name: "Varia RTL515", status: .connected, batteryPercent: 84),
                SensorRow(kind: .speed, name: "Wahoo SPEED", status: .connected, batteryPercent: 95,
                          warning: .batteryLow),
                SensorRow(kind: .cadence, name: "Wahoo CADENCE", status: .searching,
                          warning: .linkUnreliable)
            ]),
            named: "warnings"
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

    // MARK: Weather (#149)

    /// The Weather group and its footer.
    private let weatherCanvas: SwiftUISnapshotLayout = .fixed(width: 402, height: 340)

    /// Pinned locale and time zone, so the hour labels and temperature unit don't follow the host.
    private func weather(
        _ weather: StartSheetWeather,
        hours: [WeatherReading] = [],
        unit: UnitSystem = .metric,
        locale: String = "en_GB"
    ) -> some View {
        List {
            StartSheetWeatherSection(weather: weather, hours: hours, unit: unit)
        }
        .tint(Color.cyPrimary)
        .environment(\.locale, Locale(identifier: locale))
        .environment(\.timeZone, TimeZone(identifier: "America/Chicago")!)
    }

    private static func loaded(_ current: WeatherReading = .fixture) -> StartSheetWeather {
        var forecast = StartSheetForecast.fixture
        forecast.current = current
        return .loaded(forecast)
    }

    /// No route: the hour under way and the next three. °C, km/h, a 24-hour clock. The footer
    /// shows the service's name, which stands in for the mark `AsyncImage` can't load here.
    func testStartSheetWeatherMetric() {
        assertBothSchemes(
            weather(Self.loaded(), hours: Array(WeatherReading.fixtureHourly.prefix(4))),
            named: "metric", layout: weatherCanvas
        )
    }

    /// A long route: more hours than fit, so the strip runs off the trailing edge. °F, mph, a
    /// 12-hour clock.
    func testStartSheetWeatherImperialLongRide() {
        assertBothSchemes(
            weather(Self.loaded(), hours: WeatherReading.fixtureHourly, unit: .imperial, locale: "en_US"),
            named: "imperial", layout: weatherCanvas
        )
    }

    /// An evening ride: clear and partly cloudy skies take their moon forms. The air is still, so the
    /// wind reads "Calm", with no arrow.
    func testStartSheetWeatherNight() {
        var current = WeatherReading.fixture
        current.condition = .clear
        current.isDaylight = false
        current.windSpeed = Measurement(value: 0.4, unit: .kilometersPerHour)
        let hours = WeatherReading.fixtureHourly.prefix(4).map {
            var hour = $0
            hour.isDaylight = false
            return hour
        }
        assertBothSchemes(weather(Self.loaded(current), hours: hours), named: "night", layout: weatherCanvas)
    }

    func testStartSheetWeatherLoading() {
        assertBothSchemes(weather(.loading), named: "loading", layout: weatherCanvas)
    }

    /// Location off for the app: says what would fix it. No attribution without WeatherKit data.
    func testStartSheetWeatherNoLocation() {
        assertBothSchemes(weather(.unavailable(.noLocation)), named: "noLocation", layout: weatherCanvas)
    }

    func testStartSheetWeatherFailed() {
        assertBothSchemes(weather(.unavailable(.failed)), named: "failed", layout: weatherCanvas)
    }

    // MARK: Route row (#196)

    /// The Route row inside a plain `NavigationLink`, so the reference carries a disclosure chevron.
    /// Plain rather than `NavigationLink(state:)`, which reports an issue — a failure under XCTest —
    /// outside a store-powered stack. The chevron is therefore this wrapper's: what the reference
    /// pins is the row's copy and truncation, not that the sheet's row is a link.
    private func routeRow(_ name: String?) -> some View {
        NavigationStack {
            List {
                Section("Ride Setup") {
                    NavigationLink {
                        EmptyView()
                    } label: {
                        ActiveRouteRow(routeName: name)
                    }
                }
            }
        }
        .tint(Color.cyPrimary)
    }

    /// No route chosen: a free ride.
    func testRouteRowNone() {
        assertBothSchemes(routeRow(nil), named: "none", layout: routeRowCanvas)
    }

    func testRouteRowChosen() {
        assertBothSchemes(routeRow(RouteSummary.previewRoutes[1].name), named: "chosen", layout: routeRowCanvas)
    }

    /// A route's name is whatever its GPX author typed. `LabeledContent` stacks the label over the
    /// value and cuts the value at the tail.
    func testRouteRowLongName() {
        assertBothSchemes(
            routeRow("Saturday Coffee Loop via the Old Quarry Road and Back Again"),
            named: "longName", layout: routeRowCanvas
        )
    }

    // MARK: Route picker (#196)

    /// S05.2's list, from a store seeded with the state `.task` would have produced. `RoutePickerList`
    /// never starts the read, so none can land mid-capture, and it has no navigation chrome — an inline
    /// title renders white offscreen. Imperial, as S19's references.
    private func picker(
        _ library: RoutePickerFeature.Library = .loaded(RouteSummary.previewRoutes),
        selection: RouteReference?
    ) -> some View {
        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.preferredUnit = .imperial }
            var state = RoutePickerFeature.State(selection: selection)
            state.library = library
            return Store(initialState: state) {
                RoutePickerFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
            }
        }
        return RoutePickerList(store: store)
            .tint(Color.cyPrimary)
    }

    func testPickerNoneChosen() {
        assertBothSchemes(picker(selection: nil), named: "none", layout: pickerCanvas)
    }

    /// "Summit Climb" checked. The distances stay one right-aligned column whichever row is chosen.
    func testPickerRouteChosen() {
        assertBothSchemes(
            picker(selection: RouteSummary.previewRoutes[1].reference),
            named: "chosen", layout: pickerCanvas
        )
    }

    func testPickerEmptyLibrary() {
        assertBothSchemes(picker(.loaded([]), selection: nil), named: "empty", layout: pickerCanvas)
    }

    /// A route seeded from S20 stays clearable: None is still offered when the read fails, beside the
    /// "Try Again" the failure's copy promises.
    func testPickerLoadFailed() {
        assertBothSchemes(
            picker(.failed, selection: RouteSummary.previewRoutes[1].reference),
            named: "failed", layout: pickerCanvas
        )
    }
}
