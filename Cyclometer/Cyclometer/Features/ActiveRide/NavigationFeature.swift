import ComposableArchitecture
import Foundation
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "navigation")

/// Follows the route a ride was started on (#197): places the rider on its polyline, tracks how
/// far along it they are, announces each turn at the rider's lead distance, and says when they
/// have left the route. Nothing reroutes — PRD §15 keeps that out of scope, so off-route is a
/// banner and no more.
///
/// `ActiveRideFeature` loads the route at `.task` and forwards each fix only while the route is
/// being followed (`isFollowingRoute`), so a free ride — and a ride with turn-by-turn off, whose
/// route is only drawn on the map — never reaches the matching at all.
///
/// # Where on the route the rider is
///
/// The obvious answer — the nearest point anywhere on the polyline — is wrong for every route that
/// passes the same place twice. An out-and-back lays both legs on one road, so a rider still riding
/// out is as near the way back, and snapping there skips everything in between. Four things keep
/// the match on the leg being ridden:
///
/// - **A window.** Once placed, the rider is matched only within `backWindowMeters` behind and
///   `forwardWindowMeters` ahead of the last match.
/// - **Direction.** While the GPS course means something (`courseSpeedFloorMPS`), a segment running
///   against it is not a candidate. Within 250 m of a turnaround the way back is inside the window,
///   and a rider who turns around short of the turnaround is on it; the course tells them apart.
/// - **Continuity.** Of what is left, the match that moves the rider least far from where they were
///   expected to be wins, not simply the nearest (`continuityWeight`). A stopped rider has no course,
///   and without this a metre of scatter could move them onto a later pass of the same road —
///   past turns they would then never be told about.
/// - **The first pass, not the nearest,** wherever there is no match to window around — ride start,
///   off-route, a relaunch mid-ride. It is searched from just behind `progressMeters`, which the
///   ride checkpoints to its `Ride` so that a relaunch resumes on the leg it was on.
///
/// # Loops
///
/// A loop's end is also its start, so arriving there is ambiguous: a rider who joined 200 m before
/// the end has not finished the loop by reaching it. A loop is finished only once the rider has
/// ridden at least half of it since their run began (`lapStartMeters`); short of that, the match
/// carries on round from the start, as the road does.
///
/// # When a turn is announced
///
/// PRD §8.6 allows ±10 m of the lead distance, and at 40 km/h a rider covers 11.1 m between fixes,
/// so announcing at the first fix inside the lead distance can be 11 m late. A turn is announced
/// instead at the fix nearer the lead point than the next one is expected to be: when what remains
/// beyond the lead distance is at most half the ground the next fix will cover. That halves the
/// worst case to 5.6 m at 40 km/h, early or late.
@Reducer
struct NavigationFeature {

    /// How far behind the last match the next may land. Enough for GPS scatter and a rider rolling
    /// back at a junction, which move the match metres, not hundreds.
    static let backWindowMeters = 100.0

    /// How far ahead of the last match the next may land — dozens of fixes' riding, so a run of
    /// dropped fixes cannot outpace it, and still a short stretch of any real route.
    static let forwardWindowMeters = 500.0

    /// Further than this from the route counts against being on it.
    static let offRouteMeters = 50.0

    /// How many fixes in a row have to miss the route before the rider is told. At CoreLocation's
    /// 1 Hz the fifth lands within PRD §8.6's five seconds of leaving, and a few fixes of scatter
    /// past 50 m never raise it.
    static let offRouteConsecutiveFixes = 5

    /// Once off-route, the rider has to come this close to be back on. Nearer than
    /// `offRouteMeters` on purpose: a rider running 40–50 m from the route would otherwise flap in
    /// and out of it.
    static let rejoinMeters = 30.0

    /// Within this of the end, the route is done: no more turns, and riding on past the finish —
    /// home, say — is not being off-route.
    static let arrivalMeters = 30.0

