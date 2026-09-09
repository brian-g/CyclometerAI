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

    private static func summary(
        id: UUID = UUID(), name: String = "River Loop",
        terrain: String? = "Rolling terrain", distanceMeters: Double = 36_050
    ) -> RouteSummary {
        var summary = RouteSummary.empty
        summary.id = id
        summary.name = name
        summary.terrainDescription = terrain
        summary.distanceMeters = distanceMeters
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

    nonisolated private static func summary(_ id: UUID, _ name: String) -> RouteSummary {
        var summary = RouteSummary.empty
        summary.id = id
        summary.name = name
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
