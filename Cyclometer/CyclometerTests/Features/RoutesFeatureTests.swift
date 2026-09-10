import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

/// S19 — the Routes tab reading its store rather than the demo data the prototype used (#193).
@MainActor
@Suite("RoutesFeature")
struct RoutesFeatureTests {

    // MARK: Harness

    /// Each store gets its own in-memory file system, and the `@Shared` seed happens in the
    /// same scope — otherwise the seed and the store read different storage. Same idiom as
    /// `SettingsFeatureTests.makeStore`.
    private func makeStore(
        showsMap: Bool = false,
        preferredUnit: UnitSystem = .imperial,
        persistenceClient: PersistenceClient = .mock(),
        locationClient: LocationClient = .testValue,
        locationPermission: PermissionState = .denied
    ) -> TestStoreOf<RoutesFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.preferredUnit = preferredUnit }
            return TestStore(initialState: RoutesFeature.State(showsMap: showsMap)) {
                RoutesFeature()
            } withDependencies: {
                $0.persistenceClient = persistenceClient
                $0.locationClient = locationClient
                $0.permissionsClient = .mock(initial: [.locationWhenInUse: locationPermission])
                $0.defaultFileStorage = storage
            }
        }
    }

    /// `RouteSummary.empty` puts every fixture at bounds (0, 0, 0, 0) — the Gulf of Guinea —
    /// with no elevation gain, so both are parameters here rather than left to the default:
    /// #194 filters on all three and a fixture that shares its box with every other one cannot
    /// express a viewport that holds some routes and not others.
    private static func summary(
        id: UUID = UUID(), name: String = "River Loop",
        terrain: String? = "Rolling terrain", distanceMeters: Double = 36_050,
        elevationGainMeters: Double? = nil,
        bounds: RouteBounds = RouteBounds(minLatitude: 37.32, maxLatitude: 37.35,
                                          minLongitude: -122.05, maxLongitude: -122.00)
    ) -> RouteSummary {
        var summary = RouteSummary.empty
        summary.id = id
        summary.name = name
        summary.terrainDescription = terrain
        summary.distanceMeters = distanceMeters
        summary.elevationGainMeters = elevationGainMeters
        summary.bounds = bounds
        return summary
    }

    /// Written to a real temporary file because `GPXRouteImporter.route(contentsOf:)` reads
    /// a URL — the import effect's whole job is turning a picked file into a saved route,
    /// and stubbing the read out would test everything except that.
    private func writeGPX(_ xml: String, named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoutesFeatureTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try xml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static let namedGPX = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="test">
      <trk><name>River Loop</name><desc>Rolling terrain</desc><trkseg>
        <trkpt lat="37.3349" lon="-122.0090"/>
        <trkpt lat="37.3360" lon="-122.0070"/>
        <trkpt lat="37.3380" lon="-122.0040"/>
      </trkseg></trk>
    </gpx>
    """

    private static let unnamedGPX = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="test">
      <trk><trkseg>
        <trkpt lat="37.3349" lon="-122.0090"/>
        <trkpt lat="37.3360" lon="-122.0070"/>
      </trkseg></trk>
    </gpx>
    """

    // MARK: Loading

    @Test("task loads the persisted routes into state")
    func taskLoadsRoutes() async {
        let routes = [Self.summary(name: "River Loop"), Self.summary(name: "Summit Climb")]
        let store = makeStore(persistenceClient: .mock(routes: routes))

        await store.send(.task)
        await store.receive(\.reloadRoutes)
        await store.receive(\.routesResponse) {
            $0.hasLoaded = true
            $0.routes = routes
        }
        await store.finish()
    }

    @Test("task with no saved routes leaves the list empty")
    func taskWithNoRoutes() async {
        let store = makeStore()

        await store.send(.task)
        await store.receive(\.reloadRoutes)
        await store.receive(\.routesResponse) { $0.hasLoaded = true }
        #expect(store.state.routes.isEmpty)
        await store.finish()
    }

    /// The screen has to render with location denied — the rider can reach the Routes tab
    /// without ever having granted it — and asking for a fix anyway would be the one call
    /// that could raise a prompt on a browse screen.
    @Test("With location denied, no fix is requested and the rider coordinate stays nil")
    func locationDeniedSkipsTheFix() async {
        let asked = LockIsolated(false)
        var location = LocationClient.testValue
        location.currentCoordinate = { asked.setValue(true); return nil }

        let store = makeStore(locationClient: location, locationPermission: .denied)

        await store.send(.task)
        await store.receive(\.reloadRoutes)
        await store.receive(\.routesResponse) { $0.hasLoaded = true }
        await store.finish()

        #expect(asked.value == false)
        #expect(store.state.riderCoordinate == nil)
    }

    @Test("With location granted, the fix is stored for the map camera")
    func locationGrantedStoresTheFix() async {
        let fix = Coordinate(latitude: 44.9778, longitude: -93.2650)
        var location = LocationClient.testValue
        location.currentCoordinate = { fix }

        let store = makeStore(locationClient: location, locationPermission: .granted)
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.riderCoordinateResponse) { $0.riderCoordinate = fix }
        await store.finish()
    }

    @Test("A failed read alerts rather than showing an empty list as if nothing was saved")
    func failedReadAlerts() async {
        var client = PersistenceClient.mock()
        client.fetchRoutes = { throw PersistenceError.rideNotFound }
        let store = makeStore(persistenceClient: client)

        await store.send(.task)
        await store.receive(\.reloadRoutes)
        await store.receive(\.routesResponse) {
            $0.alert = AlertState {
                TextState("Couldn't Load Routes")
            } actions: {
                ButtonState(role: .cancel) { TextState("OK") }
            } message: {
                TextState("Your saved routes couldn't be read. Try again in a moment.")
            }
        }
        await store.finish()

        // The read failed, so the screen must not also assert the store is empty — that is
        // what `hasLoaded` separates.
        #expect(store.state.hasLoaded == false)
    }

    // MARK: Map

    @Test("The map toggle flips the view")
    func mapToggle() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.mapToggled) { $0.showsMap = true }
        await store.send(.mapToggled) { $0.showsMap = false }
        await store.finish()
    }

    /// Polylines are the one thing `RouteSummary` deliberately does not carry, so opening
    /// the map is a second read — and it must not happen for a rider who only uses the list.
    @Test("Polylines load when the map opens, not before")
    func polylinesLoadOnMapOpen() async {
        let id = UUID()
        let coordinates = [
            RouteCoordinate(latitude: 37.3349, longitude: -122.0090, elevationMeters: nil),
            RouteCoordinate(latitude: 37.3360, longitude: -122.0070, elevationMeters: nil)
        ]
        let route = Self.summary(id: id)
        let store = makeStore(persistenceClient: .mock(
            routes: [route],
            routeDetails: [id: RouteDetail(summary: route, coordinates: coordinates, cuePoints: [])]
        ))
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.routesResponse)
        #expect(store.state.polylines.isEmpty)

        await store.send(.mapToggled)
        await store.receive(\.polylinesResponse) { $0.polylines = [id: coordinates] }
        await store.finish()
    }

    // MARK: Import

    @Test("Importing a GPX prepends the saved route and closes the picker")
    func importPrependsRoute() async throws {
        let url = try writeGPX(Self.namedGPX, named: "river-loop.gpx")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let existing = Self.summary(name: "Summit Climb")
        let imported = LockIsolated<[ImportedRoute]>([])
        let store = makeStore(persistenceClient: .mock(
            routes: [existing],
            onImportRoute: { route in imported.withValue { $0.append(route) } }
        ))
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.routesResponse) { $0.routes = [existing] }

        await store.send(.importButtonTapped) { $0.isImporterPresented = true }
        await store.send(.fileSelected(url)) {
            $0.isImporterPresented = false
            $0.isImporting = true
        }
        await store.receive(\.importResponse) { $0.isImporting = false }
        await store.finish()

        #expect(imported.value.count == 1)
        #expect(imported.value.first?.name == "River Loop")
        #expect(store.state.routes.count == 2)
        #expect(store.state.routes.first?.name == "River Loop")
        // Newest first — the same order `fetchRoutes` returns.
        #expect(store.state.routes.last?.name == "Summit Climb")
    }

    /// `Route.defaultName` ("Imported Route") is a poor label when the file is right there
    /// with a name on it.
    @Test("A GPX that names itself nowhere takes the filename")
    func unnamedGPXTakesFilename() async throws {
        let url = try writeGPX(Self.unnamedGPX, named: "Sunday Gravel.gpx")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let imported = LockIsolated<[ImportedRoute]>([])
        let store = makeStore(persistenceClient: .mock(
            onImportRoute: { route in imported.withValue { $0.append(route) } }
        ))
        store.exhaustivity = .off

        await store.send(.fileSelected(url))
        await store.receive(\.importResponse)
        await store.finish()

        #expect(imported.value.first?.name == "Sunday Gravel")
        #expect(store.state.routes.first?.name == "Sunday Gravel")
    }

    @Test("Each parse failure gets its own message and leaves the list alone",
          arguments: [
            ("<gpx>", GPXImportError.malformed),
            ("<?xml version=\"1.0\"?><gpx version=\"1.1\"><trk><trkseg></trkseg></trk></gpx>",
             GPXImportError.noCoordinates)
          ])
    func importFailureAlerts(_ xml: String, _ expected: GPXImportError) async throws {
        let url = try writeGPX(xml, named: "broken.gpx")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let existing = Self.summary(name: "Summit Climb")
        let store = makeStore(persistenceClient: .mock(routes: [existing]))
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.routesResponse)

        await store.send(.fileSelected(url))
        await store.receive(\.importResponse)
        await store.finish()

        #expect(store.state.routes == [existing])
        #expect(store.state.isImporting == false)
        #expect(store.state.alert != nil)
        #expect(store.state.alert?.message == TextState(RouteImportFailure(expected).message))
    }

    @Test("A save failure is reported as a save failure, not a parse failure")
    func saveFailureMessage() async throws {
        let url = try writeGPX(Self.namedGPX, named: "river-loop.gpx")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var client = PersistenceClient.mock()
        client.importRoute = { _ in throw PersistenceError.batchInsertFailed }
        let store = makeStore(persistenceClient: client)
        store.exhaustivity = .off

        await store.send(.fileSelected(url))
        await store.receive(\.importResponse)
        await store.finish()

        #expect(store.state.routes.isEmpty)
        #expect(store.state.alert?.message
                == TextState("The route was read but couldn't be saved."))
    }

    @Test("A cancelled or failed picker closes the sheet and says so")
    func pickerFailure() async {
        let store = makeStore()

        await store.send(.importButtonTapped) { $0.isImporterPresented = true }
        await store.send(.filePickerFailed) {
            $0.isImporterPresented = false
            $0.alert = AlertState {
                TextState("Couldn't Open File")
            } actions: {
                ButtonState(role: .cancel) { TextState("OK") }
            } message: {
                TextState("That file couldn't be opened. Try picking it again.")
            }
        }
        await store.finish()
    }

    // MARK: Delete

    @Test("Swipe-to-delete removes the row and deletes it from the store")
    func deleteRemovesRoute() async {
        let keep = Self.summary(name: "Summit Climb")
        let drop = Self.summary(name: "River Loop")
        let deleted = LockIsolated<[UUID]>([])
        let store = makeStore(persistenceClient: .mock(
            routes: [drop, keep],
            onDeleteRoute: { id in deleted.withValue { $0.append(id) } }
        ))
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.routesResponse)

        await store.send(.deleteButtonTapped(drop.id)) { $0.routes = [keep] }
        await store.finish()

        #expect(deleted.value == [drop.id])
    }

    /// The row is removed optimistically, so a failed write would otherwise leave the list
    /// quietly disagreeing with the store.
    @Test("A failed delete alerts and re-reads rather than trusting the optimistic removal")
    func deleteFailureRestores() async {
        let route = Self.summary(name: "River Loop")
        var client = PersistenceClient.mock(routes: [route])
        client.deleteRoute = { _ in throw PersistenceError.batchInsertFailed }
        let store = makeStore(persistenceClient: client)
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.routesResponse) { $0.routes = [route] }

        await store.send(.deleteButtonTapped(route.id)) { $0.routes = [] }
        await store.receive(\.deleteFailed)
        await store.receive(\.reloadRoutes)
        await store.receive(\.routesResponse)
        await store.finish()

        #expect(store.state.routes == [route])
        #expect(store.state.alert?.title == TextState("Couldn't Delete Route"))
    }
}

