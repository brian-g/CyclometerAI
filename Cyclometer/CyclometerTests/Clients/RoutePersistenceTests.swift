import ComposableArchitecture
import Foundation
import SwiftData
import Testing
@testable import Cyclometer

@Suite("PersistenceClient — Routes")
struct RoutePersistenceTests {

    // MARK: - Fixtures

    /// Inline rather than on disk, matching `GPXRouteImporterTests`. Elevations rise by
    /// 40 m per point so gain clears the hysteresis floor and the numbers are hand-checkable.
    static func climbingRoute(name: String? = "Sauratown Ridge") -> ImportedRoute {
        ImportedRoute(
            name: name,
            terrainDescription: "Rolling, chip-seal",
            coordinates: (0..<5).map {
                RouteCoordinate(
                    latitude: 36.30 + Double($0) * 0.01,
                    longitude: -80.40 + Double($0) * 0.01,
                    elevationMeters: 300 + Double($0) * 40
                )
            },
            cuePoints: [
                RouteCuePoint(latitude: 36.31, longitude: -80.39, name: "Turn left onto Sauratown Rd", cueDescription: nil, type: "Left"),
                RouteCuePoint(latitude: 36.33, longitude: -80.37, name: "Turn right onto Moore Rd", cueDescription: "at the church", type: "Right"),
            ]
        )
    }

    /// A bare `<trk>` — no `<ele>` anywhere, which is the common shape for a planned route.
    static func flatlandTrackWithoutElevation() -> ImportedRoute {
        ImportedRoute(
            name: "Greensboro Watershed",
            terrainDescription: "cycling",
            coordinates: (0..<4).map {
                RouteCoordinate(latitude: 36.10 + Double($0) * 0.01, longitude: -79.80, elevationMeters: nil)
            },
            cuePoints: []
        )
    }

    /// Fresh in-memory stacks per test, mirroring `PersistenceClientTests.makeLiveClient()`.
    static func makeLiveClient() -> (client: PersistenceClient, swiftDataStack: SwiftDataStack) {
        let swiftDataStack = SwiftDataStack(inMemory: true)
        let client = PersistenceClient.live(
            coreDataContainer: CoreDataStack(inMemory: true).container,
            modelContainer: swiftDataStack.container
        )
        return (client, swiftDataStack)
    }

    private static func fetchRideRow(_ id: UUID, from stack: SwiftDataStack) throws -> Ride {
        let context = ModelContext(stack.container)
        var descriptor = FetchDescriptor<Ride>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try #require(try context.fetch(descriptor).first)
    }

    // MARK: - Import → list → load → delete

    @Test("a route round-trips through import, list, load and delete")
    func importListLoadDeleteRoundTrip() async throws {
        let (client, _) = Self.makeLiveClient()
        let imported = Self.climbingRoute()

        let summary = try await client.importRoute(imported)
        #expect(summary.name == "Sauratown Ridge")
        #expect(summary.terrainDescription == "Rolling, chip-seal")
        #expect(summary.coordinateCount == imported.coordinates.count)

        let listed = try await client.fetchRoutes()
        #expect(listed == [summary])

        let detail = try #require(await client.fetchRoute(summary.id))
        #expect(detail.summary == summary)
        #expect(detail.coordinates == imported.coordinates)
        #expect(detail.cuePoints == imported.cuePoints)

        try await client.deleteRoute(summary.id)
        #expect(try await client.fetchRoutes().isEmpty)
        #expect(try await client.fetchRoute(summary.id) == nil)
    }

    @Test("import derives distance, elevation and bounds from the polyline")
    func importDerivesGeometry() async throws {
        let (client, _) = Self.makeLiveClient()
        let imported = Self.climbingRoute()

        let summary = try await client.importRoute(imported)

        // The stored values are exactly what the pure functions produce for this polyline —
        // the actor derives, it does not invent.
        let elevation = try #require(RouteGeometry.elevationGainLoss(imported.coordinates))
        #expect(summary.distanceMeters == RouteGeometry.distanceMeters(imported.coordinates))
        #expect(summary.elevationGainMeters == elevation.gain)
        #expect(summary.elevationLossMeters == elevation.loss)
        #expect(summary.bounds == RouteGeometry.boundingBox(imported.coordinates))
        // 4 rises of 40 m, all clearing the 3 m floor.
        #expect(summary.elevationGainMeters == 160)
        #expect(summary.elevationLossMeters == 0)
    }

