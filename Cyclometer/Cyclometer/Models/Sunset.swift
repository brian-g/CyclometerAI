import Foundation

/// Today's sunset where the rider is (#462), worked out on the device — no network, no WeatherKit.
///
/// NOAA's solar-position algorithm as its Solar Calculator (gml.noaa.gov/grad/solcalc) runs it: the
/// sun's position at noon gives a first sunset, and its position at that sunset the final one. The
/// zenith is 90.833°, for refraction and the sun's radius, with no allowance for elevation.
enum Sunset {
    /// W21's reading.
    enum Countdown: Equatable, Sendable {
        /// Whole minutes until sunset, at least 1.
        case minutesLeft(Int)
        /// Today's sunset has been.
        case passed
        /// The sun doesn't set today: polar day or night.
        case noSunset
        case noFix
    }

    /// The countdown at `now`, by the calendar day in `timeZone`.
    ///
    /// Counted from the start of `now`'s minute to a sunset that is itself to the minute, so it turns
    /// over on the clock's minute and never reads 0. Yesterday's sunset counts while it is still
    /// ahead: near midsummer Reykjavik's is at 00:04.
    static func countdown(now: Date, coordinate: Coordinate?, timeZone: TimeZone) -> Countdown {
        guard let coordinate else { return .noFix }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let minute = calendar.dateInterval(of: .minute, for: now)!.start
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let sunsets = [yesterday, today].map { day in
            let date = calendar.dateComponents([.year, .month, .day], from: day)
            return sunset(year: date.year!, month: date.month!, day: date.day!, at: coordinate)
        }
        if let next = sunsets.compactMap({ $0 }).first(where: { $0 > minute }) {
            return .minutesLeft(Int((next.timeIntervalSince(minute) / 60).rounded()))
        }
        return sunsets.last! == nil ? .noSunset : .passed
    }

    /// The sunset of a calendar day at `coordinate`, to the nearest minute as NOAA publishes it. Nil
    /// when the sun doesn't set that day.
    ///
    /// The instant doesn't depend on a time zone: NOAA works in minutes from 0h UTC of the date, and
    /// west of Greenwich the sunset can fall after the next UTC midnight (Honolulu's, at 03:57 UTC).
    static func sunset(year: Int, month: Int, day: Int, at coordinate: Coordinate) -> Date? {
        let julianDay = julianDay(year: year, month: month, day: day)
        guard let estimate = utcMinutes(julianDay: julianDay, at: coordinate),
              let minutes = utcMinutes(julianDay: julianDay + estimate / minutesPerDay, at: coordinate)
        else { return nil }
        let midnight = Date(timeIntervalSince1970: (julianDay - unixEpochJulianDay) * secondsPerDay)
        return midnight.addingTimeInterval(minutes.rounded() * 60)
    }

    // MARK: - NOAA

    private static let minutesPerDay = 1_440.0
    private static let secondsPerDay = 86_400.0
    /// 1970-01-01 0h UTC.
    private static let unixEpochJulianDay = 2_440_587.5
    /// J2000.0: 2000-01-01 12h TT.
    private static let j2000JulianDay = 2_451_545.0
    private static let daysPerJulianCentury = 36_525.0
    /// The sun's centre at sunset: 90° plus 34′ of refraction and its 16′ radius.
    private static let sunsetZenith = 90.833

    /// The Julian day at 0h UTC of a Gregorian date (NOAA's `getJD`).
    private static func julianDay(year: Int, month: Int, day: Int) -> Double {
        let (y, m) = month <= 2 ? (Double(year - 1), Double(month + 12)) : (Double(year), Double(month))
        let a = (y / 100).rounded(.down)
        let b = 2 - a + (a / 4).rounded(.down)
        return (365.25 * (y + 4_716)).rounded(.down) + (30.6001 * (m + 1)).rounded(.down) + Double(day) + b - 1_524.5
    }

    /// Sunset in minutes after 0h UTC of the day `julianDay` falls in, with the sun placed at
    /// `julianDay` (NOAA's `calcSunriseSetUTC`). Nil when the sun never reaches the sunset zenith.
    private static func utcMinutes(julianDay: Double, at coordinate: Coordinate) -> Double? {
        let t = (julianDay - j2000JulianDay) / daysPerJulianCentury
        let latitude = radians(coordinate.latitude)
        let declination = radians(sunDeclination(t))
        let cosHourAngle = cos(radians(sunsetZenith)) / (cos(latitude) * cos(declination))
            - tan(latitude) * tan(declination)
        guard (-1...1).contains(cosHourAngle) else { return nil }
        let hourAngle = degrees(acos(cosHourAngle))
        return 720 - 4 * (coordinate.longitude - hourAngle) - equationOfTime(t)
    }

    private static func geometricMeanLongitude(_ t: Double) -> Double {
        (280.46646 + t * (36_000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
    }

    private static func geometricMeanAnomaly(_ t: Double) -> Double {
        357.52911 + t * (35_999.05029 - 0.0001537 * t)
    }

    private static func orbitEccentricity(_ t: Double) -> Double {
        0.016708634 - t * (0.000042037 + 0.0000001267 * t)
    }

    private static func equationOfCenter(_ t: Double) -> Double {
        let m = radians(geometricMeanAnomaly(t))
        return sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * m) * (0.019993 - 0.000101 * t)
            + sin(3 * m) * 0.000289
    }

    /// The longitude of the ascending node of the moon's orbit, behind nutation's correction.
    private static func omega(_ t: Double) -> Double {
        125.04 - 1_934.136 * t
    }

    private static func apparentLongitude(_ t: Double) -> Double {
        geometricMeanLongitude(t) + equationOfCenter(t) - 0.00569 - 0.00478 * sin(radians(omega(t)))
    }

    private static func obliquity(_ t: Double) -> Double {
        let seconds = 21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813))
        let mean = 23 + (26 + seconds / 60) / 60
        return mean + 0.00256 * cos(radians(omega(t)))
    }

    private static func sunDeclination(_ t: Double) -> Double {
        degrees(asin(sin(radians(obliquity(t))) * sin(radians(apparentLongitude(t)))))
    }

    /// Minutes of time.
    private static func equationOfTime(_ t: Double) -> Double {
        let y = pow(tan(radians(obliquity(t)) / 2), 2)
        let l0 = radians(geometricMeanLongitude(t))
        let e = orbitEccentricity(t)
        let m = radians(geometricMeanAnomaly(t))
        let radiansOfTime = y * sin(2 * l0) - 2 * e * sin(m) + 4 * e * y * sin(m) * cos(2 * l0)
            - 0.5 * y * y * sin(4 * l0) - 1.25 * e * e * sin(2 * m)
        return degrees(radiansOfTime) * 4
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}

/// The fix W21 works its sunset out from (#462): the latest, taken at most once a `refreshInterval`,
/// so the card re-renders once a minute rather than on every fix.
struct SunsetFix: Equatable, Sendable {
    static let refreshInterval: TimeInterval = 60

    let coordinate: Coordinate
    let takenAt: Date

    func isFresh(at now: Date) -> Bool {
        now.timeIntervalSince(takenAt) < Self.refreshInterval
    }
}
