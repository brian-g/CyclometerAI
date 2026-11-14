import XCTest
import SnapshotTesting
import SwiftUI
@testable import Cyclometer

/// W10's sheet (#150): current conditions, the next hours and WeatherKit's attribution; and a ride
/// with no weather.
///
/// Renders `WeatherList` without the sheet's `NavigationStack`, as `ElevationSheetSnapshotTests`
/// does. The attribution's mark is an `AsyncImage`, which a snapshot can't load: the service's
/// name stands in, as on S05.1.
///
/// The wind map (#561) is a live `Map`, which can't be pixel-snapshotted reproducibly: a placeholder
/// of the same height takes its place, and the reference pins everything around it. What the map
/// draws is pinned by `WindSamplingTests` and `WindArrowGeometryTests`.
final class WeatherSheetSnapshotTests: XCTestCase {

    private let canvas: SwiftUISnapshotLayout = .fixed(width: 402, height: 600)

    private func makeList(_ metrics: WeatherMetrics, scheme: ColorScheme) -> some View {
        WeatherList(metrics: metrics, mapRow: Color.cyBgTertiary)
            .frame(width: 402, height: 600)
            // The temperature's unit and the strip's hours follow these.
            .environment(\.locale, Locale(identifier: "en_GB"))
            .environment(\.timeZone, TimeZone(identifier: "UTC")!)
            .preferredColorScheme(scheme)
    }

    private static let loaded = WeatherMetrics(
        forecast: .fixture,
        hours: AttributedForecast.fixture.hours(within: RideWeatherFeature.State.forecastWindow),
        now: WeatherReading.fixtureNow,
        course: 0
    )

    /// With a rider to centre on, the map tops the sheet (#561).
    private static let withMap: WeatherMetrics = {
        var metrics = loaded
        metrics.riderCoordinate = RouteCoordinate(latitude: 46.8772, longitude: -96.7898)
        return metrics
    }()

    // Named for this screen — reference PNGs are flat in the test bundle.

    func testWeatherSheetLoaded() {
        assertSnapshot(
            of: makeList(Self.loaded, scheme: .light),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .light))
        )
    }

    func testWeatherSheetLoadedDark() {
        assertSnapshot(
            of: makeList(Self.loaded, scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }

    func testWeatherSheetNoWeather() {
        assertSnapshot(
            of: makeList(WeatherMetrics(), scheme: .light),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .light))
        )
    }

    /// #204: nothing to show because the last request failed offline.
    func testWeatherSheetOffline() {
        assertSnapshot(
            of: makeList(WeatherMetrics(isOffline: true), scheme: .light),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .light))
        )
    }

    func testWeatherSheetWindMap() {
        assertSnapshot(
            of: makeList(Self.withMap, scheme: .light),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .light))
        )
    }

    func testWeatherSheetWindMapDark() {
        assertSnapshot(
            of: makeList(Self.withMap, scheme: .dark),
            as: .image(layout: canvas, traits: .init(userInterfaceStyle: .dark))
        )
    }
}