    /// How close a route's two ends have to be for it to be a loop — the distance a fix is matched
    /// within, so a rider at a loop's start is within reach of its end as well.
    static let loopClosureMeters = 50.0

    /// Below this the GPS course is noise, and matching ignores which way a leg runs. 2 m/s is
    /// 7 km/h: slower than anyone rides, faster than anyone standing still reads.
    static let courseSpeedFloorMPS = 2.0

    /// How much moving along the route counts against a match, in metres of offset per metre moved
    /// from where the rider was expected to be. A tenth: a 400 m jump onto the other leg of an
    /// out-and-back costs 40 m, far more than the few metres separating the legs, while a genuine
    /// 20 m between fixes costs 2 m, inside what a fix's own offset varies by.
    static let continuityWeight = 0.1

    /// CoreLocation's delivery interval on iPhone. Turn timing splits the difference against the
    /// ground the next fix is expected to cover in it; fixes arriving faster only bring the next
    /// one nearer, which keeps the error inside the same bound.
    static let expectedFixInterval: TimeInterval = 1

    /// How long the turn instruction stays up. Matches `SpeedFeature`'s banner.
    static let instructionDuration: Duration = .seconds(4)

    /// PRD §8.6's wording.
    static let offRouteBannerText = "Off route"

    /// What the overlay says for a turn: the cue's own words when the file gave some, which already
    /// read as an instruction ("Turn left onto County Road S"), otherwise the direction.
    ///
    /// No distance. The overlay appears at the lead distance and stays up for
    /// `instructionDuration`, so a distance frozen into its text would be wrong within a second;
    /// W9 (#200) is where a live one belongs.
    static func instructionText(for maneuver: Maneuver) -> String {
        if let name = maneuver.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        switch maneuver.direction {
        case .left: return "Turn left"
        case .right: return "Turn right"
        case .slightLeft: return "Bear left"
        case .slightRight: return "Bear right"
        case .uTurn: return "Make a U-turn"
        }
    }

    @Dependency(\.persistenceClient) var persistenceClient
    @Dependency(\.continuousClock) var clock

    @ObservableState
    struct State: Equatable {
        /// Read-only: the rider's lead distance and whether they have turn-by-turn on.
        @SharedReader(.appPreferences) var preferences
        /// Nil for a free ride, until the route has loaded, and for a route that no longer exists.
        var activeRoute: NavigationRoute? = nil
        /// How far along the route the rider last matched, in metres.
        ///
        /// Checkpointed to the `Ride` and restored on relaunch, where it is the floor the first
        /// search looks from — which is what puts a rider resumed on the way back of an out-and-back
        /// on the way back. Kept, not cleared, while off-route: it is also where rejoining searches
        /// from.
        var progressMeters: Double? = nil
        /// The segment of the last match *this session*. Nil until one is made — including after a
        /// relaunch, where `progressMeters` is restored but not yet confirmed by a fix.
        var snappedIndex: Int? = nil
        /// Where the rider's current unbroken run along the route began: their first match, a
        /// rejoin after off-route, or a new lap of a loop — and 0 for a resumed ride, whose run
        /// began before the kill. What finishing a loop is measured from.
        var lapStartMeters: Double? = nil
        /// Index into `activeRoute.maneuvers` of the next turn ahead; `maneuvers.count` once past
        /// the last. Only goes back when a loop comes round to its start again.
        var nextManeuverIndex = 0
        /// The turn whose alert has fired and which the rider has not yet passed. Wheel calibration
        /// stands down while this is set (PRD §8.9).
        var announcedManeuverIndex: Int? = nil
        var offRouteStreak = 0
        var isOffRoute = false
        var isRouteComplete = false
        /// The turn on the dashboard's centred overlay, nil when hidden — the maneuver rather than
        /// its text, so the overlay can draw its arrow.
        var turnInstruction: Maneuver? = nil

        /// Whether fixes are being matched to the route at all: there is one, and the rider has
        /// turn-by-turn on (#197 review). Off, the route is only drawn on the map — no turns, no
        /// off-route.
        var isFollowingRoute: Bool { activeRoute != nil && preferences.isTurnByTurnEnabled }

