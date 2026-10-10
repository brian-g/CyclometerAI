import Charts
import SwiftUI

// MARK: - Grade

/// A grade as W16–W18 and the Elevation sheet show it (#387): signed whole percent, so a climb
/// reads "+4" and a descent "-3".
enum Grade {
    static let unit = "%"

    /// "+4", "-3", "0"; "—" with no grade yet.
    static func value(_ percent: Double?) -> String {
        guard let percent else { return "—" }
        return Int(percent.rounded()).formatted(.number.sign(strategy: .always(includingZero: false)))
    }

    /// "4 percent", "-3 percent"; "No reading" with no grade yet.
    static func spoken(_ percent: Double?) -> String {
        guard let percent else { return MetricReading.missing.spoken }
        return "\(Int(percent.rounded())) percent"
    }
}

// MARK: - W14 Ascent / W15 Descent

/// W14 Ascent and W15 Descent (#387): the ride's total climb or drop. Real at zero, as distance is.
struct ElevationTotalWidget: View {
    let title: String
    let meters: Double
    let unit: UnitSystem
    /// The Elevation sheet's data. A closure so the card never reads it; only the open sheet does,
    /// in its own body (#144).
    var metrics: () -> ElevationMetrics = { ElevationMetrics() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(title)
            HeroNumber(unit.elevation(fromMeters: meters), decimals: 0, unit: unit.elevationLabel)
                .heroNumberSize(.medium)
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.cyBgSecondary)
        .widgetDetail(label: title, value: accessibilityValue) {
            ElevationSheet(metrics: metrics)
        }
    }

    var accessibilityValue: String { unit.spokenElevation(fromMeters: meters) }
}

// MARK: - W16 Grade

/// W16 Grade (#387): the road's slope over the last `RouteTerrain.gradeWindowMeters` ridden.
struct GradeWidget: View {
    let percent: Double?
    var metrics: () -> ElevationMetrics = { ElevationMetrics() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(GradeDashboardWidget.title)
            HeroNumber(Grade.value(percent), unit: percent == nil ? "" : Grade.unit)
                .heroNumberSize(.medium)
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.cyBgSecondary)
        .widgetDetail(label: GradeDashboardWidget.title, value: accessibilityValue) {
            ElevationSheet(metrics: metrics)
        }
    }

    var accessibilityValue: String { Grade.spoken(percent) }
}

// MARK: - W17 Elevation

/// W17 Elevation (#387): where the rider is now and the grade under them, over the ride's elevation
/// as a watermark on Speed's axis — the ride so far, up to an hour.
struct ElevationWidget: View {
    let altitude: Double?       // meters; nil → "—"
    let gradePercent: Double?
    let history: [Double]       // meters, oldest first, for the watermark
    let unit: UnitSystem
    var metrics: () -> ElevationMetrics = { ElevationMetrics() }
    /// W18 shows this face without a route, and keeps its own title on it: the rider placed
    /// Route Elevation, and the card, VoiceOver and edit mode all name it so.
    var title = ElevationDashboardWidget.title

    var body: some View {
        ZStack {
            if !history.isEmpty {
                ElevationHistoryChart(history: history)
                    .opacity(Opacity.watermark)
            }
            ElevationReadout(
                title: title,
                altitude: altitude,
                gradePercent: gradePercent,
                unit: unit
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyBgSecondary)
        .widgetDetail(label: title, value: accessibilityValue) {
            ElevationSheet(metrics: metrics)
        }
    }

    var accessibilityValue: String {
        ElevationReadout.accessibilityValue(altitude: altitude, gradePercent: gradePercent, unit: unit)
    }
}

// MARK: - W18 Route Elevation

/// W18 Route Elevation (#387): the whole route's profile by distance, the part ridden darker than
/// the part ahead, under W17's readout. Without a route that has elevation it is W17's face, under
/// its own title.
struct RouteElevationWidget: View {
    let altitude: Double?
    let gradePercent: Double?
    /// `NavigationRoute.elevationProfile`; nil with no route, or one with no `<ele>`.
    let routeProfile: [Double]?
    /// How far along the route the rider is, 0–1; nil while navigation isn't placing them on it.
    let routeProgress: Double?
    /// W17's watermark, for a ride with no route profile.
    let history: [Double]
    let unit: UnitSystem
    var metrics: () -> ElevationMetrics = { ElevationMetrics() }