// MARK: - Regressions from the #193 review

@MainActor
@Suite("RoutesFeature — review regressions")
struct RoutesFeatureReviewTests {

    private func makeStore(
        showsMap: Bool = false,
        persistenceClient: PersistenceClient = .mock()
    ) -> TestStoreOf<RoutesFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            TestStore(initialState: RoutesFeature.State(showsMap: showsMap)) {
                RoutesFeature()
            } withDependencies: {
                $0.persistenceClient = persistenceClient
                $0.locationClient = .testValue
                $0.permissionsClient = .mock(initial: [.locationWhenInUse: .denied])
                $0.defaultFileStorage = storage
            }
        }
    }

    /// Bounds that actually contain `coordinates()`. They used to be `RouteSummary.empty`'s
    /// zeros while the geometry sat off Cupertino, which was harmless until #194 gave the
    /// bounding box a job: a summary whose box disagrees with its own polyline cannot be
    /// filtered correctly by any rule.
    nonisolated private static func summary(_ id: UUID, _ name: String) -> RouteSummary {
        var summary = RouteSummary.empty
        summary.id = id
        summary.name = name
        summary.bounds = RouteGeometry.boundingBox(coordinates())
        return summary
    }

    nonisolated private static func coordinates() -> [RouteCoordinate] {
        [RouteCoordinate(latitude: 37.33, longitude: -122.00, elevationMeters: nil),
         RouteCoordinate(latitude: 37.34, longitude: -122.01, elevationMeters: nil)]
    }

    private static func gpx(named name: String) throws -> URL {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1"><trk><name>\(name)</name><trkseg>
          <trkpt lat="37.3349" lon="-122.0090"/>
          <trkpt lat="37.3420" lon="-122.0150"/>
        </trkseg></trk></gpx>
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoutesReview-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("\(name).gpx")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try xml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Importing while the map is showing used to leave the new route with a pin and no line:
    /// the only two loaders ran on the map toggle and on a re-read, and this path is neither.
    @Test("A route imported while the map is showing gets its polyline loaded")
    func importOnTheMapLoadsItsPolyline() async throws {
        let url = try Self.gpx(named: "Coastal Loop")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let id = UUID()
        let summary = Self.summary(id, "Coastal Loop")
        let store = makeStore(showsMap: true, persistenceClient: .mock(
            routeDetails: [id: RouteDetail(summary: summary,
                                           coordinates: Self.coordinates(), cuePoints: [])],
            importResult: summary
        ))
        store.exhaustivity = .off

        await store.send(.fileSelected(url))
        await store.receive(\.importResponse)
        await store.receive(\.polylinesResponse)
        await store.finish()

        #expect(store.state.polylines[id]?.count == 2)
    }

    /// The cache used to be validated by comparing counts, so a route whose fetch failed left
    /// the counts permanently unequal and every toggle re-fetched all of them.
    @Test("A route whose polyline cannot load is not re-fetched on every map toggle")
    func unloadablePolylineIsNotRefetchedForever() async {
        let good = UUID(), bad = UUID()
        let goodSummary = Self.summary(good, "Loads")
        let fetches = LockIsolated<[UUID]>([])
        var client = PersistenceClient.mock(routes: [goodSummary, Self.summary(bad, "Fails")])
        client.fetchRoute = { id in
            fetches.withValue { $0.append(id) }
            guard id == good else { return nil }
            return RouteDetail(summary: goodSummary, coordinates: Self.coordinates(), cuePoints: [])
        }
        let store = makeStore(persistenceClient: client)
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.routesResponse)

        await store.send(.mapToggled)
        await store.receive(\.polylinesResponse)
        #expect(fetches.value.count == 2)

        // Back to the list and onto the map again: only the one that failed is retried.
        await store.send(.mapToggled)
        await store.send(.mapToggled)
        await store.receive(\.polylinesResponse)
        await store.finish()

        #expect(fetches.value == [good, bad, bad])
    }

    /// A 16 MB file is seconds of parsing, and the picker dismisses immediately — a rider who
    /// taps Import again used to get the route saved twice.
    ///
    /// Asserted against the guard rather than by racing two sends against a sleeping mock:
    /// the two-tap version passed alone and failed under suite load, because it assumed the
    /// second send lands inside the first effect's sleep. The guard is the behaviour; the
    /// double tap is only the motivation for it.
    @Test("A file picked while an import is already running is ignored")
    func concurrentImportIsRefused() async throws {
        let url = try Self.gpx(named: "Coastal Loop")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let imports = LockIsolated(0)
        var client = PersistenceClient.mock()
        client.importRoute = { imported in
            imports.withValue { $0 += 1 }
            return RouteSummary(imported: imported)
        }

        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            var state = RoutesFeature.State()
            state.isImporting = true
            return TestStore(initialState: state) {
                RoutesFeature()
            } withDependencies: {
                $0.persistenceClient = client
                $0.locationClient = .testValue
                $0.permissionsClient = .mock(initial: [.locationWhenInUse: .denied])
                $0.defaultFileStorage = storage
            }
        }

        // No state change and no effect: the in-flight import owns the screen.
        await store.send(.fileSelected(url))
        await store.finish()

        #expect(imports.value == 0)
        #expect(store.state.routes.isEmpty)
    }

    /// The other half of the guard — it has to clear, or one import would lock the screen out
    /// of importing ever again.
    @Test("The guard clears once the import finishes")
    func importGuardClears() async throws {
        let url = try Self.gpx(named: "Coastal Loop")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let imports = LockIsolated(0)
        var client = PersistenceClient.mock()
        client.importRoute = { imported in
            imports.withValue { $0 += 1 }
            return RouteSummary(imported: imported)
        }
        let store = makeStore(persistenceClient: client)
        store.exhaustivity = .off

        await store.send(.fileSelected(url))
        await store.receive(\.importResponse)
        #expect(store.state.isImporting == false)

        await store.send(.fileSelected(url))
        await store.receive(\.importResponse)
        await store.finish()

        #expect(imports.value == 2)
        #expect(store.state.routes.count == 2)
    }

    /// The recovery re-read used to be `.send(.task)`, which also re-ran the permission check
    /// and issued another location request.
    @Test("A failed delete re-reads the routes without re-requesting a location fix")
    func deleteRecoveryDoesNotRequestLocationAgain() async {
        let route = Self.summary(UUID(), "River Loop")
        let fixes = LockIsolated(0)
        var location = LocationClient.testValue
        location.currentCoordinate = { fixes.withValue { $0 += 1 }; return nil }

        var client = PersistenceClient.mock(routes: [route])
        client.deleteRoute = { _ in throw PersistenceError.batchInsertFailed }

        let storage = FileStorage.inMemory
        let store = withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            TestStore(initialState: RoutesFeature.State()) {
                RoutesFeature()
            } withDependencies: {
                $0.persistenceClient = client
                $0.locationClient = location
                $0.permissionsClient = .mock(initial: [.locationWhenInUse: .granted])
                $0.defaultFileStorage = storage
            }
        }
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.routesResponse)
        #expect(fixes.value == 1)

        await store.send(.deleteButtonTapped(route.id))
        await store.receive(\.deleteFailed)
        await store.receive(\.reloadRoutes)
        await store.receive(\.routesResponse)
        await store.finish()

        #expect(fixes.value == 1, "the recovery re-read also re-ran the location request")
        #expect(store.state.routes == [route])
    }
}

