import Foundation
import Testing
@testable import Cyclometer

/// S10's default ride name (#249).
@Suite("RideTitle")
struct RideTitleTests {

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Midnight UTC, 2023-11-15.
    private static let midnight = Date(timeIntervalSince1970: 1_700_006_400)

    private static func at(hour: Int) -> Date { midnight.addingTimeInterval(Double(hour) * 3_600) }

    /// About 1.1 km of latitude per 0.01°; points every ~11 m.
    private static func line(from start: (Double, Double), to end: (Double, Double), steps: Int = 100) -> [RouteCoordinate] {
        (0...steps).map { step in
            let t = Double(step) / Double(steps)
            return RouteCoordinate(latitude: start.0 + (end.0 - start.0) * t,
                                   longitude: start.1 + (end.1 - start.1) * t)
        }
    }

    private static let origin = (45.0, -93.0)

    /// North 1.1 km and straight back down the same road.
    private static let outAndBack = line(from: origin, to: (45.01, -93.0)) + line(from: (45.01, -93.0), to: origin)

    /// A 1.1 km square, back to the start.
    private static let loop = line(from: origin, to: (45.01, -93.0))
        + line(from: (45.01, -93.0), to: (45.01, -92.986))
        + line(from: (45.01, -92.986), to: (45.0, -92.986))
        + line(from: (45.0, -92.986), to: origin)

    private static let oneWay = line(from: origin, to: (45.02, -93.0))

    // MARK: Shape

    @Test("a ride that comes back a different way is a loop")
    func loopShape() { #expect(RideTitle.shape(Self.loop) == .loop) }

    @Test("a ride that comes back the way it went is an out-and-back")
    func outAndBackShape() { #expect(RideTitle.shape(Self.outAndBack) == .outAndBack) }

    @Test("a ride that ends somewhere else is one way")
    func oneWayShape() { #expect(RideTitle.shape(Self.oneWay) == .oneWay) }

    @Test("an out-and-back returning along the far side of the road, with GPS noise, is still one")
    func outAndBackOffset() {
        // ~40 m east on the way back.
        let back = Self.line(from: (45.01, -92.9995), to: (45.0, -92.9995))
        #expect(RideTitle.shape(Self.line(from: Self.origin, to: (45.01, -93.0)) + back) == .outAndBack)
    }

    /// Code review of #249: the second half of repeated laps runs over the first half, so comparing
    /// it with *any* outbound point called four laps of a park an out-and-back.
    @Test("repeated laps of a loop are still a loop")
    func repeatedLaps() {
        #expect(RideTitle.shape(Self.loop + Self.loop + Self.loop + Self.loop) == .loop)
        #expect(RideTitle.shape(Self.loop + Self.loop) == .loop)
    }

    /// Found driving the simulator: 22 s and 0.1 mi from the start was named "Evening Loop".
    @Test("a ride that never left the start's neighbourhood has no shape, though it ends near it")
    func wentNowhere() {
        #expect(RideTitle.shape(Self.line(from: Self.origin, to: (45.0015, -93.0))) == .oneWay)
    }

    @Test("no track is one way — there's no shape to name")
    func emptyTrack() { #expect(RideTitle.shape([]) == .oneWay) }

    // MARK: Title

    @Test("the route's name wins over time and shape")
    func routeNameWins() {
        #expect(RideTitle.defaultTitle(routeName: "SW Fargo", startedAt: Self.at(hour: 8),
                                       segments: [Self.loop], calendar: Self.calendar) == "SW Fargo")
    }

    @Test("an empty route name falls through to time and shape")
    func emptyRouteName() {
        #expect(RideTitle.defaultTitle(routeName: "", startedAt: Self.at(hour: 8),
                                       segments: [Self.loop], calendar: Self.calendar) == "Morning Loop")
    }

    @Test("time of day and shape make the name", arguments: [
        (8, "Morning Out and Back"), (13, "Afternoon Out and Back"),
        (18, "Evening Out and Back"), (23, "Night Out and Back")
    ])
    func timeAndShape(hour: Int, expected: String) {
        #expect(RideTitle.defaultTitle(routeName: nil, startedAt: Self.at(hour: hour),
                                       segments: [Self.outAndBack], calendar: Self.calendar) == expected)
    }

    @Test("a one-way ride, or one with no track, is a plain Ride")
    func plainRide() {
        #expect(RideTitle.defaultTitle(routeName: nil, startedAt: Self.at(hour: 8),
                                       segments: [Self.oneWay], calendar: Self.calendar) == "Morning Ride")
        #expect(RideTitle.defaultTitle(routeName: nil, startedAt: Self.at(hour: 8),
                                       segments: [], calendar: Self.calendar) == "Morning Ride")
    }

    @Test("a pause splitting the track doesn't change its shape")
    func segmentsJoined() {
        let half = Self.loop.count / 2
        let split = [Array(Self.loop[..<half]), Array(Self.loop[half...])]
        #expect(RideTitle.defaultTitle(routeName: nil, startedAt: Self.at(hour: 8),
                                       segments: split, calendar: Self.calendar) == "Morning Loop")
    }

    @Test("a place name leads the time of day and shape")
    func placeNameLeads() {
        #expect(RideTitle.defaultTitle(routeName: nil, placeName: "Fargo", startedAt: Self.at(hour: 8),
                                       segments: [Self.loop], calendar: Self.calendar) == "Fargo Morning Loop")
        #expect(RideTitle.defaultTitle(routeName: nil, placeName: "Fargo", startedAt: Self.at(hour: 18),
                                       segments: [Self.outAndBack], calendar: Self.calendar) == "Fargo Evening Out and Back")
    }

    @Test("the route's name wins over a place name")
    func routeNameBeatsPlace() {
        #expect(RideTitle.defaultTitle(routeName: "SW Fargo", placeName: "Fargo", startedAt: Self.at(hour: 8),
                                       segments: [Self.loop], calendar: Self.calendar) == "SW Fargo")
    }

    @Test("no place name, or a blank one, gives the offline name", arguments: [nil, "", "  "] as [String?])
    func missingPlaceName(place: String?) {
        #expect(RideTitle.defaultTitle(routeName: nil, placeName: place, startedAt: Self.at(hour: 8),
                                       segments: [Self.loop], calendar: Self.calendar) == "Morning Loop")
    }

    @Test("part-of-day boundaries", arguments: [
        (4, "Night"), (5, "Morning"), (11, "Morning"), (12, "Afternoon"),
        (16, "Afternoon"), (17, "Evening"), (20, "Evening"), (21, "Night")
    ])
    func partOfDay(hour: Int, expected: String) {
        #expect(RideTitle.partOfDay(Self.at(hour: hour), calendar: Self.calendar) == expected)
    }
}
