import Foundation
import SwiftData
import Testing
@testable import Cyclometer

/// `JSONColumn`, the accessor every JSON-backed `Ride` and `Route` column goes through (#563). The
/// resume-checkpoint-finish path and the NaN encode are covered end to end in
/// `PersistenceClientTests`; these pin the helper's own rules.
@Suite("JSONColumn")
struct JSONColumnTests {
    private static func column(_ name: String = "pausesData") -> JSONColumn {
        JSONColumn(entity: "Ride", name: name, owner: UUID())
    }

    private static let pause = RidePause(startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                         endedAt: Date(timeIntervalSince1970: 1_700_000_060), isAuto: false)

    @Test("an empty value reads as none without a log: the marker backfillRouteTerrain stores")
    func emptyDataIsNone() {
        let column = Self.column("terrainData")
        #expect(column.read(RouteTerrainAnalysis.self, from: Data()) == nil)
        #expect(column.read(RouteTerrainAnalysis.self, from: nil) == nil)
        #expect(!column.hasReported(.unreadable))
    }

    @Test("a value that doesn't decode reads as none, and is reported")
    func undecodableReadsAsNone() {
        let column = Self.column()
        #expect(column.read([RidePause].self, from: Data("not json".utf8)) == nil)
        #expect(column.hasReported(.unreadable))
    }

    @Test("a write over bytes that don't decode is dropped and reported; clearing them is dropped silently")
    func writeOverUndecodableIsDropped() {
        let column = Self.column()
        let stored = Data(#"[{"start":0}]"#.utf8)
        var written: [Data?] = []

        column.write(nil as [RidePause]?, over: stored) { written.append($0) }
        #expect(written.isEmpty)
        #expect(!column.hasReported(.writeDropped))

        column.write([Self.pause], over: stored) { written.append($0) }
        #expect(written.isEmpty)
        #expect(column.hasReported(.writeDropped))
    }

    @Test("a write over a value that decodes replaces it, and nil clears it")
    func writeOverDecodableStores() throws {
        let column = Self.column()
        let stored = try #require(column.encode([Self.pause]))
        var later = Self.pause
        later.isAuto = true
        var written: [Data?] = []

        column.write([Self.pause, later], over: stored) { written.append($0) }
        column.write(nil as [RidePause]?, over: stored) { written.append($0) }

        #expect(written.count == 2)
        #expect(column.read([RidePause].self, from: written[0]) == [Self.pause, later])
        #expect(written[1] == nil)
    }

    @Test("a write that encodes to the bytes already stored isn't made, a dictionary in any order included")
    func unchangedValueIsNotRewritten() throws {
        let column = Self.column("cadenceSecondsByRPMData")
        let ascending = Dictionary(uniqueKeysWithValues: (40...140).map { ($0, Double($0)) })
        let descending = Dictionary(uniqueKeysWithValues: (40...140).reversed().map { ($0, Double($0)) })
        let stored = try #require(column.encode(ascending))
        var written: [Data?] = []

        column.write(descending, over: stored) { written.append($0) }
        column.write(nil as [Int: TimeInterval]?, over: nil) { written.append($0) }

        #expect(written.isEmpty)
    }

    @Test("a checkpoint's unchanged weather, pauses and cadence leave a saved ride unchanged")
    func unchangedRideColumnsAreNotDirtied() throws {
        let stack = SwiftDataStack(inMemory: true)
        let context = ModelContext(stack.container)
        let ride = Ride()
        let sample = RideWeatherSample(date: Date(timeIntervalSince1970: 1_700_000_000), temperatureCelsius: 20,
                                       humidity: 0.5, windSpeedMPS: 2, windFromDegrees: 90, condition: .clear)
        let cadence = Dictionary(uniqueKeysWithValues: (40...140).map { ($0, Double($0)) })
        ride.weather = [sample]
        ride.pauses = [Self.pause]
        ride.cadenceSecondsByRPM = cadence
        context.insert(ride)
        try context.save()

        ride.weather = [sample]
        ride.pauses = [Self.pause]
        ride.cadenceSecondsByRPM = Dictionary(uniqueKeysWithValues: (40...140).reversed().map { ($0, Double($0)) })

        #expect(!context.hasChanges)
    }

    @Test("a route's polyline that doesn't decode reads as no coordinates, and is reported")
    func undecodableRoutePolyline() {
        let route = Route(imported: ImportedRoute(
            name: "Loop",
            terrainDescription: nil,
            coordinates: [RouteCoordinate(latitude: 36.1, longitude: -80.2, elevationMeters: nil),
                          RouteCoordinate(latitude: 36.2, longitude: -80.3, elevationMeters: nil)],
            cuePoints: []
        ))
        #expect(route.coordinates.count == 2)

        route.polylineData = Data(#"[{"lat":36.1}]"#.utf8)

        #expect(route.coordinates.isEmpty)
        #expect(JSONColumn(entity: "Route", name: "polylineData", owner: route.id).hasReported(.unreadable))
    }
}