/// #194 — the three filters, and what happens to them as the library changes underneath.
@MainActor
@Suite("RoutesFeature — filters")
struct RoutesFeatureFilterTests {

    // MARK: Fixtures

    private static let nearID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private static let farID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!

    /// Two routes far enough apart that a viewport can hold one and not the other.
    private static let near = summary(
        id: nearID, name: "Near", distanceMeters: 20_000, elevationGainMeters: 100,
        bounds: RouteBounds(minLatitude: 37.30, maxLatitude: 37.35,
                            minLongitude: -122.10, maxLongitude: -122.05)
    )
    private static let far = summary(
        id: farID, name: "Far", distanceMeters: 60_000, elevationGainMeters: 800,
        bounds: RouteBounds(minLatitude: 37.60, maxLatitude: 37.65,
                            minLongitude: -121.90, maxLongitude: -121.85)
    )

    /// Holds `near` whole and none of `far`.
    private static let nearViewport = RouteBounds(
        minLatitude: 37.28, maxLatitude: 37.37,
        minLongitude: -122.12, maxLongitude: -122.03
    )

    private static func summary(
        id: UUID, name: String, distanceMeters: Double,
        elevationGainMeters: Double?, bounds: RouteBounds
    ) -> RouteSummary {
        var summary = RouteSummary.empty
        summary.id = id
        summary.name = name
        summary.distanceMeters = distanceMeters
        summary.elevationGainMeters = elevationGainMeters
        summary.bounds = bounds
        return summary
    }

