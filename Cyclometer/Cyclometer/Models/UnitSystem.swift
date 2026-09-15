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
        let distance = Measurement(value: max(meters, 0), unit: UnitLength.meters)
        let near = (distance.converted(to: elevationUnit).value / 10).rounded() * 10
        let switchover = Measurement(value: self == .metric ? 1 : 0.1, unit: lengthUnit)
            .converted(to: elevationUnit).value
        if near < switchover {
            return (near.formatted(.number.precision(.fractionLength(0))), elevationUnit.symbol)
        }
        let far = distance.converted(to: lengthUnit).value
        return (far.formatted(.number.precision(.fractionLength(1))), lengthUnit.symbol)
    }

    /// Seconds required to cover one distance unit (mile or kilometer) at the
    /// given speed. `nil` when speed is non-positive (pace is undefined).
    /// Built on `speed(fromMPS:)` rather than a separate factor, so pace and
    /// speed can never disagree about the conversion.
    func paceSeconds(fromMPS mps: Double) -> Double? {
        let unitsPerHour = speed(fromMPS: mps)
        guard unitsPerHour > 0 else { return nil }
        return 3600.0 / unitsPerHour
    }

    /// Pace label ("/mi", "/km") to pair with `paceSeconds(fromMPS:)`.
    var paceLabel: String { "/" + distanceLabel }
}
