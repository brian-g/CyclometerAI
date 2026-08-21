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

    /// OS-localized unit symbols ("km/h"/"mph", "km"/"mi").
    var speedLabel: String { speedUnit.symbol }
    var distanceLabel: String { lengthUnit.symbol }

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
}
