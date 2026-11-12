import SwiftUI

// MARK: - Ride Weather Summary

/// What S15's weather block shows (#151): the ride's temperature and humidity ranges over the
/// conditions recorded during it, and how the wind met the rider. Built from plain values, so
/// the view never holds a store snapshot (lessons, #537).
struct RideWeatherSummary: Equatable {
    var samples: [RideWeatherSample]
    var exposure: RideWindExposure?

    /// The coldest to the warmest reading, in whole degrees of the locale's weather unit, as
    /// S05.1 and W10 quote it: "12–18 °C". One value when the range rounds flat. Nil with no
    /// samples.
    func temperature(in unit: UnitTemperature) -> MetricReading? {
        let degrees = samples.map {
            Measurement(value: $0.temperatureCelsius, unit: UnitTemperature.celsius).wholeDegrees(in: unit)
        }
        guard let low = degrees.min(), let high = degrees.max() else { return nil }
        let spokenHigh = Measurement(value: high, unit: unit).formatted(
            .measurement(width: .wide, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
        )
        return MetricReading(
            value: Self.range(low, high),
            unit: unit.symbol,
            spoken: low == high ? spokenHigh : "\(Self.whole(low)) to \(spokenHigh)"
        )
    }

    /// The driest to the most humid reading, in whole percent: "45–60 %". Nil with no samples.
    var humidity: MetricReading? {
        let percents = samples.map { ($0.humidity * Self.percentPerUnit).rounded() }
        guard let low = percents.min(), let high = percents.max() else { return nil }
        return MetricReading(
            value: Self.range(low, high),
            unit: "%",
            spoken: low == high ? "\(Self.whole(high)) percent" : "\(Self.whole(low)) to \(Self.whole(high)) percent"
        )
    }

    private static func range(_ low: Double, _ high: Double) -> String {
        low == high ? whole(high) : "\(whole(low))–\(whole(high))"
    }

    private static func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    private static let percentPerUnit = 100.0
}

/// A share of the ride's moving time as a reading: "40 %".
private func shareReading(_ percent: Int, name: String) -> MetricReading {
    MetricReading(value: "\(percent)", unit: "%", spoken: "\(percent) percent \(name)")
}

// MARK: - Ride Weather Section

/// S15's Weather section (#151), after Time: the temperature and humidity ranges, then a bar of the
/// ride's moving time into, across and with the wind, keyed by its shares. WeatherKit's mark and
/// legal link in the footer once the attribution loads.
struct RideWeatherSection: View {
    let summary: RideWeatherSummary
    let attribution: WeatherSourceAttribution?

    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            ReadingColumns {
                if let temperature = summary.temperature(in: UnitTemperature(forLocale: locale, usage: .weather)) {
                    ReadingColumn("Temperature", temperature)
                }
                if let humidity = summary.humidity {
                    ReadingColumn("Humidity", humidity)
                }
                if summary.exposure == .calm {
                    ReadingColumn("Wind", MetricReading(value: "Calm", spoken: "Calm"))
                }
            }
            if case let .shares(headwind, crosswind, tailwind) = summary.exposure {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    WindShareBar(shares: [
                        (headwind, RideWindShareColor.headwind),
                        (crosswind, RideWindShareColor.crosswind),
                        (tailwind, RideWindShareColor.tailwind),
                    ])
                    ReadingColumns {
                        ReadingColumn("Headwind", shareReading(headwind, name: "headwind")) {
                            ZoneDot(color: RideWindShareColor.headwind)
                        }
                        ReadingColumn("Crosswind", shareReading(crosswind, name: "crosswind")) {
                            ZoneDot(color: RideWindShareColor.crosswind)
                        }
                        ReadingColumn("Tailwind", shareReading(tailwind, name: "tailwind")) {
                            ZoneDot(color: RideWindShareColor.tailwind)
                        }
                    }
                }
            }
        } header: {
            Text("Weather")
        } footer: {
            if let attribution {
                WeatherAttributionFooter(attribution: attribution)
            }
        }
    }
}

/// The wind shares' colours: into the wind is the hard going, with it the easy.
private enum RideWindShareColor {
    static let headwind = Color.cyRatingBad
    static let crosswind = Color.cyRatingOkay
    static let tailwind = Color.cyRatingGood
}

/// The three shares end to end, each as wide as its share of the ride. A share of 0 takes no
/// room. Hidden from VoiceOver: the columns under it read the same numbers.
private struct WindShareBar: View {
    let shares: [(percent: Int, color: Color)]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(Array(shares.enumerated()), id: \.offset) { _, share in
                    share.color.frame(width: proxy.size.width * CGFloat(share.percent) / 100)
                }
            }
        }
        .frame(height: Spacing.sm)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

private struct RideWeatherSectionPreview: View {
    var samples: [RideWeatherSample] = RideWeatherSample.fixtureRide
    var exposure: RideWindExposure? = .shares(headwind: 40, crosswind: 25, tailwind: 35)

    var body: some View {
        List {
            RideWeatherSection(
                summary: RideWeatherSummary(samples: samples, exposure: exposure),
                attribution: .fixture
            )
        }
    }
}

#Preview("Full") {
    RideWeatherSectionPreview()
}

#Preview("Dark") {
    RideWeatherSectionPreview()
        .preferredColorScheme(.dark)
}

#Preview("Metric") {
    RideWeatherSectionPreview()
        .environment(\.locale, Locale(identifier: "en_GB"))
}

#Preview("Calm") {
    RideWeatherSectionPreview(exposure: .calm)
}

#Preview("No Wind (No Track)") {
    RideWeatherSectionPreview(exposure: nil)
}

#Preview("Single Capture") {
    RideWeatherSectionPreview(samples: [RideWeatherSample.fixtureRide[0]], exposure: .shares(headwind: 100, crosswind: 0, tailwind: 0))
}
