import Foundation

/// Rain on the route ahead (#152): the first place along it, where the rider is included, with at
/// least `RainOutlook.threshold` chance of precipitation in the hour the rider is expected to get
/// there. Only places reached within `RainOutlook.window` count, the same two hours W10 looks
/// ahead. The first wins, not the wettest, as in `RainOutlook`: the rider meets it first.
///
/// Each place is judged by its forecast for the hour containing the arrival, never by its current
/// conditions, which carry no chance of precipitation (`WeatherClient`).
struct RainAhead: Equatable, Sendable {
    /// Chance of precipitation in that hour, 0…1.
    var chance: Double
    /// The hour's sky, for its name and symbol. Nil for a condition a later SDK adds.
    var condition: WeatherCondition?
    var isDaylight: Bool
    /// How far along the route from the rider; 0 where the rider is.
    var distanceAheadMeters: Double
    /// When the rider is expected there.
    var arrival: Date

    /// Places nearer the rider than this along the route aren't asked about: they're where the
    /// rider is as far as the banner goes, and the rider's own forecast already answers for it.
    /// The banner reads "here" or a distance of at least a kilometre, never "0 m ahead".
    static let hereMeters = 1_000.0

    /// "Rain", "Snow", "Thunderstorms", as W10 names it.
    var name: String { RainOutlook.name(for: condition) }

    var symbolName: String { RainOutlook.symbolName(for: condition, isDaylight: isDaylight) }

    /// Wet where the rider is now.
    var isHere: Bool { distanceAheadMeters == 0 }

    /// The dashboard banner's line: "Rain 70% · 18.4 km ahead", or "Rain 70% · here". The distance
    /// reads as W9's does (`UnitSystem.turnDistance`), metres or feet close in.
    func bannerText(unitSystem: UnitSystem) -> String {
        guard !isHere else { return "\(name) \(percent) · here" }
        let distance = unitSystem.turnDistance(fromMeters: distanceAheadMeters)
        return "\(name) \(percent) · \(distance.value) \(distance.unit) ahead"
    }

    /// The banner as VoiceOver reads it (#568): "Rain, 70 percent chance, 18.4 kilometers ahead", or
    /// "…, here". Phrased as W10's rain (`WeatherWidgetView.accessibilityValue`), with the distance
    /// in words (`UnitSystem.spokenTurnDistance`) so no unit symbol or "·" is read as written.
    func spokenText(unitSystem: UnitSystem) -> String {
        let place = isHere ? "here" : "\(unitSystem.spokenTurnDistance(fromMeters: distanceAheadMeters)) ahead"
        return "\(name), \(percent) chance, \(place)"
    }

    /// "70%": VoiceOver reads the sign as "percent".
    private var percent: String { chance.formatted(.percent.precision(.fractionLength(0))) }
}

// In an extension, so the struct keeps its synthesized memberwise initialiser.
extension RainAhead {
    /// Nil when no place reached within the window is wet. `rider` is the forecast where the rider
    /// is, timed now; `ahead` is the route ahead in order.
    init?(rider: PointForecast, ahead: [PointForecast]) {
        let latest = rider.point.arrival.addingTimeInterval(RainOutlook.window)
        for answer in [rider] + ahead where answer.point.arrival <= latest {
            guard let hour = AttributedForecast.hour(containing: answer.point.arrival, in: answer.forecast.hourly),
                  let chance = hour.precipitationChance, chance >= RainOutlook.threshold
            else { continue }
            self.chance = chance
            condition = hour.condition
            isDaylight = hour.isDaylight
            distanceAheadMeters = max(answer.point.distanceMeters - rider.point.distanceMeters, 0)
            arrival = answer.point.arrival
            return
        }
        return nil
    }
}
