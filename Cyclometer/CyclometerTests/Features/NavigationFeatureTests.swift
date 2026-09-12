import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// #197 — route following, turn announcements and off-route, driven one fix at a time.
///
/// Every route is built in metres (`RouteFixtures`) and every fix is placed by how far along the
/// route it is and how far to the side, so each test reads as the ride it describes. Maneuvers are
/// seeded where a test is about matching or timing, and derived through `NavigationRoute(detail:)`
/// where it is about the whole path from a polyline to an announcement.
@MainActor
@Suite("NavigationFeature")
struct NavigationFeatureTests {

    private static let start = Date(timeIntervalSince1970: 1_000_000)

    /// 40 km/h — where PRD §8.6's ±10 m is hardest to hold: 11.1 m between fixes.
    nonisolated private static let fortyKPH = 40 / 3.6

    /// Every placement of the fixes relative to the lead point, a metre apart across one fix's
    /// ground. Derived from `expectedFixInterval`, so a change to it re-sweeps the range it covers.
    nonisolated static let fixPhases = Array(stride(from: 0.0, to: fortyKPH * NavigationFeature.expectedFixInterval, by: 1))

    /// A route along a line, with no turns in it.
    private let straight: [RouteFixtures.Leg] = [(0, 3_000)]

    /// Out 1 km, a 4 m jog east, back 600 m, then right. The way back runs 4 m east of the way out,
    /// and a rider keeping right is 3 m east of the way out going out — 1 m from the way back —
    /// and 3 m west of the way back coming home — 1 m from the way out. Whichever leg the rider is
    /// on, the other one is nearer.
    private let outAndBack: [RouteFixtures.Leg] = [(0, 1_000), (90, 4), (180, 600), (270, 300)]

    // MARK: - Harness