    @Test("a GPX with no elevation stores nil gain and loss rather than zero")
    func aRouteWithNoElevationStoresNilGainAndLoss() async throws {
        let (client, _) = Self.makeLiveClient()

        let summary = try await client.importRoute(Self.flatlandTrackWithoutElevation())

        #expect(summary.elevationGainMeters == nil)
        #expect(summary.elevationLossMeters == nil)
        // ...and the distinction survives the store, which is what S20 reads to decide
        // whether to render an elevation section at all (#195).
        let detail = try #require(await client.fetchRoute(summary.id))
        #expect(detail.summary.elevationGainMeters == nil)
        #expect(detail.coordinates.allSatisfy { $0.elevationMeters == nil })
    }

    @Test("a route the file names nowhere gets the default name")
    func importedRouteWithNoNameGetsTheDefault() async throws {
        let (client, _) = Self.makeLiveClient()
        let summary = try await client.importRoute(Self.climbingRoute(name: nil))
        #expect(summary.name == Route.defaultName)
    }

    @Test("fetchRoutes lists newest first")
    func fetchRoutesIsNewestFirst() async throws {
        let (client, _) = Self.makeLiveClient()

        let first = try await client.importRoute(Self.climbingRoute(name: "First"))
        let second = try await client.importRoute(Self.climbingRoute(name: "Second"))

        #expect(try await client.fetchRoutes().map(\.name) == ["Second", "First"])
        #expect(second.importedAt > first.importedAt)
    }

    @Test("fetchRoute for an unknown id returns nil rather than throwing")
    func fetchRouteForAnUnknownIdReturnsNil() async throws {
        let (client, _) = Self.makeLiveClient()
        // Deliberately unlike fetchRide, which throws .rideNotFound: a Ride id is always
        // live, whereas a Ride.routeId is allowed to dangle once its route is deleted.
        #expect(try await client.fetchRoute(UUID()) == nil)
    }

    @Test("deleting an unknown route is a no-op, not an error")
    func deleteRouteForAnUnknownIdIsANoOp() async throws {
        let (client, _) = Self.makeLiveClient()
        try await client.deleteRoute(UUID())
        #expect(try await client.fetchRoutes().isEmpty)
    }

    // MARK: - Ride linkage

    @Test("createRide writes both routeId and the denormalized routeName")
    func createRideWritesRouteIdAndRouteName() async throws {
        let (client, stack) = Self.makeLiveClient()
        let summary = try await client.importRoute(Self.climbingRoute())
        let rideId = UUID()

        try await client.createRide(rideId, Date(), RouteReference(id: summary.id, name: summary.name))

        let ride = try Self.fetchRideRow(rideId, from: stack)
        #expect(ride.routeId == summary.id)
        #expect(ride.routeName == "Sauratown Ridge")
    }

    @Test("a ride started without a route leaves both fields nil")
    func createRideWithoutARouteLeavesBothFieldsNil() async throws {
        let (client, stack) = Self.makeLiveClient()
        let rideId = UUID()

        try await client.createRide(rideId, Date(), nil)

        let ride = try Self.fetchRideRow(rideId, from: stack)
        #expect(ride.routeId == nil)
        #expect(ride.routeName == nil)
    }

    @Test("deleting a route leaves a past ride's routeName intact, and its routeId dangling")
    func deletingARouteLeavesThePastRidesRouteNameIntact() async throws {
        let (client, stack) = Self.makeLiveClient()
        let summary = try await client.importRoute(Self.climbingRoute())
        let rideId = UUID()
        try await client.createRide(rideId, Date(), RouteReference(id: summary.id, name: summary.name))

        try await client.deleteRoute(summary.id)

        let ride = try Self.fetchRideRow(rideId, from: stack)
        #expect(ride.routeName == "Sauratown Ridge")
        // The id is left pointing at a row that no longer exists, on purpose: routeName is
        // the historical record, and clearing either field would rewrite history to tidy up
        // a foreign key. Pinned so a change to nulling breaks a test instead of passing quietly.
        #expect(ride.routeId == summary.id)
        #expect(try await client.fetchRoute(summary.id) == nil)
    }

    // MARK: - fetchRides(routeId:)