        var nextManeuver: Maneuver? {
            guard let maneuvers = activeRoute?.maneuvers, maneuvers.indices.contains(nextManeuverIndex)
            else { return nil }
            return maneuvers[nextManeuverIndex]
        }

        /// Along the route to the next turn, or nil when there is none or the rider is not on the
        /// route to measure from. W9 (#200) reads this.
        var distanceToNextTurnMeters: Double? {
            guard let nextManeuver, let progressMeters, snappedIndex != nil, !isOffRoute, !isRouteComplete
            else { return nil }
            return nextManeuver.distanceAlongRouteMeters - progressMeters
        }

        var isTurnAlertActive: Bool { announcedManeuverIndex != nil }
    }

    enum Action: Equatable {
        /// Sent by `ActiveRideFeature.task` for a ride that has a route, fresh or resumed.
        case loadRoute(UUID)
        case routeLoaded(NavigationRoute?)
        case locationUpdated(LocationUpdate)
        case instructionDismissed
    }

    private enum CancelID { case instructionTimer }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .loadRoute(let id):
                // In the effect rather than the reducer: decoding the polyline and deriving its
                // turns walks every point, and a route can have tens of thousands.
                return .run { [persistenceClient] send in
                    do {
                        guard let detail = try await persistenceClient.fetchRoute(id) else {
                            // A `Ride.routeId` may legitimately outlive its route.
                            logger.notice("route \(id, privacy: .public) no longer exists — riding without navigation")
                            await send(.routeLoaded(nil))
                            return
                        }
                        guard let route = NavigationRoute(detail: detail) else {
                            logger.notice("route \(id, privacy: .public) has too few points to follow")
                            await send(.routeLoaded(nil))
                            return
                        }
                        await send(.routeLoaded(route))
                    } catch {
                        logger.error(
                            "route \(id, privacy: .public) failed to load: \(error.localizedDescription, privacy: .public) — riding without navigation"
                        )
                        await send(.routeLoaded(nil))
                    }
                }

            case .routeLoaded(let route):
                state.activeRoute = route
                guard let route else { return .none }
                // A resumed ride's run along the route began before the kill, so its lap counts from
                // the start: a relaunch late in a loop still finishes it at the end.
                if state.progressMeters != nil, state.lapStartMeters == nil { state.lapStartMeters = 0 }
                logger.notice(
                    """
                    route loaded — \(route.maneuvers.count, privacy: .public) turns over \
                    \(route.totalDistanceMeters, format: .fixed(precision: 0), privacy: .public) m\
                    \(route.isLoop ? ", a loop" : "", privacy: .public)
                    """
                )
                return .none

            case .locationUpdated(let update):
                return follow(update, &state)

