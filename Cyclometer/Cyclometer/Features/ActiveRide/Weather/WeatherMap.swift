import MapKit
import SwiftUI

/// The wind map at the top of W10's sheet (#561).
///
/// - **Free ride:** W10's one reading drawn as an even field of arrows over whatever the map shows
///   (`WindSampling.field(in:)`). WeatherKit's wind barely changes across a few kilometres, so
///   sampling more points would spend requests on the same answer.
/// - **Following a route:** the route, and the forecast wind along it for when the rider gets there
///   (`RouteWindFeature`), W10's own reading where the rider is.
///
/// Opens on the rider at `riderSpanMeters` across, or on the whole route with the rider on it. The
/// rider can pan and zoom; the arrows keep their size in points (`measuresMapScale`).
struct WeatherMap: View {
    let metrics: WeatherMetrics

    /// Wide enough to read the wind's direction against roads, close enough to know where you are.
    static let riderSpanMeters = 5_000.0

    @State private var metersPerPoint: Double?
    /// What the camera shows; the free-ride field fills it, re-placed when the camera settles.
    @State private var visibleBounds: RouteBounds?

    var body: some View {
        MapReader { proxy in
            Map(initialPosition: .region(framing), interactionModes: [.pan, .zoom]) {
                if metrics.route.count > 1 {
                    RouteMapContent(coordinates: metrics.route)
                    WindLayer(samples: metrics.routeWind, metersPerPoint: metersPerPoint)
                } else if let reading = metrics.forecast?.current, let visibleBounds {
                    WindLayer(reading: reading, at: WindSampling.field(in: visibleBounds), metersPerPoint: metersPerPoint)
                }
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .measuresMapScale(proxy, into: $metersPerPoint)
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleBounds = RoutesMapCamera.bounds(for: context.region)
            }
        }
        // Seeded, as S20's map is: `.onMapCameraChange` isn't guaranteed to fire on the first settle.
        .onAppear { visibleBounds = RoutesMapCamera.bounds(for: framing) }
    }

    private var framing: MKCoordinateRegion {
        guard metrics.route.count > 1 else {
            let center = metrics.riderCoordinate ?? RouteCoordinate(RoutesMapCamera.fallbackCenter)
            return MKCoordinateRegion(center: center.coordinate2D,
                                      latitudinalMeters: Self.riderSpanMeters,
                                      longitudinalMeters: Self.riderSpanMeters)
        }
        let points = metrics.route + (metrics.riderCoordinate.map { [$0] } ?? [])
        return RoutesMapCamera.region(fitting: RouteGeometry.boundingBox(points))
    }
}

// MARK: - Previews

private extension WeatherMetrics {
    static let previewRider = RouteCoordinate(latitude: 37.3349, longitude: -122.0090, elevationMeters: nil)

    static let previewRoute: [RouteCoordinate] = (0...40).map { step in
        RouteCoordinate(latitude: 37.3349 + Double(step) * 0.004, longitude: -122.0090 + Double(step) * 0.002, elevationMeters: nil)
    }
}

#Preview("Free Ride") {
    WeatherMap(metrics: WeatherMetrics(forecast: .fixture, riderCoordinate: WeatherMetrics.previewRider))
        .frame(height: RouteDetailView.mapHeight)
}

#Preview("Route") {
    let route = WeatherMetrics.previewRoute
    WeatherMap(metrics: WeatherMetrics(
        forecast: .fixture,
        riderCoordinate: route[0],
        route: route,
        routeWind: [0, 13, 26, 40].enumerated().map { index, step in
            var reading = WeatherReading.fixtureHourly[index * 3]
            reading.windSpeed = Measurement(value: 8 + Double(index) * 8, unit: .kilometersPerHour)
            return WindSample(coordinate: route[step], reading: reading)
        }
    ))
    .frame(height: RouteDetailView.mapHeight)
}

#Preview("Route — Dark") {
    let route = WeatherMetrics.previewRoute
    WeatherMap(metrics: WeatherMetrics(
        forecast: .fixture,
        riderCoordinate: route[0],
        route: route,
        routeWind: [WindSample(coordinate: route[0], reading: .fixture),
                    WindSample(coordinate: route[40], reading: WeatherReading.fixtureHourly[6])]
    ))
    .frame(height: RouteDetailView.mapHeight)
    .preferredColorScheme(.dark)
}