    @Test("fetchRides returns only that route's finished rides, newest first")
    func fetchRidesForARouteReturnsOnlyEndedRidesNewestFirst() async throws {
        let (client, _) = Self.makeLiveClient()
        let route = try await client.importRoute(Self.climbingRoute())
        let otherRoute = try await client.importRoute(Self.climbingRoute(name: "Elsewhere"))
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        let older = UUID()
        let newer = UUID()
        let otherRouteRide = UUID()
        let stillRiding = UUID()

        for (id, startedAt, reference) in [
            (older, base, route),
            (newer, base.addingTimeInterval(86_400), route),
            (otherRouteRide, base.addingTimeInterval(3_600), otherRoute),
            (stillRiding, base.addingTimeInterval(172_800), route),
        ] {
            try await client.createRide(id, startedAt, RouteReference(id: reference.id, name: reference.name))
        }
        for (id, endedAt) in [(older, base.addingTimeInterval(3_600)),
                              (newer, base.addingTimeInterval(90_000)),
                              (otherRouteRide, base.addingTimeInterval(7_200))] {
            let summary = RideSummaryUpdate(
                rideId: id, recordingState: .ended,
                durationSeconds: 3_600, distanceMeters: 42_000,
                averageSpeedMPS: 6, maxSpeedMPS: 12
            )
            try await client.finalizeRide(id, endedAt, summary, nil)
        }

        // This is also the canary for the predicate itself: `routeId` is a `UUID?` compared
        // against a captured value, the same shape that compiled and then faulted at fetch
        // time for `recordingState` (#171). A fault surfaces here as a thrown error rather
        // than as a silently empty Previous Rides list on S20.
        let rides = try await client.fetchRides(route.id)

        #expect(rides.map(\.rideId) == [newer, older])
        #expect(rides.first?.durationSeconds == 3_600)
        #expect(rides.first?.distanceMeters == 42_000)
        #expect(rides.allSatisfy { $0.endedAt != nil })
    }

    @Test("fetchRides for a route with no rides returns empty")
    func fetchRidesForARouteWithNoRidesReturnsEmpty() async throws {
        let (client, _) = Self.makeLiveClient()
        let route = try await client.importRoute(Self.climbingRoute())
        #expect(try await client.fetchRides(route.id).isEmpty)
    }

    // MARK: - Mock

    @Test("the mock derives the same summary the live path stores")
    func mockImportRouteDerivesTheSameSummaryAsLive() async throws {
        // #193's TestStore tests import through the mock, so the numbers they see have to
        // be the real derivation rather than a placeholder — otherwise a distance or an
        // elevation assertion in a feature test would be asserting on fiction.
        let imported = Self.climbingRoute()
        let seen = LockIsolated<ImportedRoute?>(nil)
        let (live, _) = Self.makeLiveClient()
        let mock = PersistenceClient.mock(onImportRoute: { seen.setValue($0) })

        let fromMock = try await mock.importRoute(imported)
        let fromLive = try await live.importRoute(imported)

        #expect(seen.value == imported)
        #expect(fromMock.name == fromLive.name)
        #expect(fromMock.distanceMeters == fromLive.distanceMeters)
        #expect(fromMock.elevationGainMeters == fromLive.elevationGainMeters)
        #expect(fromMock.elevationLossMeters == fromLive.elevationLossMeters)
        #expect(fromMock.coordinateCount == fromLive.coordinateCount)
        #expect(fromMock.bounds == fromLive.bounds)
    }

    @Test("the mock's delete spy reports the id it was asked to remove")
    func mockDeleteRouteReportsTheId() async throws {
        let deleted = LockIsolated<UUID?>(nil)
        let client = PersistenceClient.mock(onDeleteRoute: { deleted.setValue($0) })
        let id = UUID()
        try await client.deleteRoute(id)
        #expect(deleted.value == id)
    }

    @Test("the mock returns the routes, details and rides it is scripted with")
    func mockReturnsScriptedRoutes() async throws {
        let (live, _) = Self.makeLiveClient()
        let summary = try await live.importRoute(Self.climbingRoute())
        let detail = try #require(await live.fetchRoute(summary.id))
        let ride = RouteRideSummary(
            rideId: UUID(), startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_003_600),
            durationSeconds: 3_600, distanceMeters: 42_000
        )
        let client = PersistenceClient.mock(
            routes: [summary],
            routeDetails: [summary.id: detail],
            rides: [summary.id: [ride]]
        )

