import MapKit
import SwiftUI

/// The wind map's layer (#561): an arrow at each sample, pointing the way the wind blows, longer
/// for a stronger wind. Static; animation is a later issue.
///
/// One `MapContent` for every map that shows the wind: W10's sheet, around the rider or along the
/// route, and S20's route map. The samples are worked out elsewhere (`WindSampling`,
/// `RouteWindFeature`), and the arrow's shape in `WindArrowGeometry`, where tests reach it.
///
/// `MapPolygon`s on the map plane, as `RouteDirectionArrows` are (#341): overlays draw beneath the
/// rider's location dot, and lying flat they turn with a heading-up camera. In the text colour with
/// a background-coloured edge, so an arrow reads over map tiles in either scheme and is never
/// taken for the route's own `cyPrimary` arrows.
struct WindLayer: MapContent {
    let samples: [WindSample]
    /// What one screen point covers on the ground, from `measuresMapScale`. Nil, before the map
    /// has been measured, draws nothing.
    let metersPerPoint: Double?

    static let edgeWidth: CGFloat = 1

    @MapContentBuilder
    var body: some MapContent {
        if let metersPerPoint {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                if let polygon = WindArrowGeometry.polygon(
                    center: sample.coordinate,
                    windFromDegrees: sample.reading.windDirection.converted(to: .degrees).value,
                    speedMPS: sample.reading.windSpeed.converted(to: .metersPerSecond).value,
                    metersPerPoint: metersPerPoint
                ) {
                    MapPolygon(coordinates: polygon.map(\.coordinate2D))
                        .foregroundStyle(Color.cyTextPrimary)
                        .stroke(Color.cyBgPrimary, lineWidth: Self.edgeWidth)
                }
            }
        }
    }
}

extension WindLayer {
    /// The no-route field (W10's sheet): W10's one reading at each of `positions`.
    init(reading: WeatherReading, at positions: [RouteCoordinate], metersPerPoint: Double?) {
        self.init(samples: positions.map { WindSample(coordinate: $0, reading: reading) }, metersPerPoint: metersPerPoint)
    }
}