    private static func detail(_ summary: RouteSummary) -> RouteDetail {
        // A short line inside the route's own bounds, so the stored box and the polyline agree.
        RouteDetail(
            summary: summary,
            coordinates: [
                RouteCoordinate(latitude: summary.bounds.minLatitude,
                                longitude: summary.bounds.minLongitude, elevationMeters: nil),
                RouteCoordinate(latitude: summary.bounds.maxLatitude,
                                longitude: summary.bounds.maxLongitude, elevationMeters: nil)
            ],
            cuePoints: []
        )
    }

    private func makeStore(
        showsMap: Bool = false,
        persistenceClient: PersistenceClient
    ) -> TestStoreOf<RoutesFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.preferredUnit = .metric }
            return TestStore(initialState: RoutesFeature.State(showsMap: showsMap)) {
                RoutesFeature()
            } withDependencies: {
                $0.persistenceClient = persistenceClient
                $0.locationClient = .testValue
                $0.permissionsClient = .mock(initial: [.locationWhenInUse: .denied])
                $0.defaultFileStorage = storage
            }
        }
    }

    /// A store already on the map with both routes and their geometry loaded.
    private func loadedMapStore() async -> TestStoreOf<RoutesFeature> {
        let routes = [Self.near, Self.far]
        let details = [Self.nearID: Self.detail(Self.near), Self.farID: Self.detail(Self.far)]
        let store = makeStore(showsMap: true,
                              persistenceClient: .mock(routes: routes, routeDetails: details))
        await store.send(.task)
        await store.receive(\.reloadRoutes)
        await store.receive(\.routesResponse) {
            $0.hasLoaded = true
            $0.routes = routes
        }
        await store.receive(\.polylinesResponse) {
            $0.polylines = [Self.nearID: details[Self.nearID]!.coordinates,
                            Self.farID: details[Self.farID]!.coordinates]
        }
        return store
    }

    // MARK: The map as a filter

    @Test("panning the map records the viewport without reordering the list")
    func mapRegionChangedRecordsOnly() async {
        let store = await loadedMapStore()

        await store.send(.mapRegionChanged(Self.nearViewport)) {
            $0.visibleMapBounds = Self.nearViewport
        }
        // Recorded, not applied: the list must not shuffle under a map the rider is still panning.
        #expect(store.state.mapFilterBounds == nil)
        #expect(store.state.filteredRoutes.count == 2)
        await store.finish()
    }

    @Test("switching back to the list captures the viewport and narrows to it")
    func mapToListCapturesTheViewport() async {
        let store = await loadedMapStore()

        await store.send(.mapRegionChanged(Self.nearViewport)) {
            $0.visibleMapBounds = Self.nearViewport
        }
        await store.send(.mapToggled) {
            $0.showsMap = false
            $0.mapFilterBounds = Self.nearViewport
            $0.mapFilteredRouteIDs = [Self.nearID]
        }

        #expect(store.state.filteredRoutes.map(\.name) == ["Near"])
        // The AC: filter state does not leak into the unfiltered store contents.
        #expect(store.state.routes.map(\.name) == ["Near", "Far"])
        await store.finish()
    }

    @Test("going back to the map does not capture, so the viewport can be widened again")
    func listToMapDoesNotCapture() async {
        let store = await loadedMapStore()
        await store.send(.mapRegionChanged(Self.nearViewport)) {
            $0.visibleMapBounds = Self.nearViewport
        }
        await store.send(.mapToggled) {
            $0.showsMap = false
            $0.mapFilterBounds = Self.nearViewport
            $0.mapFilteredRouteIDs = [Self.nearID]
        }

        // Re-opening the map must show everything the sheet allows, or the rider can only ever
        // narrow — there would be no gesture that brings a route back.
        await store.send(.mapToggled) { $0.showsMap = true }
        #expect(store.state.sheetFilteredRoutes.count == 2)
        #expect(store.state.mapFilterBounds == Self.nearViewport)
        await store.finish()
    }

    @Test("a cleared map filter stays cleared across a trip back to the map")
    func clearedMapFilterIsNotSilentlyReapplied() async {
        // The map re-opens on the viewport the rider left it on, reports it, and the switch
        // back to the list captures it — so without remembering what was dismissed, the chip's
        // clear button would appear to do nothing the moment they visited the map again.
        let store = await loadedMapStore()
        await store.send(.mapRegionChanged(Self.nearViewport)) {
            $0.visibleMapBounds = Self.nearViewport
        }
        await store.send(.mapToggled) {
            $0.showsMap = false
            $0.mapFilterBounds = Self.nearViewport
            $0.mapFilteredRouteIDs = [Self.nearID]
        }
        await store.send(.mapFilterCleared) {
            $0.dismissedMapBounds = Self.nearViewport
            $0.mapFilterBounds = nil
            $0.mapFilteredRouteIDs = nil
        }

        await store.send(.mapToggled) { $0.showsMap = true }
        // The map re-opens where it was and re-reports the same region.
        await store.send(.mapRegionChanged(Self.nearViewport))
        await store.send(.mapToggled) { $0.showsMap = false }
        #expect(store.state.mapFilterBounds == nil)
        #expect(store.state.filteredRoutes.count == 2)

        // Panning somewhere new is a fresh decision and does capture.
        let wider = RouteBounds(minLatitude: 37.20, maxLatitude: 37.40,
                                minLongitude: -122.20, maxLongitude: -122.00)
        await store.send(.mapToggled) { $0.showsMap = true }
        await store.send(.mapRegionChanged(wider)) { $0.visibleMapBounds = wider }
        await store.send(.mapToggled) {
            $0.showsMap = false
            $0.dismissedMapBounds = nil
            $0.mapFilterBounds = wider
            $0.mapFilteredRouteIDs = [Self.nearID]
        }
        await store.finish()
    }

    @Test("clearing the map filter restores the whole list")
    func mapFilterCleared() async {
        let store = await loadedMapStore()
        await store.send(.mapRegionChanged(Self.nearViewport)) {
            $0.visibleMapBounds = Self.nearViewport
        }
        await store.send(.mapToggled) {
            $0.showsMap = false
            $0.mapFilterBounds = Self.nearViewport
            $0.mapFilteredRouteIDs = [Self.nearID]
        }
        await store.send(.mapFilterCleared) {
            $0.dismissedMapBounds = Self.nearViewport
            $0.mapFilterBounds = nil
            $0.mapFilteredRouteIDs = nil
        }
        #expect(store.state.filteredRoutes.count == 2)
        await store.finish()
    }

    // MARK: Routes whose geometry has not loaded

    @Test("a route imported from the list survives an active map filter")
    func importedRouteIsNotHiddenByTheMapFilter() async {
        // `loadMissingPolylines` runs only while the map is showing, so a route imported from
        // the list has no geometry. Failing it would mean the rider imports a GPX and the
        // screen does nothing at all.
        let store = await loadedMapStore()
        await store.send(.mapRegionChanged(Self.nearViewport)) {
            $0.visibleMapBounds = Self.nearViewport
        }
        await store.send(.mapToggled) {
            $0.showsMap = false
            $0.mapFilterBounds = Self.nearViewport
            $0.mapFilteredRouteIDs = [Self.nearID]
        }

        let importedID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let imported = Self.summary(
            id: importedID, name: "Imported", distanceMeters: 30_000, elevationGainMeters: 200,
            bounds: RouteBounds(minLatitude: 37.31, maxLatitude: 37.33,
                                minLongitude: -122.09, maxLongitude: -122.06)
        )
        await store.send(.importResponse(.success(imported))) {
            $0.routes.insert(imported, at: 0)
            $0.mapFilteredRouteIDs = [Self.nearID, importedID]
        }
        #expect(store.state.filteredRoutes.map(\.name) == ["Imported", "Near"])
        await store.finish()
    }

    @Test("a route whose polyline never loads is still matched on its bounding box")
    func unloadablePolylineFallsBackToBounds() async {
        // `unloadablePolylineIsNotRefetchedForever` pins that a failed fetch is never retried,
        // so this route has no geometry for the life of the screen. Dropping it would remove
        // the row from the list permanently, with no way back.
        let routes = [Self.near, Self.far]
        let store = makeStore(showsMap: true,
                              persistenceClient: .mock(routes: routes, routeDetails: [:]))
        await store.send(.task)
        await store.receive(\.reloadRoutes)
        await store.receive(\.routesResponse) {
            $0.hasLoaded = true
            $0.routes = routes
        }
        await store.receive(\.polylinesResponse)

        #expect(store.state.polylines.isEmpty)
        await store.send(.mapRegionChanged(Self.nearViewport)) {
            $0.visibleMapBounds = Self.nearViewport
        }
        await store.send(.mapToggled) {
            $0.showsMap = false
            $0.mapFilterBounds = Self.nearViewport
            // `near`'s box is inside the viewport; `far`'s is not, so the fallback still
            // discriminates — it is over-inclusive, not indiscriminate.
            $0.mapFilteredRouteIDs = [Self.nearID]
        }
        #expect(store.state.filteredRoutes.map(\.name) == ["Near"])
        await store.finish()
    }

    @Test("geometry arriving later upgrades the map filter from the box to the exact test")
    func polylinesResponseRefreshesTheMapFilter() async {
        // A viewport in the empty corner of a diagonal route: its box overlaps, its line does
        // not. Before the geometry lands the box keeps it; once the polyline is in, it goes.
        let diagonalID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let diagonal = Self.summary(
            id: diagonalID, name: "Diagonal", distanceMeters: 50_000, elevationGainMeters: nil,
            bounds: RouteBounds(minLatitude: 37.00, maxLatitude: 38.00,
                                minLongitude: -123.00, maxLongitude: -121.00)
        )
        let corner = RouteBounds(minLatitude: 37.90, maxLatitude: 38.00,
                                 minLongitude: -123.00, maxLongitude: -122.90)
        let geometry = [
            RouteCoordinate(latitude: 37.00, longitude: -123.00, elevationMeters: nil),
            RouteCoordinate(latitude: 38.00, longitude: -121.00, elevationMeters: nil)
        ]

        let store = makeStore(persistenceClient: .mock(routes: [diagonal]))
        await store.send(.task)
        await store.receive(\.reloadRoutes)
        await store.receive(\.routesResponse) {
            $0.hasLoaded = true
            $0.routes = [diagonal]
        }
        await store.send(.mapRegionChanged(corner)) { $0.visibleMapBounds = corner }
        await store.send(.mapToggled) { $0.showsMap = true }
        await store.receive(\.polylinesResponse)
        await store.send(.mapToggled) {
            $0.showsMap = false
            $0.mapFilterBounds = corner
            $0.mapFilteredRouteIDs = [diagonalID]
        }
        #expect(store.state.filteredRoutes.count == 1, "kept on its box while geometry is absent")

        await store.send(.polylinesResponse([diagonalID: geometry])) {
            $0.polylines = [diagonalID: geometry]
            $0.mapFilteredRouteIDs = []
        }
        #expect(store.state.filteredRoutes.isEmpty, "the line never enters that corner")
        await store.finish()
    }

    // MARK: The sheet filters

    @Test("the badge counts the sheet filters and ignores the map")
    func badgeCountsSheetFiltersOnly() async {
        let store = await loadedMapStore()
        #expect(store.state.activeFilterCount == 0)

        await store.send(.distanceFilterChanged(20_000...30_000)) {
            $0.filter.distanceMeters = 20_000...30_000
        }
        #expect(store.state.activeFilterCount == 1)

        await store.send(.elevationGainFilterChanged(400)) {
            $0.filter.maxElevationGainMeters = 400
        }
        #expect(store.state.activeFilterCount == 2)

        await store.send(.mapRegionChanged(Self.nearViewport)) {
            $0.visibleMapBounds = Self.nearViewport
        }
        await store.send(.mapToggled) {
            $0.showsMap = false
            $0.mapFilterBounds = Self.nearViewport
            $0.mapFilteredRouteIDs = [Self.nearID]
        }
        // The map narrowed the list, but it has its own chip — the badge must not claim it.
        #expect(store.state.activeFilterCount == 2)
        #expect(store.state.isFiltered)
        await store.finish()
    }

    @Test("the map filter and the sheet filters compose")
    func mapAndSheetFiltersCompose() async {
        let store = await loadedMapStore()

        // Admits `far` on distance and excludes `near`.
        await store.send(.distanceFilterChanged(50_000...60_000)) {
            $0.filter.distanceMeters = 50_000...60_000
        }
        #expect(store.state.sheetFilteredRoutes.map(\.name) == ["Far"])

        // The viewport admits `near` and excludes `far`. Composed, nothing survives — which is
        // the point: neither filter overrides the other.
        await store.send(.mapRegionChanged(Self.nearViewport)) {
            $0.visibleMapBounds = Self.nearViewport
        }
        await store.send(.mapToggled) {
            $0.showsMap = false
            $0.mapFilterBounds = Self.nearViewport
            $0.mapFilteredRouteIDs = [Self.nearID]
        }
        #expect(store.state.filteredRoutes.isEmpty)
        #expect(store.state.routes.count == 2)
        await store.finish()
    }

    @Test("clearing the sheet filters leaves the map filter alone")
    func filtersClearedLeavesTheMapFilter() async {
        let store = await loadedMapStore()
        await store.send(.distanceFilterChanged(20_000...30_000)) {
            $0.filter.distanceMeters = 20_000...30_000
        }
        await store.send(.mapRegionChanged(Self.nearViewport)) {
            $0.visibleMapBounds = Self.nearViewport
        }
        await store.send(.mapToggled) {
            $0.showsMap = false
            $0.mapFilterBounds = Self.nearViewport
            $0.mapFilteredRouteIDs = [Self.nearID]
        }

        await store.send(.filtersCleared) { $0.filter = RouteFilter() }
        #expect(store.state.mapFilterBounds == Self.nearViewport)
        #expect(store.state.filteredRoutes.map(\.name) == ["Near"])
        await store.finish()
    }

    @Test("a route with no elevation data is not dropped by the gain filter")
    func nilGainRouteSurvivesTheGainFilter() async {
        let flatID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
        let noElevation = Self.summary(
            id: flatID, name: "No Elevation", distanceMeters: 25_000, elevationGainMeters: nil,
            bounds: Self.near.bounds
        )
        let routes = [Self.near, Self.far, noElevation]
        let store = makeStore(persistenceClient: .mock(routes: routes))
        await store.send(.task)
        await store.receive(\.reloadRoutes)
        await store.receive(\.routesResponse) {
            $0.hasLoaded = true
            $0.routes = routes
        }

        await store.send(.elevationGainFilterChanged(150)) {
            $0.filter.maxElevationGainMeters = 150
        }
        #expect(store.state.filteredRoutes.map(\.name) == ["Near", "No Elevation"])
        await store.finish()
    }

    @Test("an import that lengthens the library does not widen a cap the rider set")
    func importDoesNotWidenAnActiveFilter() async {
        let routes = [Self.near, Self.far]
        let store = makeStore(persistenceClient: .mock(routes: routes))
        await store.send(.task)
        await store.receive(\.reloadRoutes)
        await store.receive(\.routesResponse) {
            $0.hasLoaded = true
            $0.routes = routes
        }

        await store.send(.distanceFilterChanged(20_000...30_000)) {
            $0.filter.distanceMeters = 20_000...30_000
        }

        let epicID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
        let epic = Self.summary(id: epicID, name: "Epic", distanceMeters: 200_000,
                                elevationGainMeters: 4_000, bounds: Self.far.bounds)
        await store.send(.importResponse(.success(epic))) {
            $0.routes.insert(epic, at: 0)
        }
        // The cap survives the domain growing, and the new route is correctly outside it.
        #expect(store.state.filter.distanceMeters == 20_000...30_000)
        #expect(store.state.filteredRoutes.map(\.name) == ["Near"])
        await store.finish()
    }

    @Test("deleting the last route with elevation drops a gain filter that could not be undone")
    func deletingTheLastElevationRouteDropsTheGainFilter() async {
        let flatID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D2")!
        let flat = Self.summary(id: flatID, name: "Flat", distanceMeters: 25_000,
                                elevationGainMeters: nil, bounds: Self.near.bounds)
        let routes = [Self.near, flat]
        let store = makeStore(persistenceClient: .mock(routes: routes))
        await store.send(.task)
        await store.receive(\.reloadRoutes)
        await store.receive(\.routesResponse) {
            $0.hasLoaded = true
            $0.routes = routes
        }
        await store.send(.elevationGainFilterChanged(50)) {
            $0.filter.maxElevationGainMeters = 50
        }

        // With `near` gone, nothing carries an elevation, so the sheet hides the gain row —
        // and a filter left set behind a hidden control can never be undone.
        await store.send(.deleteButtonTapped(Self.nearID)) {
            $0.routes = [flat]
            $0.filter.maxElevationGainMeters = nil
        }
        #expect(store.state.activeFilterCount == 0)
        await store.finish()
    }

    @Test("each chip clears only its own filter")
    func chipsClearIndividually() async {
        let store = await loadedMapStore()
        await store.send(.distanceFilterChanged(20_000...30_000)) {
            $0.filter.distanceMeters = 20_000...30_000
        }
        await store.send(.elevationGainFilterChanged(400)) {
            $0.filter.maxElevationGainMeters = 400
        }
        await store.send(.distanceFilterCleared) { $0.filter.distanceMeters = nil }
        #expect(store.state.filter.maxElevationGainMeters == 400)
        await store.send(.elevationGainFilterCleared) { $0.filter.maxElevationGainMeters = nil }
        #expect(store.state.activeFilterCount == 0)
        await store.finish()
    }

    @Test("clearing everything takes the map narrowing with it")
    func allFiltersClearedIncludesTheMap() async {
        // The no-matches empty state's only action. Clearing the sheet's two alone would leave
        // the screen still empty and the reason for it still applied.
        let store = await loadedMapStore()
        await store.send(.distanceFilterChanged(20_000...30_000)) {
            $0.filter.distanceMeters = 20_000...30_000
        }
        await store.send(.mapRegionChanged(Self.nearViewport)) {
            $0.visibleMapBounds = Self.nearViewport
        }
        await store.send(.mapToggled) {
            $0.showsMap = false
            $0.mapFilterBounds = Self.nearViewport
            $0.mapFilteredRouteIDs = [Self.nearID]
        }

        await store.send(.allFiltersCleared) {
            $0.filter = RouteFilter()
            $0.dismissedMapBounds = Self.nearViewport
            $0.mapFilterBounds = nil
            $0.mapFilteredRouteIDs = nil
        }
        #expect(!store.state.isFiltered)
        #expect(store.state.filteredRoutes.count == 2)
        await store.finish()
    }

    // MARK: Sheet presentation

    @Test("the filter button opens the sheet and Done closes it")
    func sheetPresentation() async {
        let store = makeStore(persistenceClient: .mock(routes: [Self.near]))
        await store.send(.filterButtonTapped) { $0.isFilterSheetPresented = true }
        await store.send(.filterSheetPresentationChanged(false)) { $0.isFilterSheetPresented = false }
        await store.finish()
    }
}