    var body: some View {
        if let routeProfile {
            ZStack {
                RouteProfileChart(profile: routeProfile, progress: routeProgress)
                ElevationReadout(
                    title: RouteElevationDashboardWidget.title,
                    altitude: altitude,
                    gradePercent: gradePercent,
                    unit: unit
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.cyBgSecondary)
            .widgetDetail(label: RouteElevationDashboardWidget.title, value: accessibilityValue) {
                ElevationSheet(metrics: metrics)
            }
        } else {
            ElevationWidget(
                altitude: altitude, gradePercent: gradePercent, history: history, unit: unit, metrics: metrics,
                title: RouteElevationDashboardWidget.title
            )
        }
    }

    var accessibilityValue: String {
        ElevationReadout.accessibilityValue(altitude: altitude, gradePercent: gradePercent, unit: unit)
    }
}

// MARK: - Shared readout

/// W17's and W18's face: elevation as the medium hero, grade as a small one on the right — the
/// Cadence 2×1 arrangement.
private struct ElevationReadout: View {
    let title: String
    let altitude: Double?
    let gradePercent: Double?
    let unit: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(title)
            HStack(alignment: .lastTextBaseline, spacing: Spacing.lg) {
                if let altitude {
                    HeroNumber(unit.elevation(fromMeters: altitude), decimals: 0, unit: unit.elevationLabel)
                        .heroNumberSize(.medium)
                } else {
                    HeroNumber("—", unit: "").heroNumberSize(.medium)
                }
                Spacer()
                HeroNumber(Grade.value(gradePercent), unit: gradePercent == nil ? "" : Grade.unit) {
                    Text("Grade").font(.caption)
                }
                .heroNumberSize(.small)
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// What VoiceOver reads after the title (#361): no "—" read aloud.
    static func accessibilityValue(altitude: Double?, gradePercent: Double?, unit: UnitSystem) -> String {
        var parts = [altitude.map { unit.spokenElevation(fromMeters: $0) } ?? MetricReading.missing.spoken]
        if gradePercent != nil { parts.append("grade \(Grade.spoken(gradePercent))") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Charts

extension Collection where Element == Double {
    /// Elevations' y-domain: the lowest up to the highest, but never less than
    /// `RouteGeometry.elevationNoiseThresholdMeters` tall — so a level ride's noise is drawn flat
    /// rather than stretched into hills, as the sheets' charts do.
    var elevationChartDomain: ClosedRange<Double> {
        let low = self.min() ?? 0
        return low...Swift.max(self.max() ?? low, low + RouteGeometry.elevationNoiseThresholdMeters)
    }
}

/// W17's watermark: Speed's area-and-line treatment, on the ride's elevation.
private struct ElevationHistoryChart: View {
    let history: [Double]   // meters

    var body: some View {
        let domain = history.elevationChartDomain
        Chart(Array(history.enumerated()), id: \.offset) { index, meters in
            AreaMark(
                x: .value("t", index),
                yStart: .value("base", domain.lowerBound),
                yEnd: .value("elevation", meters)
            )
            .foregroundStyle(Color.cyPrimary)
            LineMark(x: .value("t", index), y: .value("elevation", meters))
                .foregroundStyle(Color.cyPrimary)
        }
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        // A line along the top of the domain would otherwise draw over the cell above (#140).
        .clipped()
    }
}

/// A route's elevation profile by distance, the part ridden darker than the part ahead (#387). W18's
/// watermark, and the Elevation sheet's route chart.
struct RouteProfileChart: View {
    let profile: [Double]   // meters at even distances, start to finish
    let progress: Double?   // 0–1; nil → nothing ridden shown
    var showsAxis = false

    private struct Point: Identifiable {
        let index: Int
        let meters: Double
        let isRidden: Bool
        var id: String { "\(isRidden)-\(index)" }
    }

    /// Each sample once on its side of the rider, and the sample at the rider on both, so the two
    /// areas meet without a gap.
    private var points: [Point] {
        let split = progress.map { Int((min(max($0, 0), 1) * Double(profile.count - 1)).rounded()) } ?? -1
        return profile.enumerated().flatMap { index, meters in
            var points: [Point] = []
            if index <= split { points.append(Point(index: index, meters: meters, isRidden: true)) }
            if index >= split { points.append(Point(index: index, meters: meters, isRidden: false)) }
            return points
        }
    }

    var body: some View {
        let domain = profile.elevationChartDomain
        Chart(points) { point in
            AreaMark(
                x: .value("distance", point.index),
                yStart: .value("base", domain.lowerBound),
                yEnd: .value("elevation", point.meters),
                series: .value("part", point.isRidden ? "ridden" : "ahead")
            )
            .foregroundStyle(Color.cyPrimary.opacity(point.isRidden ? Opacity.lineWatermark : Opacity.watermark))
        }
        .chartYScale(domain: domain)
        .chartXScale(domain: 0...Swift.max(profile.count - 1, 1))
        .chartXAxis(.hidden)
        .chartYAxis(showsAxis ? .automatic : .hidden)
        .chartLegend(.hidden)
        .clipped()
    }
}

// MARK: - Previews

#Preview("W14–W16") {
    HStack(spacing: Spacing.xs) {
        ElevationTotalWidget(title: "Ascent", meters: 412, unit: .metric)
        GradeWidget(percent: 4.4)
    }
    .frame(height: 96)
}

#Preview("W17 / W18") {
    VStack(spacing: Spacing.xs) {
        ElevationWidget(altitude: 284, gradePercent: -3, history: AltitudeSample.sampleHour.map(\.meters), unit: .metric)
            .frame(height: 96)
        RouteElevationWidget(
            altitude: 284, gradePercent: 6, routeProfile: AltitudeSample.sampleHour.map(\.meters),
            routeProgress: 0.4, history: [], unit: .imperial
        )
        .frame(height: 96)
    }
}