        #expect(try await client.fetchRoutes() == [summary])
        #expect(try await client.fetchRoute(summary.id) == detail)
        // Nil for an unscripted id, matching live — unlike fetchRide, which throws.
        #expect(try await client.fetchRoute(UUID()) == nil)
        #expect(try await client.fetchRides(summary.id) == [ride])
        #expect(try await client.fetchRides(UUID()).isEmpty)
    }

    // MARK: - On-disk behaviour
    //
    // `isStoredInMemoryOnly` cannot prove either of the next two: an in-memory store never
    // spills an `.externalStorage` attribute to its own file, and it has no relaunch to
    // survive. Both use a real store URL, following `RideSchemaMigrationTests`.

    private func withTemporaryStoreURL(_ body: (URL) async throws -> Void) async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoutePersistence-\(UUID().uuidString)")
            .appendingPathExtension("store")
        defer {
            for path in [url.path, url.path + "-wal", url.path + "-shm"] {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        try await body(url)
    }

    private func makeOnDiskClient(at url: URL) throws -> PersistenceClient {
        let container = try ModelContainer(
            for: SwiftDataStack.schema,
            configurations: [ModelConfiguration(schema: SwiftDataStack.schema, url: url)]
        )
        return PersistenceClient.live(
            coreDataContainer: CoreDataStack(inMemory: true).container,
            modelContainer: container
        )
    }

    @Test("a large polyline and its cues survive a cold reopen byte for byte")
    func externalStorageBlobsRoundTripThroughAnOnDiskStore() async throws {
        // 5,000 points is comfortably past the size at which SwiftData moves an
        // .externalStorage attribute out of the row and into its own file.
        let imported = ImportedRoute(
            name: "Blue Ridge Parkway",
            terrainDescription: "Sustained climbing",
            coordinates: (0..<5_000).map {
                RouteCoordinate(
                    latitude: 36.0 + Double($0) * 0.0001,
                    longitude: -81.0 + Double($0) * 0.0001,
                    elevationMeters: $0.isMultiple(of: 3) ? nil : 300 + Double($0) * 0.2
                )
            },
            cuePoints: (0..<50).map {
                RouteCuePoint(
                    latitude: 36.0 + Double($0) * 0.01, longitude: -81.0,
                    name: "Cue \($0)", cueDescription: $0.isMultiple(of: 2) ? "left at the barn" : nil,
                    type: $0.isMultiple(of: 2) ? "Left" : nil
                )
            }
        )

        try await withTemporaryStoreURL { url in
            // Scoped so the container and its actors are released before the reopen —
            // otherwise this reads back through the same live context and proves nothing.
            let routeId: UUID
            do {
                let client = try makeOnDiskClient(at: url)
                routeId = try await client.importRoute(imported).id
            }

            let reopened = try makeOnDiskClient(at: url)
            let detail = try #require(await reopened.fetchRoute(routeId))
            #expect(detail.coordinates == imported.coordinates)
            #expect(detail.cuePoints == imported.cuePoints)
            #expect(detail.summary.coordinateCount == 5_000)
            // The nil elevations inside the blob come back nil, not zero.
            #expect(detail.coordinates.filter { $0.elevationMeters == nil }.count
                    == imported.coordinates.filter { $0.elevationMeters == nil }.count)
        }
    }

    @Test("a ride's routeId and routeName survive an app relaunch")
    func rideRouteLinkSurvivesAColdReopen() async throws {
        try await withTemporaryStoreURL { url in
            let rideId = UUID()
            let routeId: UUID
            do {
                let client = try makeOnDiskClient(at: url)
                let summary = try await client.importRoute(Self.climbingRoute())
                try await client.createRide(rideId, Date(), RouteReference(id: summary.id, name: summary.name))
                routeId = summary.id
            }

            let reopened = try makeOnDiskClient(at: url)
            #expect(try await reopened.fetchRoute(routeId) != nil)
            #expect(try await reopened.fetchRoutes().count == 1)

            // The link itself, read off the row rather than through the client, because
            // this is the claim: routeId was persisted, not merely held in feature state.
            let container = try ModelContainer(
                for: SwiftDataStack.schema,
                configurations: [ModelConfiguration(schema: SwiftDataStack.schema, url: url)]
            )
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<Ride>(predicate: #Predicate { $0.id == rideId })
            descriptor.fetchLimit = 1
            let ride = try #require(try context.fetch(descriptor).first)
            #expect(ride.routeId == routeId)
            #expect(ride.routeName == "Sauratown Ridge")
        }
    }
}
