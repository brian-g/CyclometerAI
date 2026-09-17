import ComposableArchitecture
import Foundation
import SwiftData
import Testing
@testable import Cyclometer

/// #201: the M8 navigation pipeline with nothing stubbed between a `.gpx` on disk and a turn's tone.
///
/// Every layer already has its own suite — `NavigationFeatureTests` follows hand-built routes,
/// `RoutesImportIntegrationTests` imports into SQLite, `AppRouteSelectionTests` carries a route to
/// the ride against a mock store, `RoutePersistenceTests` and `ActiveRideFeatureTests` cover delete
/// and resume. This one proves they agree: a checked-in file goes through the real importer into
/// an on-disk store, out through S20's Use Route and the Start sheet, into a ride that loads it back
/// from that store, and fixes placed along it come out as turns, tones and an off-route banner.
///
/// A "launch" is a fresh `AppFeature` store over a new container on the same store file, which is
/// exactly what a cold start opens. Nothing is ever seeded into navigation state: the only way a
/// route reaches a ride here is the way a rider's does.
@MainActor
@Suite("Navigation pipeline — end to end")
struct NavigationPipelineTests {

    private static let start = Date(timeIntervalSince1970: 1_000_000)
    private static let lead = AppPreferences.defaultTurnLeadDistanceMeters

    /// What `NavigationPipeline.gpx` says: three cued turns, 1,000 m, 1,600 m and 2,100 m along a
    /// 2,500 m point-to-point route.
    private static let routeName = "Reynolda Connector"
    private static let cues: [(name: String, direction: Maneuver.Direction)] = [
        ("Turn left onto Silas Creek Parkway", .left),
        ("Turn right onto Reynolda Road", .right),
        ("Turn left onto Polo Road", .left),
    ]