            case .instructionDismissed:
                state.turnInstruction = nil
                return .none
            }
        }
    }

    // MARK: - Following

    private func follow(_ update: LocationUpdate, _ state: inout State) -> Effect<Action> {
        // A negative accuracy is CoreLocation saying the position itself is meaningless
        // (`GPSFixFilter`). A merely poor one still counts: under tree cover accuracy can stay poor
        // for minutes, and navigation that paused for it would stop announcing turns just where the
        // road is hardest to read.
        guard state.isFollowingRoute, let route = state.activeRoute, !state.isRouteComplete,
              update.horizontalAccuracy > 0
        else { return .none }

        guard let match = match(update, on: route, state) else { return missedRoute(&state) }
        let progress = match.projection.distanceAlongRouteMeters

        if state.isOffRoute || state.snappedIndex == nil || match.wrapped {
            // Read out first: `Logger`'s interpolations are escaping autoclosures, and cannot
            // capture an `inout` parameter.
            let event = match.wrapped ? "round the loop" : state.isOffRoute ? "back on route" : "on route"
            logger.notice(
                "\(event, privacy: .public) at \(progress, format: .fixed(precision: 0), privacy: .public) m"
            )
        }
        // A run along the route begins at a rider's first match, a rejoin and a new lap. A resumed
        // ride's began before the kill, and `.routeLoaded` has already set it.
        if match.wrapped || state.isOffRoute || state.lapStartMeters == nil {
            state.lapStartMeters = progress
        }
        if match.wrapped {
            // A new lap: every turn from here on is ahead again.
            state.nextManeuverIndex = route.maneuvers.firstIndex { $0.distanceAlongRouteMeters > progress }
                ?? route.maneuvers.count
            state.announcedManeuverIndex = nil
        }
        state.isOffRoute = false
        state.offRouteStreak = 0
        state.progressMeters = progress
        state.snappedIndex = match.projection.segmentIndex

        // Past every turn now behind the rider — including any a rejoin or a relaunch skipped over,
        // which go unannounced because they are behind.
        while let maneuver = state.nextManeuver, maneuver.distanceAlongRouteMeters <= progress {
            if state.announcedManeuverIndex == state.nextManeuverIndex { state.announcedManeuverIndex = nil }
            state.nextManeuverIndex += 1
        }

        if hasFinished(at: progress, on: route, lapStart: state.lapStartMeters) {
            state.isRouteComplete = true
            state.announcedManeuverIndex = nil
            logger.notice("route complete")
            return .none
        }
        return announceTurnIfDue(speed: update.speed, &state)
    }

    /// A place on the route for a fix, and whether reaching it went round the end of a loop.
    private struct Match {
        var projection: RouteGeometry.Projection
        var wrapped = false
    }

    /// Where this fix puts the rider on the route, or nil when it puts them nowhere on it.
    private func match(_ update: LocationUpdate, on route: NavigationRoute, _ state: State) -> Match? {
        let point = RouteCoordinate(
            latitude: update.coordinate.latitude,
            longitude: update.coordinate.longitude,
            elevationMeters: nil
        )
        // CoreLocation's course is -1 when it has none.
        let course = update.heading >= 0 && update.speed >= Self.courseSpeedFloorMPS ? update.heading : nil

        guard let progress = state.progressMeters, state.snappedIndex != nil, !state.isOffRoute else {
            return RouteGeometry.passes(
                of: point,
                onto: route.coordinates,
                cumulative: route.cumulativeDistances,
                fromMeters: max(0, (state.progressMeters ?? 0) - Self.backWindowMeters),
                within: state.isOffRoute ? Self.rejoinMeters : Self.offRouteMeters,
                heading: course,
                limit: 1
            ).first.map { Match(projection: $0) }
        }

        let total = route.totalDistanceMeters
        let reach = progress + Self.forwardWindowMeters
        var candidates = RouteGeometry.candidates(
            of: point,
            onto: route.coordinates,
            cumulative: route.cumulativeDistances,
            alongRoute: (progress - Self.backWindowMeters)...reach,
            heading: course
        ).map { (match: Match(projection: $0), along: $0.distanceAlongRouteMeters) }
        // Round the end of a loop and on from its start, counted a lap further along.
        if route.isLoop, reach > total {
            candidates += RouteGeometry.candidates(
                of: point,
                onto: route.coordinates,
                cumulative: route.cumulativeDistances,
                alongRoute: 0...(reach - total),
                heading: course
            ).map { (match: Match(projection: $0, wrapped: true), along: $0.distanceAlongRouteMeters + total) }
        }

        let expected = progress + max(update.speed, 0) * Self.expectedFixInterval
        func cost(_ candidate: (match: Match, along: Double)) -> Double {
            candidate.match.projection.offsetMeters + Self.continuityWeight * abs(candidate.along - expected)
        }
        return candidates
            .filter { $0.match.projection.offsetMeters <= Self.offRouteMeters }
            .min { cost($0) < cost($1) }?
            .match
    }

    /// Whether a match this far along finishes the route. A loop's end is also its start, so there
    /// it takes having ridden at least half the loop since the run began; anywhere else, arriving
    /// is enough.
    private func hasFinished(at progress: Double, on route: NavigationRoute, lapStart: Double?) -> Bool {
        guard progress >= route.totalDistanceMeters - Self.arrivalMeters else { return false }
        guard route.isLoop else { return true }
        return progress - (lapStart ?? progress) >= route.totalDistanceMeters / 2
    }

    /// A fix that puts the rider nowhere on the route. It counts toward off-route and moves nothing
    /// else: the last match stays where the rider was last known to be.
    private func missedRoute(_ state: inout State) -> Effect<Action> {
        guard !state.isOffRoute else { return .none }
        state.offRouteStreak += 1
        guard state.offRouteStreak >= Self.offRouteConsecutiveFixes else { return .none }
        state.isOffRoute = true
        // The turn ahead is not ahead of a rider who has left the route. If they come back before
        // it, rejoining announces it again.
        state.announcedManeuverIndex = nil
        state.turnInstruction = nil
        let lastOnRoute = state.progressMeters ?? 0
        logger.notice("off route — last on it at \(lastOnRoute, format: .fixed(precision: 0), privacy: .public) m")
        return .cancel(id: CancelID.instructionTimer)
    }

    private func announceTurnIfDue(speed: Double, _ state: inout State) -> Effect<Action> {
        guard let distance = state.distanceToNextTurnMeters,
              let maneuver = state.nextManeuver,
              state.announcedManeuverIndex != state.nextManeuverIndex
        else { return .none }
        let lead = state.preferences.turnLeadDistanceMeters
        // See "When a turn is announced" above. An unknown speed (CoreLocation's -1) predicts no
        // movement, which falls back to announcing at the first fix inside the lead distance.
        guard distance - lead <= max(speed, 0) * Self.expectedFixInterval / 2 else { return .none }

        let index = state.nextManeuverIndex
        state.announcedManeuverIndex = index
        state.turnInstruction = maneuver
        logger.notice(
            """
            turn \(index, privacy: .public) announced \
            \(distance, format: .fixed(precision: 1), privacy: .public) m out \
            (lead \(lead, format: .fixed(precision: 0), privacy: .public) m)
            """
        )
        return .run { send in
            try await clock.sleep(for: Self.instructionDuration)
            await send(.instructionDismissed)
        }
        .cancellable(id: CancelID.instructionTimer, cancelInFlight: true)
    }
}

