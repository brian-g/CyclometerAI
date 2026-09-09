import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

/// The S19 import path with nothing stubbed below the reducer (#193): a real `.gpx` on disk,
/// the real `GPXRouteImporter`, the real `RoutePersistenceActor`, and a real SQLite store.
///
/// The reducer tests cover the same actions against `PersistenceClient.mock`, which proves the
/// state machine but not that anything reaches SQLite. This proves the whole hop — and the
/// second container at the same URL is what "survives relaunch" actually means, since a
/// container opened fresh from disk is exactly what a cold launch does.
@MainActor
@Suite("Routes import — end to end")
struct RoutesImportIntegrationTests {

    /// A RideWithGPS-shaped file: `<trk>` geometry, `<ele>` throughout, and a `<wpt>` cue.
    private static let gpx = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="RideWithGPS">
      <trk>
        <name>Coastal Loop</name>
        <desc>Rolling coastal terrain</desc>
        <trkseg>
          <trkpt lat="37.3349" lon="-122.0090"><ele>30</ele></trkpt>
          <trkpt lat="37.3420" lon="-122.0150"><ele>48</ele></trkpt>
          <trkpt lat="37.3510" lon="-122.0240"><ele>72</ele></trkpt>
          <trkpt lat="37.3600" lon="-122.0120"><ele>55</ele></trkpt>
          <trkpt lat="37.3480" lon="-121.9980"><ele>34</ele></trkpt>
        </trkseg>
      </trk>
      <wpt lat="37.3420" lon="-122.0150"><name>Turn left onto Foothill</name><type>Left</type></wpt>
    </gpx>
    """

    private func writeGPX(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoutesImportIntegration-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Self.gpx.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("A picked .gpx reaches SQLite and is still there when the store is reopened")
    func importSurvivesAColdOpen() async throws {
        let url = try writeGPX(named: "Coastal Loop.gpx")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try await withTemporaryStoreURL(prefix: "RoutesImport") { storeURL in
            let storage = FileStorage.inMemory

            // First "launch": the reducer imports through the live client.
            let imported: RouteSummary = try await {
                let container = try openStore(at: storeURL)
                let client = PersistenceClient.live(
                    coreDataContainer: CoreDataStack(inMemory: true).container,
                    modelContainer: container
                )
                let store = withDependencies {
                    $0.defaultFileStorage = storage
                } operation: {
                    TestStore(initialState: RoutesFeature.State()) {
                        RoutesFeature()
                    } withDependencies: {
                        $0.persistenceClient = client
                        $0.locationClient = .testValue
                        $0.permissionsClient = .mock(initial: [.locationWhenInUse: .denied])
                        $0.defaultFileStorage = storage
                    }
                }
                store.exhaustivity = .off

                await store.send(.fileSelected(url))
                await store.receive(\.importResponse)
                await store.finish()

                #expect(store.state.alert == nil, "import reported a failure")
                let route = try #require(store.state.routes.first)
                #expect(store.state.routes.count == 1)
                return route
            }()

            // The file's own name and description, not `Route.defaultName`.
            #expect(imported.name == "Coastal Loop")
            #expect(imported.terrainDescription == "Rolling coastal terrain")
            #expect(imported.coordinateCount == 5)
            // ~4.6 km around the loop, and 42 m of gain over the noise threshold.
            #expect(imported.distanceMeters > 3_000 && imported.distanceMeters < 8_000)
            #expect(imported.elevationGainMeters != nil)

            // Second "launch": a brand-new container over the same file, as a cold start does.
            let reopened = PersistenceClient.live(
                coreDataContainer: CoreDataStack(inMemory: true).container,
                modelContainer: try openStore(at: storeURL)
            )
            let onDisk = try await reopened.fetchRoutes()
            #expect(onDisk.map(\.id) == [imported.id])
            #expect(onDisk.first?.name == "Coastal Loop")

            // The polyline and the file's cue survived external storage.
            let detail = try #require(try await reopened.fetchRoute(imported.id))
            #expect(detail.coordinates.count == 5)
            #expect(detail.cuePoints.first?.name == "Turn left onto Foothill")

            // And the delete the swipe action performs is durable too.
            try await reopened.deleteRoute(imported.id)
            let afterDelete = PersistenceClient.live(
                coreDataContainer: CoreDataStack(inMemory: true).container,
                modelContainer: try openStore(at: storeURL)
            )
            #expect(try await afterDelete.fetchRoutes().isEmpty)
        }
    }
}