    /// Loaded from the test bundle, where the synchronized `CyclometerTests` group copies it.
    private static var fixtureURL: URL {
        get throws {
            try #require(
                Bundle(for: BundleToken.self).url(forResource: "NavigationPipeline", withExtension: "gpx"),
                "NavigationPipeline.gpx is not in the test bundle"
            )
        }
    }
    private final class BundleToken {}

    // MARK: - Harness

    /// One store file, and everything that outlives a launch: the rider's preferences, the
    /// track-point stack, and what the speaker was asked to play.
    ///
    /// `@unchecked Sendable` so `expectEventually`'s predicates can read the store file through it:
    /// every stored property is a `let`, and the mutable ones are `LockIsolated`.
    @MainActor
    private final class Harness: @unchecked Sendable {
        let storeURL: URL
        let storage = FileStorage.inMemory
        let coreData = CoreDataStack(inMemory: true)
        let gpxDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NavigationPipeline-\(UUID().uuidString)", isDirectory: true)
        /// Every turn tone played, in order.
        let tones = LockIsolated<[Maneuver.Direction]>([])
        /// Every route read the app makes.
        let routeFetches = LockIsolated(0)
        /// The test's own view of the store, uncounted — what it reads to check the app's writes.
        let reader: PersistenceClient
        nonisolated private let readerContainer: ModelContainer

        init(storeURL: URL) throws {
            self.storeURL = storeURL
            readerContainer = try openStore(at: storeURL)
            reader = PersistenceClient.live(coreDataContainer: coreData.container, modelContainer: readerContainer)
        }

        deinit { try? FileManager.default.removeItem(at: gpxDirectory) }

        /// A cold start: a new container on the store file, and a new `AppFeature` over it.
        func launch() throws -> TestStoreOf<AppFeature> {
            var client = PersistenceClient.live(
                coreDataContainer: coreData.container,
                modelContainer: try openStore(at: storeURL)
            )
            let fetchRoute = client.fetchRoute
            client.fetchRoute = { [routeFetches] id in
                routeFetches.withValue { $0 += 1 }
                return try await fetchRoute(id)
            }
            var audio = AudioClient.testValue
            audio.playTurn = { [tones] direction in tones.withValue { $0.append(direction) } }

            return withDependencies {
                $0.defaultFileStorage = storage
            } operation: {
                @Shared(.appPreferences) var preferences
                $preferences.withLock {
                    $0.hasCompletedOnboarding = true
                    $0.turnLeadDistanceMeters = NavigationPipelineTests.lead
                    $0.isTurnByTurnEnabled = true
                }
                let store = TestStore(initialState: AppFeature.State()) {
                    AppFeature()
                } withDependencies: {
                    $0.defaultFileStorage = storage
                    $0.persistenceClient = client
                    $0.audioClient = audio
                    $0.gpxDocumentsDirectory = gpxDirectory
                    $0.continuousClock = TestClock()
                    $0.date = .constant(NavigationPipelineTests.start)
                    $0.uuid = .incrementing
                    $0.bleCSCClient = .testValue
                    $0.variaRadarClient = .testValue
                    $0.bleHRClient = .testValue
                    $0.screenClient = .testValue
                    $0.hapticsClient = .testValue
                    $0.locationClient = .testValue
                    $0.permissionsClient = .mock(initial: [.locationWhenInUse: .denied])
                }
                store.exhaustivity = .off(showSkippedAssertions: false)
                return store
            }
        }

        /// The `Ride` row as the store file has it now.
        nonisolated func rideRow(_ id: UUID) -> Ride? {
            var descriptor = FetchDescriptor<Ride>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try? ModelContext(readerContainer).fetch(descriptor).first
        }
    }

    /// Picks the fixture on S19, and returns the route it became.
    private func importFixture(on store: TestStoreOf<AppFeature>) async throws -> RouteSummary {
        let before = Set(store.state.routes.routes.map(\.id))
        await store.send(.routes(.fileSelected(try Self.fixtureURL)))
        await store.receive(\.routes.importResponse, timeout: effectDrainTimeout)
        #expect(store.state.routes.alert == nil, "import reported a failure")
        return try #require(store.state.routes.routes.first { !before.contains($0.id) })
    }

    /// Pushes S20 for `summary`, taps Use Route, then the Start sheet's Start Ride, and waits for the
    /// ride to load the route back out of the store.
    private func startRide(on summary: RouteSummary, _ store: TestStoreOf<AppFeature>) async throws -> NavigationRoute {
        let detail = withDependencies { $0 = store.dependencies } operation: {
            RouteDetailFeature.State(summary: summary)
        }
        await store.send(.routes(.path(.push(id: 0, state: .detail(detail)))))
        await store.send(.routes(.path(.element(id: 0, action: .detail(.useRouteButtonTapped)))))
        await store.receive(\.routes.delegate.useRoute, summary.reference)
        #expect(store.state.startSheet?.route == summary.reference)

        await store.send(.startSheet(.presented(.startRideButtonTapped)))
        await store.receive(\.activeRide.navigation.routeLoaded, timeout: effectDrainTimeout)
        #expect(store.state.activeRide?.route == summary.reference)
        return try #require(store.state.activeRide?.navigation.activeRoute)
    }

    /// Rides `polyline` from `from` to `through` metres at `kph`, one fix a second, `lateral` metres
    /// right of it. `second` carries the clock across calls; `afterEach` sees each fix's distance
    /// along the polyline, and its second, once the app has handled it.
    private func ride(
        _ store: TestStoreOf<AppFeature>,
        along polyline: [RouteCoordinate],
        from: Double,
        through: Double,
        kph: Double,
        lateral: Double = 0,
        second: inout Double,
        afterEach: (_ meters: Double, _ second: Double) -> Void = { _, _ in }
    ) async {
        let mps = kph / 3.6
        for meters in stride(from: from, through: through, by: mps) {
            await store.send(.activeRide(.locationUpdated(RouteFixtures.fix(
                RouteFixtures.point(alongPolyline: polyline, at: meters, lateralMeters: lateral),
                speed: mps,
                at: Self.start.addingTimeInterval(second),
                course: RouteFixtures.bearing(alongPolyline: polyline, at: meters),
                horizontalAccuracy: 5
            ))))
            // The ride hands the fix on as an effect, so navigation has not seen it when `send`
            // returns. It only hands it on while the route is being followed.
            if store.state.activeRide?.navigation.isFollowingRoute == true {
                await store.receive(\.activeRide.navigation.locationUpdated)
            }
            afterEach(meters, second)
            second += 1
        }
    }

    /// Thirty ticks: one checkpoint of the ride to its `Ride` row, as a ride running that long does.
    private func checkpoint(_ store: TestStoreOf<AppFeature>) async {
        for _ in 0..<30 { await store.send(.activeRide(.elapsedTick)) }
    }

    /// Polls an async read until it holds. The bounded wait `expectEventually` is, for reads that
    /// go through the persistence actors.
    private func eventually(
        _ comment: Comment,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () async throws -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while clock.now < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try await condition(), comment, sourceLocation: sourceLocation)
    }

    // MARK: - Turns

    @Test("a GPX file on disk fires each turn's tone within ±10 m of the lead distance", arguments: [20.0, 30.0, 40.0])
    func turnsFireWithinTenMetres(kph: Double) async throws {
        try await withTemporaryStoreURL(prefix: "NavigationPipeline") { url in
            let harness = try Harness(storeURL: url)
            let store = try harness.launch()
            let summary = try await importFixture(on: store)
            #expect(summary.name == Self.routeName)
            let route = try await startRide(on: summary, store)

            // The file's cues, not turns the geometry found: without their names this would pass
            // just as well with every cue silently dropped.
            #expect(route.maneuvers.map(\.name) == Self.cues.map(\.name))
            #expect(route.maneuvers.map(\.direction) == Self.cues.map(\.direction))
            #expect(abs(RouteFixtures.length(ofPolyline: route.coordinates) - route.totalDistanceMeters) < 0.5)

            let rideId = try #require(store.state.activeRide?.rideId)
            await expectEventually { harness.rideRow(rideId) != nil }
            #expect(harness.rideRow(rideId)?.routeId == summary.id)
            #expect(harness.rideRow(rideId)?.routeName == Self.routeName)

            var announcedAt: [Int: Double] = [:]
            var second = 0.0
            await ride(store, along: route.coordinates, from: 0, through: route.totalDistanceMeters, kph: kph, second: &second) { meters, _ in
                if let index = store.state.activeRide?.navigation.announcedManeuverIndex, announcedAt[index] == nil {
                    announcedAt[index] = meters
                }
            }

            for (index, maneuver) in route.maneuvers.enumerated() {
                let at = try #require(announcedAt[index], "turn \(index) was never announced")
                let error = maneuver.distanceAlongRouteMeters - at - Self.lead
                #expect(abs(error) <= 10, "turn \(index) announced \(error) m off the lead at \(kph) km/h")
            }
            #expect(store.state.activeRide?.navigation.isRouteComplete == true)
            let cueCount = Self.cues.count
            await expectEventually { harness.tones.value.count >= cueCount }
            #expect(harness.tones.value == Self.cues.map(\.direction))

            await store.skipInFlightEffects(strict: false)
        }
    }

    // MARK: - Off route

    @Test("leaving the route raises Off route within 5 s, and rejoining clears it")
    func offRouteWithinFiveSecondsAndClearsOnRejoin() async throws {
        try await withTemporaryStoreURL(prefix: "NavigationPipeline") { url in
            let harness = try Harness(storeURL: url)
            let store = try harness.launch()
            let route = try await startRide(on: try await importFixture(on: store), store)
            let banner = {
                RideDashboardView.banner(
                    sourceSwitch: nil,
                    calibration: nil,
                    isOffRoute: store.state.activeRide?.navigation.isOffRoute ?? false
                )?.text
            }

            // Past the first turn, and on down the second leg.
            var second = 0.0
            await ride(store, along: route.coordinates, from: 0, through: 1_300, kph: 30, second: &second)
            let lastOnRoute = second - 1
            #expect(banner() == nil)

            // Onto a road 80 m over.
            var raisedAt: Double?
            await ride(store, along: route.coordinates, from: 1_308, through: 1_360, kph: 30, lateral: 80, second: &second) { _, fixSecond in
                if raisedAt == nil, store.state.activeRide?.navigation.isOffRoute == true { raisedAt = fixSecond }
            }
            let raised = try #require(raisedAt, "never raised off route")
            #expect(raised - lastOnRoute <= 5)
            #expect(banner() == NavigationFeature.offRouteBannerText)

            // Back on, well before the second turn's lead point.
            await ride(store, along: route.coordinates, from: 1_368, through: 1_368, kph: 30, second: &second)
            #expect(store.state.activeRide?.navigation.isOffRoute == false)
            #expect(banner() == nil)

            // And the turns ahead of the rejoin are still announced.
            await ride(store, along: route.coordinates, from: 1_376, through: route.totalDistanceMeters, kph: 30, second: &second)
            let cueCount = Self.cues.count
            await expectEventually { harness.tones.value.count >= cueCount }
            #expect(harness.tones.value == Self.cues.map(\.direction))

            await store.skipInFlightEffects(strict: false)
        }
    }

    @Test("a route the rider never joins is off route, with no turns")
    func neverJoinedRouteIsOffRouteWithoutTurns() async throws {
        try await withTemporaryStoreURL(prefix: "NavigationPipeline") { url in
            let harness = try Harness(storeURL: url)
            let store = try harness.launch()
            let route = try await startRide(on: try await importFixture(on: store), store)

            // The route's shape the whole way, a kilometre to its right — nowhere near any of it.
            var fixes = 0
            var second = 0.0
            await ride(store, along: route.coordinates, from: 0, through: route.totalDistanceMeters, kph: 30, lateral: 1_000, second: &second) { _, _ in
                fixes += 1
                let navigation = store.state.activeRide?.navigation
                #expect(navigation?.snappedIndex == nil)
                #expect(navigation?.turnInstruction == nil)
                #expect(navigation?.isTurnAlertActive == false)
                if fixes >= NavigationFeature.offRouteConsecutiveFixes {
                    #expect(navigation?.isOffRoute == true, "still not off route after \(fixes) fixes")
                }
            }
            #expect(store.state.activeRide?.navigation.isRouteComplete == false)

            await store.skipInFlightEffects(strict: false)
            #expect(harness.tones.value.isEmpty)
        }
    }

    // MARK: - No route

    @Test("a ride with no route never touches navigation, through a checkpoint and a relaunch")
    func noRouteRideNeverTouchesNavigation() async throws {
        try await withTemporaryStoreURL(prefix: "NavigationPipeline") { url in
            let harness = try Harness(storeURL: url)
            let rideId: UUID
            do {
                let store = try harness.launch()
                // A route exists — it just isn't the ride's.
                let summary = try await importFixture(on: store)
                let polyline = try #require(try await harness.reader.fetchRoute(summary.id)).coordinates
                let untouched = withDependencies { $0 = store.dependencies } operation: { NavigationFeature.State() }

                await store.send(.startRideButtonTapped)
                #expect(store.state.startSheet?.route == nil)
                await store.send(.startSheet(.presented(.startRideButtonTapped)))
                await store.receive(\.activeRide.task)
                rideId = try #require(store.state.activeRide?.rideId)
                #expect(store.state.activeRide?.route == nil)

                // `routeLoaded` could never be skipped past silently: every fix checks the state it would set.
                let untouchedAfterEachFix: (Double, Double) -> Void = { meters, _ in
                    #expect(store.state.activeRide?.navigation == untouched, "navigation moved at \(meters) m")
                }
                // The same track as the off-route test: along it, 80 m off it, and back.
                var second = 0.0
                await ride(store, along: polyline, from: 0, through: 1_300, kph: 30, second: &second, afterEach: untouchedAfterEachFix)
                await ride(store, along: polyline, from: 1_308, through: 1_360, kph: 30, lateral: 80, second: &second, afterEach: untouchedAfterEachFix)
                await ride(store, along: polyline, from: 1_368, through: 2_500, kph: 30, second: &second, afterEach: untouchedAfterEachFix)

                await checkpoint(store)
                await expectEventually { harness.rideRow(rideId)?.durationSeconds == 30 }
                #expect(harness.rideRow(rideId)?.routeId == nil)
                #expect(harness.rideRow(rideId)?.routeName == nil)
                #expect(harness.rideRow(rideId)?.routeProgressMeters == nil)
                let resumable = try #require(try await harness.reader.fetchResumableRide())
                #expect(resumable.route == nil)
                #expect(resumable.routeProgressMeters == nil)

                // The kill: nothing ends the ride, and nothing is drained.
                await store.skipInFlightEffects(strict: false)
            }

            let relaunched = try harness.launch()
            await relaunched.send(.task)
            await relaunched.receive(\.resumableRideFetched, timeout: effectDrainTimeout)
            await relaunched.receive(\.activeRide.task)
            #expect(relaunched.state.activeRide?.rideId == rideId)
            #expect(relaunched.state.activeRide?.route == nil)
            let untouched = withDependencies { $0 = relaunched.dependencies } operation: { NavigationFeature.State() }
            #expect(relaunched.state.activeRide?.navigation == untouched)

            await relaunched.skipInFlightEffects(strict: false)
            #expect(harness.routeFetches.value == 0)
            #expect(harness.tones.value.isEmpty)
        }
    }

    // MARK: - Deleted route

    @Test("a deleted route leaves its rides' routeName, and a re-import starts with no history")
    func deletedRouteKeepsHistoryOffItsReimport() async throws {
        try await withTemporaryStoreURL(prefix: "NavigationPipeline") { url in
            let harness = try Harness(storeURL: url)
            let original: RouteSummary
            let rideId: UUID
            do {
                let store = try harness.launch()
                original = try await importFixture(on: store)
                let route = try await startRide(on: original, store)
                rideId = try #require(store.state.activeRide?.rideId)

                var second = 0.0
                await ride(store, along: route.coordinates, from: 0, through: 1_100, kph: 30, second: &second)
                await store.send(.activeRide(.pauseTapped))
                await store.send(.activeRide(.finishTapped))
                await store.send(.activeRide(.finishAlert(.presented(.confirmFinish))))
                #expect(store.state.activeRide == nil)
                await expectEventually { harness.rideRow(rideId)?.endedAt != nil }

                await store.send(.routes(.deleteButtonTapped(original.id)))
                try await eventually("the route was never deleted") {
                    try await harness.reader.fetchRoutes().isEmpty
                }
                await store.skipInFlightEffects(strict: false)
            }

            // Cold: the route is gone, the ride remembers what it was ridden on.
            let store = try harness.launch()
            #expect(try await harness.reader.fetchRoutes().isEmpty)
            #expect(harness.rideRow(rideId)?.routeName == Self.routeName)
            #expect(harness.rideRow(rideId)?.routeId == original.id)

            // The same file again is a new route, and none of the old one's rides come with it.
            let reimported = try await importFixture(on: store)
            #expect(reimported.id != original.id)
            #expect(!store.state.routes.routes.contains { $0.id == original.id })

            let detail = withDependencies { $0 = store.dependencies } operation: {
                RouteDetailFeature.State(summary: reimported)
            }
            await store.send(.routes(.path(.push(id: 0, state: .detail(detail)))))
            await store.send(.routes(.path(.element(id: 0, action: .detail(.task)))))
            await store.receive(\.routes.path[id: 0].detail.previousRidesLoaded, [], timeout: effectDrainTimeout)
            #expect(store.state.routes.path[id: 0]?.detail?.previousRides == [])

            // The old id still finds its ride — left dangling on purpose (#191) — but nothing on
            // S19 or S20 carries that id any more to ask with.
            #expect(try await harness.reader.fetchRouteRides(original.id).map(\.rideId) == [rideId])

            await store.skipInFlightEffects(strict: false)
        }
    }

    // MARK: - Crash recovery

    @Test("a ride killed mid-route relaunches still navigating")
    func killedRideRelaunchesStillNavigating() async throws {
        try await withTemporaryStoreURL(prefix: "NavigationPipeline") { url in
            let harness = try Harness(storeURL: url)
            let summary: RouteSummary
            let rideId: UUID
            var second = 0.0
            let killedAt = 1_350.0
            do {
                let store = try harness.launch()
                summary = try await importFixture(on: store)
                let route = try await startRide(on: summary, store)
                rideId = try #require(store.state.activeRide?.rideId)

                // Past the first turn, and 150 m short of the second's lead point.
                await ride(store, along: route.coordinates, from: 0, through: killedAt, kph: 30, second: &second)
                await expectEventually { harness.tones.value == [.left] }
                let progress = try #require(store.state.activeRide?.navigation.progressMeters)

                await checkpoint(store)
                await expectEventually { harness.rideRow(rideId)?.routeProgressMeters == progress }

                // The kill: nothing ends the ride, and nothing is drained.
                await store.skipInFlightEffects(strict: false)
            }
            harness.tones.setValue([])
            let fetchesBeforeRelaunch = harness.routeFetches.value

            let store = try harness.launch()
            await store.send(.task)
            await store.receive(\.resumableRideFetched, timeout: effectDrainTimeout)
            await store.receive(\.activeRide.navigation.routeLoaded, timeout: effectDrainTimeout)
            #expect(harness.routeFetches.value == fetchesBeforeRelaunch + 1)
            #expect(store.state.activeRide?.rideId == rideId)
            #expect(store.state.activeRide?.route == summary.reference)
            let navigation = try #require(store.state.activeRide?.navigation)
            let route = try #require(navigation.activeRoute)
            #expect(abs((navigation.progressMeters ?? -1) - killedAt) < 10)

            // Back on the road where the ride left off: the first turn is behind, the second next.
            let step = 30 / 3.6
            var announcedAt: [Int: Double] = [:]
            await ride(store, along: route.coordinates, from: killedAt + step, through: killedAt + step, kph: 30, second: &second)
            #expect(store.state.activeRide?.navigation.nextManeuverIndex == 1)
            #expect(store.state.activeRide?.navigation.announcedManeuverIndex == nil)

            await ride(store, along: route.coordinates, from: killedAt + 2 * step, through: route.totalDistanceMeters, kph: 30, second: &second) { meters, _ in
                if let index = store.state.activeRide?.navigation.announcedManeuverIndex, announcedAt[index] == nil {
                    announcedAt[index] = meters
                }
            }
            #expect(announcedAt[0] == nil)
            for index in 1..<route.maneuvers.count {
                let at = try #require(announcedAt[index], "turn \(index) was never announced after the relaunch")
                let error = route.maneuvers[index].distanceAlongRouteMeters - at - Self.lead
                #expect(abs(error) <= 10, "turn \(index) announced \(error) m off the lead")
            }
            await expectEventually { harness.tones.value.count >= 2 }
            #expect(harness.tones.value == [.right, .left])

            await store.skipInFlightEffects(strict: false)
        }
    }
}
