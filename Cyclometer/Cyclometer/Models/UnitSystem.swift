import Foundation

/// Display unit system for speed and distance. Conversions and unit symbols are
/// delegated to Foundation's `Measurement` / `UnitSpeed` / `UnitLength` so there
/// are no hardcoded conversion factors and labels are the OS-localized symbols.
enum UnitSystem: String, Equatable, Sendable, Codable, CaseIterable {
    case metric, imperial

    /// The unit system a locale implies. US/UK use mph + miles for road distances;
    /// everything else is metric. Mixed locales (e.g. Canada) fall back to the
    /// system's primary measurement system, which is metric.
    ///
    /// Split out from `system` so the mapping can be asserted against named locales
    /// rather than whatever region the test machine happens to be set to.
    init(_ locale: Locale) {
        switch locale.measurementSystem {
        case .us, .uk: self = .imperial
        default:       self = .metric
        }
    }

    /// Default resolved from the device locale (Settings → General → Language &
    /// Region → Measurement System).
    static var system: UnitSystem { UnitSystem(.current) }

    private var speedUnit: UnitSpeed { self == .metric ? .kilometersPerHour : .milesPerHour }
    private var lengthUnit: UnitLength { self == .metric ? .kilometers : .miles }
    /// Elevation is metres or feet — never kilometres or miles. A climb is quoted in the
    /// small unit in both systems, which is why this is separate from `lengthUnit`.
    private var elevationUnit: UnitLength { self == .metric ? .meters : .feet }

    /// OS-localized unit symbols ("km/h"/"mph", "km"/"mi").
    var speedLabel: String { speedUnit.symbol }
    var distanceLabel: String { lengthUnit.symbol }
    /// OS-localized elevation symbol ("m"/"ft").
    var elevationLabel: String { elevationUnit.symbol }

    /// Title-case name for the S12 units picker.
    var displayName: String { self == .metric ? "Metric" : "Imperial" }

    func speed(fromMPS mps: Double) -> Double {
        Measurement(value: mps, unit: UnitSpeed.metersPerSecond)
            .converted(to: speedUnit).value
    }

    func distance(fromMeters meters: Double) -> Double {
        Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: lengthUnit).value
    }

    /// Elevation gain or loss for display. S19's filter sheet labels its gain slider with it
    /// and S20 (#195) quotes gain and loss with the same helper, so the two cannot disagree.
    func elevation(fromMeters meters: Double) -> Double {
        Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: elevationUnit).value
    }

    /// How far off a turn is, as W9 shows it (#200): metres or feet close in, where a tenth of a
    /// kilometre or mile is too coarse to act on, and kilometres or miles to one decimal beyond
    /// 1 km / 0.1 mi. The close-in value is rounded to 10 so it does not tick over with every metre
    /// ridden, and the switch is decided on that rounded value, so 996 m reads "1.0 km", never
    /// "1,000 m". Close in is `elevationUnit` — each system's small unit.
    func turnDistance(fromMeters meters: Double) -> (value: String, unit: String) {
        let (distance, digits) = turnMeasurement(fromMeters: meters)
        return (distance.value.formatted(.number.precision(.fractionLength(digits))), distance.unit.symbol)
    }

    /// `turnDistance(fromMeters:)` in words, for VoiceOver (#361): "350 meters", "1.2 miles".
    func spokenTurnDistance(fromMeters meters: Double) -> String {
        let (distance, digits) = turnMeasurement(fromMeters: meters)
        return Self.spoken(distance, fractionLength: digits)
    }

    /// The distance W9 shows, already rounded, and how many decimals it shows it with.
    private func turnMeasurement(fromMeters meters: Double) -> (Measurement<UnitLength>, digits: Int) {
        let distance = Measurement(value: max(meters, 0), unit: UnitLength.meters)
        let near = (distance.converted(to: elevationUnit).value / 10).rounded() * 10
        let switchover = Measurement(value: self == .metric ? 1 : 0.1, unit: lengthUnit)
            .converted(to: elevationUnit).value
        if near < switchover {
            return (Measurement(value: near, unit: elevationUnit), 0)
        }
        return (distance.converted(to: lengthUnit), 1)
    }

    // MARK: - Spoken (VoiceOver)

    /// Speed in words, to one decimal as the widgets show it: "36.0 kilometers per hour" (#361).
    /// Spelled out because a bare symbol leaves VoiceOver to guess how to read it.
    func spokenSpeed(fromMPS mps: Double) -> String {
        Self.spoken(Measurement(value: speed(fromMPS: mps), unit: speedUnit), fractionLength: 1)
    }

    /// Distance in words, to one decimal: "12.4 kilometers" (#361).
    func spokenDistance(fromMeters meters: Double) -> String {
        Self.spoken(Measurement(value: distance(fromMeters: meters), unit: lengthUnit), fractionLength: 1)
    }

    private static func spoken<U: Dimension>(_ measurement: Measurement<U>, fractionLength: Int) -> String {
        measurement.formatted(.measurement(
            width: .wide,
            usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(fractionLength))
        ))
    }

    /// Seconds required to cover one distance unit (mile or kilometer) at the
    /// given speed. `nil` when the rider is stopped — at or below
    /// `ActiveRideFeature.stationarySpeedMPS`, not only at zero: a stationary
    /// phone's GPS reports a few cm/s, which read as a 500-minute pace (#144).
    /// Built on `speed(fromMPS:)` rather than a separate factor, so pace and
    /// speed can never disagree about the conversion.
    func paceSeconds(fromMPS mps: Double) -> Double? {
        guard mps > ActiveRideFeature.stationarySpeedMPS else { return nil }
        return 3600.0 / speed(fromMPS: mps)
    }

    /// Pace label ("/mi", "/km") to pair with `paceSeconds(fromMPS:)`.
    var paceLabel: String { "/" + distanceLabel }

    /// Pace as W11 shows it, "5:30": whole seconds, minutes unpadded and uncapped. `nil` where
    /// `paceSeconds(fromMPS:)` is.
    func formattedPace(fromMPS mps: Double) -> String? {
        guard let paceSeconds = paceSeconds(fromMPS: mps) else { return nil }
        let seconds = Int(paceSeconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Pace in words, "5 minutes, 30 seconds per kilometer" (#144): VoiceOver reads "5:30" digit by
    /// digit, as it does a time (#361). `nil` where `paceSeconds(fromMPS:)` is.
    func spokenPace(fromMPS mps: Double) -> String? {
        guard let paceSeconds = paceSeconds(fromMPS: mps) else { return nil }
        let time = Duration.seconds(Int(paceSeconds))
            .formatted(.units(allowed: [.minutes, .seconds], width: .wide))
        return time + (self == .metric ? " per kilometer" : " per mile")
    }
}