/// A route as navigation follows it: its polyline, how far along it each point lies, and its
/// turns — worked out once when the ride loads it, so no fix pays for any of it.
///
/// One value rather than separate fields, because none of them means anything without the others.
struct NavigationRoute: Equatable, Sendable {
    let coordinates: [RouteCoordinate]
    let cumulativeDistances: [Double]
    let maneuvers: [Maneuver]
    /// Whether the route ends where it starts (`NavigationFeature.loopClosureMeters`), so that its
    /// end is also its start. An out-and-back is one too.
    let isLoop: Bool

    var totalDistanceMeters: Double { cumulativeDistances.last ?? 0 }

    /// Nil for a polyline with no segment to follow: a one-point GPX imports fine
    /// (`GPXRouteImporter` rejects only an empty one).
    init?(coordinates: [RouteCoordinate], maneuvers: [Maneuver]) {
        guard coordinates.count > 1, let first = coordinates.first, let last = coordinates.last else { return nil }
        self.coordinates = coordinates
        self.cumulativeDistances = RouteGeometry.cumulativeDistances(coordinates)
        self.maneuvers = maneuvers
        self.isLoop = RouteGeometry.distanceMeters([first, last]) <= NavigationFeature.loopClosureMeters
    }

    /// Derives the turns (#192) here, at load, rather than reading a stored copy — there is none,
    /// so a fix to the derivation reaches routes imported before it.
    init?(detail: RouteDetail) {
        self.init(coordinates: detail.coordinates, maneuvers: TurnDerivation.maneuvers(for: detail))
    }
}