    /// A store whose `AppPreferences` live in their own in-memory storage. The state is built
    /// inside that scope so its `@SharedReader` resolves there, not against whatever
    /// `app-preferences.json` the machine running the suite has — `ActiveRideFeatureTests`' pattern.
    private func makeStore(
        route: NavigationRoute?,
        progressMeters: Double? = nil,
        leadMeters: Double = AppPreferences.defaultTurnLeadDistanceMeters,
        exhaustive: Bool = false,
        clock: TestClock<Duration> = TestClock(),
        persistenceClient: PersistenceClient = .testValue
    ) -> TestStoreOf<NavigationFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.turnLeadDistanceMeters = leadMeters }
            var state = NavigationFeature.State()
            state.activeRoute = route
            state.progressMeters = progressMeters
            let store = TestStore(initialState: state) {
                NavigationFeature()
            } withDependencies: {
                $0.continuousClock = clock
                $0.persistenceClient = persistenceClient
                $0.defaultFileStorage = storage
            }
            if !exhaustive { store.exhaustivity = .off }
            return store
        }
    }

    private func route(_ legs: [RouteFixtures.Leg], turns: [(meters: Double, direction: Maneuver.Direction)]) throws -> NavigationRoute {
        try #require(NavigationRoute(
            coordinates: RouteFixtures.path(legs: legs),
            maneuvers: turns.map {
                Maneuver(
                    coordinate: RouteFixtures.point(along: legs, at: $0.meters),
                    direction: $0.direction,
                    name: nil,
                    distanceAlongRouteMeters: $0.meters
                )
            }
        ))
    }

    private func outAndBackRoute() throws -> NavigationRoute {
        try route(outAndBack, turns: [(1_002, .uTurn), (1_604, .right)])
    }

    /// A fix `meters` along `legs` and `lateral` metres right of the direction of travel, `second`
    /// seconds into the ride. The course is the leg's own bearing unless given; `-1` is none.
    private func fix(
        _ legs: [RouteFixtures.Leg],
        at meters: Double,
        lateral: Double = 0,
        speed: Double = 10,
        second: Double,
        course: Double? = nil,
        accuracy: Double = 5
    ) -> LocationUpdate {
        RouteFixtures.fix(
            RouteFixtures.point(along: legs, at: meters, lateralMeters: lateral),
            speed: speed,
            at: Self.start.addingTimeInterval(second),
            course: course ?? RouteFixtures.bearing(along: legs, at: meters),
            horizontalAccuracy: accuracy
        )
    }

    // MARK: - Turn timing

    @Test("a turn is announced within ±10 m of the lead distance at 40 km/h, wherever the fixes fall", arguments: fixPhases)
    func turnIsAnnouncedWithinTenMetresAtFortyKPH(phase: Double) async throws {
        let legs: [RouteFixtures.Leg] = [(0, 1_000), (90, 300)]
        let store = makeStore(route: try route(legs, turns: [(1_000, .right)]))

        var announcedAt: Double?
        var second = 0.0
        for meters in stride(from: phase, through: 1_000, by: Self.fortyKPH) {
            await store.send(.locationUpdated(fix(legs, at: meters, speed: Self.fortyKPH, second: second)))
            second += 1
            if store.state.announcedManeuverIndex == 0 {
                announcedAt = 1_000 - meters
                break
            }
        }

        let error = try #require(announcedAt) - AppPreferences.defaultTurnLeadDistanceMeters
        #expect(abs(error) <= 10)
        // The rule's own bound, half the ground between fixes, with a centimetre for arithmetic.
        #expect(abs(error) <= Self.fortyKPH * NavigationFeature.expectedFixInterval / 2 + 0.01)
        await store.skipInFlightEffects(strict: false)
    }

    @Test("the rider's lead distance is the one used")
    func leadDistanceComesFromPreferences() async throws {
        let store = makeStore(route: try route(straight, turns: [(1_000, .right)]), leadMeters: 200)
        await store.send(.locationUpdated(fix(straight, at: 700, second: 0)))
        #expect(store.state.announcedManeuverIndex == nil)
        // 200 m out: announced at a 200 m lead, where the default 100 m would still be waiting.
        await store.send(.locationUpdated(fix(straight, at: 800, second: 1)))
        #expect(store.state.announcedManeuverIndex == 0)
        await store.skipInFlightEffects(strict: false)
    }

    // MARK: - Approach, announce, advance

    @Test("each turn of a multi-turn route is announced once, in order, and passed at its apex")
    func multiTurnRouteAnnouncesEachTurnOnce() async throws {
        let legs: [RouteFixtures.Leg] = [(0, 300), (90, 300), (0, 300), (270, 300)]
        let navigation = try #require(NavigationRoute(detail: RouteDetail(
            summary: .empty, coordinates: RouteFixtures.path(legs: legs), cuePoints: []
        )))
        // The derivation is #192's to test; this only pins the fixture everything below relies on.
        try #require(navigation.maneuvers.map(\.direction) == [.right, .left, .left])

        let store = makeStore(route: navigation)
        var announced: [(index: Int, distance: Double)] = []
        var second = 0.0
        for meters in stride(from: 0.0, through: 1_200, by: 10) {
            let before = store.state.announcedManeuverIndex
            await store.send(.locationUpdated(fix(legs, at: meters, second: second)))
            second += 1
            if let index = store.state.announcedManeuverIndex, index != before {
                let distance = try #require(store.state.distanceToNextTurnMeters)
                announced.append((index, distance))
            }
            // The alert holds from its announcement to the turn itself — the window PRD §8.9
            // suspends calibration over.
            for (index, maneuver) in navigation.maneuvers.enumerated() {
                let toGo = maneuver.distanceAlongRouteMeters - meters
                if toGo > 0, toGo <= 90 {
                    #expect(store.state.announcedManeuverIndex == index, "at \(meters) m")
                }
            }
        }

        #expect(announced.map(\.index) == [0, 1, 2])
        for announcement in announced {
            #expect(abs(announcement.distance - AppPreferences.defaultTurnLeadDistanceMeters) <= 10)
        }
        #expect(store.state.nextManeuverIndex == 3)
        #expect(!store.state.isTurnAlertActive)
        await store.skipInFlightEffects(strict: false)
    }

    @Test("the turn banner shows the turn and dismisses itself; the alert holds until the turn")
    func turnBannerDismissesItself() async throws {
        let legs: [RouteFixtures.Leg] = [(0, 600), (90, 100)]
        let clock = TestClock()
        let store = makeStore(route: try route(legs, turns: [(600, .right)]), clock: clock)

        await store.send(.locationUpdated(fix(legs, at: 500, second: 0)))
        #expect(store.state.turnBanner?.direction == .right)

        await clock.advance(by: NavigationFeature.bannerDismissDelay)
        await store.receive(\.bannerDismissed) {
            $0.turnBanner = nil
        }
        #expect(store.state.isTurnAlertActive)
    }

    @Test("the banner reads the cue's own words, or the direction when there are none")
    func bannerText() {
        let named = Maneuver(
            coordinate: RouteFixtures.origin, direction: .left, name: "Turn left onto Elm St", distanceAlongRouteMeters: 0
        )
        #expect(NavigationFeature.bannerText(for: named) == "Turn left onto Elm St")

        let expected: [(Maneuver.Direction, String)] = [
            (.left, "Turn left"), (.right, "Turn right"),
            (.slightLeft, "Bear left"), (.slightRight, "Bear right"),
            (.uTurn, "Make a U-turn"),
        ]
        #expect(expected.count == Maneuver.Direction.allCases.count)
        for (direction, text) in expected {
            // Whitespace is no name at all.
            let bare = Maneuver(coordinate: RouteFixtures.origin, direction: direction, name: "  ", distanceAlongRouteMeters: 0)
            #expect(NavigationFeature.bannerText(for: bare) == text)
        }
    }

    // MARK: - Staying on the leg being ridden

    @Test("an out-and-back is followed out and back, though the other leg is always the nearer")
    func outAndBackStaysOnTheLegBeingRidden() async throws {
        let store = makeStore(route: try outAndBackRoute())
        var second = 0.0
        // The whole way out — including the last 250 m, where the way back lies inside the window.
        for meters in stride(from: 0.0, through: 990, by: 10) {
            await store.send(.locationUpdated(fix(outAndBack, at: meters, lateral: 3, second: second)))
            second += 1
            #expect(abs((store.state.progressMeters ?? -1) - meters) < 2, "riding out at \(meters) m")
            #expect(store.state.nextManeuverIndex == 0, "riding out at \(meters) m")
        }
        // And home again, where the way out is the nearer.
        for meters in stride(from: 1_014.0, through: 1_590, by: 10) {
            await store.send(.locationUpdated(fix(outAndBack, at: meters, lateral: 3, second: second)))
            second += 1
            #expect(abs((store.state.progressMeters ?? -1) - meters) < 2, "riding back at \(meters) m")
        }
        #expect(store.state.nextManeuverIndex == 1)
        #expect(store.state.announcedManeuverIndex == 1)
        #expect(!store.state.isOffRoute)
        await store.skipInFlightEffects(strict: false)
    }

    @Test("a rider who turns around short of the turnaround is followed home")
    func earlyTurnaroundIsFollowedHome() async throws {
        let store = makeStore(route: try outAndBackRoute())
        var second = 0.0
        // Out along the west edge, 1 m left of the way-out line and so nearer it than the way back:
        // position alone keeps this stretch on the way out, and it is asserted so that a slip here
        // cannot quietly leave the match somewhere the rest of the test happens to agree with.
        for meters in stride(from: 0.0, through: 940, by: 10) {
            await store.send(.locationUpdated(fix(outAndBack, at: meters, lateral: -1, second: second)))
            second += 1
            #expect(abs((store.state.progressMeters ?? -1) - meters) < 2, "riding out at \(meters) m")
        }
        // Turned 60 m short and riding home down the same west edge — 1 m from the way out, 5 m
        // from the way back — so only the course says which leg this is.
        for north in stride(from: 930.0, through: 410, by: -10) {
            let alongTheWayBack = 1_004 + (1_000 - north)
            await store.send(.locationUpdated(fix(outAndBack, at: alongTheWayBack, lateral: 5, second: second)))
            second += 1
            #expect(abs((store.state.progressMeters ?? -1) - alongTheWayBack) < 2, "\(north) m north, riding home")
        }
        // The U-turn counts as made, and the next turn home is the one announced.
        #expect(store.state.nextManeuverIndex == 1)
        #expect(store.state.announcedManeuverIndex == 1)
        #expect(!store.state.isOffRoute)
        await store.skipInFlightEffects(strict: false)
    }

    // MARK: - Off route

    @Test("off route is raised on the fifth fix in a row beyond 50 m, and not before")
    func offRouteNeedsFiveMissesInARow() async throws {
        let store = makeStore(route: try route(straight, turns: []))
        await store.send(.locationUpdated(fix(straight, at: 500, second: 0)))
        // A second apart from the first fix off the road, so the fifth is within PRD §8.6's five
        // seconds of leaving it.
        for miss in 1...NavigationFeature.offRouteConsecutiveFixes {
            await store.send(.locationUpdated(fix(straight, at: 500 + Double(miss) * 10, lateral: 60, second: Double(miss))))
            #expect(store.state.isOffRoute == (miss == NavigationFeature.offRouteConsecutiveFixes), "after \(miss)")
        }
    }

    @Test("wobbling either side of 50 m never raises off route")
    func aFixInsideFiftyMetresRestartsTheCount() async throws {
        let store = makeStore(route: try route(straight, turns: []))
        await store.send(.locationUpdated(fix(straight, at: 500, second: 0)))
        for step in 1...20 {
            let second = Double(step)
            await store.send(.locationUpdated(
                fix(straight, at: 500 + second * 10, lateral: step.isMultiple(of: 2) ? 45 : 55, second: second)
            ))
            #expect(!store.state.isOffRoute, "step \(step)")
        }
    }

    @Test("once off route, only a fix within 30 m brings the rider back")
    func rejoiningNeedsThirtyMetres() async throws {
        let store = makeStore(route: try route(straight, turns: []))
        var second = 0.0
        await store.send(.locationUpdated(fix(straight, at: 500, second: second)))
        for _ in 1...NavigationFeature.offRouteConsecutiveFixes {
            second += 1
            await store.send(.locationUpdated(fix(straight, at: 500 + second * 10, lateral: 60, second: second)))
        }
        try #require(store.state.isOffRoute)

        // 35–45 m off: inside the 50 m that raised it, outside the 30 m that clears it.
        for step in 1...6 {
            second += 1
            await store.send(.locationUpdated(
                fix(straight, at: 500 + second * 10, lateral: step.isMultiple(of: 2) ? 35 : 45, second: second)
            ))
            #expect(store.state.isOffRoute, "step \(step)")
        }

        second += 1
        await store.send(.locationUpdated(fix(straight, at: 500 + second * 10, lateral: 25, second: second)))
        #expect(!store.state.isOffRoute)
        #expect(abs((store.state.progressMeters ?? -1) - (500 + second * 10)) < 2)
    }

    @Test("leaving the route drops the turn ahead, and coming back before it announces it again")
    func offRouteDropsTheTurnAndRejoiningRestoresIt() async throws {
        let store = makeStore(route: try route(straight, turns: [(700, .left)]))
        await store.send(.locationUpdated(fix(straight, at: 600, second: 0)))
        try #require(store.state.announcedManeuverIndex == 0)

        for miss in 1...NavigationFeature.offRouteConsecutiveFixes {
            await store.send(.locationUpdated(fix(straight, at: 600, lateral: 60, second: Double(miss))))
        }
        #expect(store.state.isOffRoute)
        #expect(store.state.turnBanner == nil)
        #expect(!store.state.isTurnAlertActive)

        await store.send(.locationUpdated(fix(straight, at: 650, second: 6)))
        #expect(!store.state.isOffRoute)
        #expect(store.state.announcedManeuverIndex == 0)
        #expect(store.state.turnBanner?.direction == .left)
        await store.skipInFlightEffects(strict: false)
    }

    @Test("a rider who never reaches the route is off route, and hears no turns")
    func neverJoiningIsOffRoute() async throws {
        let store = makeStore(route: try route(straight, turns: [(50, .right)]))
        for second in 0...NavigationFeature.offRouteConsecutiveFixes {
            await store.send(.locationUpdated(
                fix(straight, at: Double(second) * 10, lateral: 200, second: Double(second))
            ))
        }
        #expect(store.state.isOffRoute)
        #expect(store.state.snappedIndex == nil)
        #expect(store.state.announcedManeuverIndex == nil)
        #expect(store.state.turnBanner == nil)
    }

    @Test("rejoining further on skips the turns in between without announcing them")
    func rejoiningAheadSkipsTheTurnsBetween() async throws {
        let store = makeStore(route: try route(straight, turns: [(800, .left), (1_500, .right), (2_500, .left)]))
        var second = 0.0
        await store.send(.locationUpdated(fix(straight, at: 500, second: second)))
        // A parallel road 200 m east, ridden to 1.6 km.
        for meters in stride(from: 600.0, through: 1_600, by: 100) {
            second += 1
            await store.send(.locationUpdated(fix(straight, at: meters, lateral: 200, second: second)))
            #expect(store.state.announcedManeuverIndex == nil, "on the detour at \(meters) m")
        }
        try #require(store.state.isOffRoute)

        second += 1
        await store.send(.locationUpdated(fix(straight, at: 1_700, second: second)))
        #expect(!store.state.isOffRoute)
        #expect(abs((store.state.progressMeters ?? -1) - 1_700) < 2)
        #expect(store.state.nextManeuverIndex == 2)
        #expect(store.state.announcedManeuverIndex == nil)
    }

    // MARK: - Route end

    @Test("reaching the end stops everything, and riding on past it is not off route")
    func reachingTheEndStopsCleanly() async throws {
        let legs: [RouteFixtures.Leg] = [(0, 500)]
        let store = makeStore(route: try route(legs, turns: [(250, .right)]))
        var second = 0.0
        for meters in stride(from: 0.0, through: 480, by: 10) {
            await store.send(.locationUpdated(fix(legs, at: meters, second: second)))
            second += 1
        }
        #expect(store.state.isRouteComplete)
        #expect(store.state.nextManeuverIndex == 1)
        #expect(store.state.distanceToNextTurnMeters == nil)
        #expect(!store.state.isTurnAlertActive)

        // Home from the finish: 200 m on, well clear of the route's end.
        let finished = store.state
        for meters in stride(from: 490.0, through: 700, by: 10) {
            await store.send(.locationUpdated(fix(legs, at: meters, second: second)))
            second += 1
        }
        #expect(store.state == finished)
        #expect(!store.state.isOffRoute)
        await store.skipInFlightEffects(strict: false)
    }

    // MARK: - No route

    @Test("with no route, a fix changes nothing")
    func noRouteIgnoresFixes() async {
        let store = makeStore(route: nil, exhaustive: true)
        await store.send(.locationUpdated(fix(straight, at: 100, second: 0)))
        await store.send(.routeLoaded(nil))
    }

    @Test("a fix CoreLocation marks invalid is ignored")
    func invalidFixIsIgnored() async throws {
        let store = makeStore(route: try route(straight, turns: []), exhaustive: true)
        await store.send(.locationUpdated(fix(straight, at: 100, second: 0, accuracy: -1)))
    }

    @Test("loading a saved route derives its turns")
    func loadingARouteDerivesItsTurns() async throws {
        let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000197"))
        let legs: [RouteFixtures.Leg] = [(0, 300), (90, 300)]
        let detail = RouteDetail(summary: .empty, coordinates: RouteFixtures.path(legs: legs), cuePoints: [])
        let expected = try #require(NavigationRoute(detail: detail))
        try #require(!expected.maneuvers.isEmpty)

        let store = makeStore(route: nil, exhaustive: true, persistenceClient: .mock(routeDetails: [id: detail]))
        await store.send(.loadRoute(id))
        await store.receive(.routeLoaded(expected)) {
            $0.activeRoute = expected
        }
    }

    @Test("a route that no longer exists, or has one point, loads as no route")
    func unusableRoutesLoadAsNone() async throws {
        let missing = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let onePoint = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let detail = RouteDetail(summary: .empty, coordinates: [RouteFixtures.origin], cuePoints: [])

        let store = makeStore(route: nil, exhaustive: true, persistenceClient: .mock(routeDetails: [onePoint: detail]))
        await store.send(.loadRoute(missing))
        await store.receive(.routeLoaded(nil))
        await store.send(.loadRoute(onePoint))
        await store.receive(.routeLoaded(nil))
    }

    // MARK: - Resume

    @Test("a relaunch looks for the rider from the checkpointed progress")
    func resumeLooksFromTheCheckpointedProgress() async throws {
        // Relaunched standing still on the way back, 1,350 m in — the same spot as 654 m in on the
        // way out. No course to go on, so only the checkpoint can tell the two apart.
        let standing = fix(outAndBack, at: 1_350, lateral: 3, speed: 0, second: 0, course: -1)

        let resumed = makeStore(route: try outAndBackRoute(), progressMeters: 1_300)
        await resumed.send(.locationUpdated(standing))
        #expect(abs((resumed.state.progressMeters ?? -1) - 1_350) < 2)
        #expect(resumed.state.nextManeuverIndex == 1)

        let unanchored = makeStore(route: try outAndBackRoute())
        await unanchored.send(.locationUpdated(standing))
        #expect(abs((unanchored.state.progressMeters ?? -1) - 654) < 2)
    }

    @Test("with no checkpoint, a moving rider's course finds the leg they are on")
    func courseFindsTheLegWithoutACheckpoint() async throws {
        let store = makeStore(route: try outAndBackRoute())
        await store.send(.locationUpdated(fix(outAndBack, at: 1_350, lateral: 3, speed: 8, second: 0)))
        #expect(abs((store.state.progressMeters ?? -1) - 1_350) < 2)
        #expect(store.state.nextManeuverIndex == 1)
    }
}
