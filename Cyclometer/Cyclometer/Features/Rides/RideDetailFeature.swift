import ComposableArchitecture
import Foundation
import os

// Stream live: Console.app / Xcode console, filter subsystem "xyz.acmeapps.ride".
private let logger = Logger.cyclometer(.persistence)

/// S15 — Ride Detail: one finished ride's track, its stats, the dashboard's metric sheets over the
/// whole ride (#536), and the vehicles that passed it (#251).
///
/// Seeded with the `RideListSummary` S14's row already holds, so the title and date are on
/// screen from the first frame. Everything else is three reads — the CoreData track, the `Ride`
/// aggregates and the pass events — each shown as it lands, plus the Health values the HR zones
/// resolve against.
///
/// An element of `RidesFeature`'s navigation stack, like S20 in `RoutesFeature` (#195): the
/// reads run from `.task`, and `.forEach` cancels a popped element's effects.
@Reducer
struct RideDetailFeature {

    /// Points in S10's elevation chart. Enough for a smooth line at any phone width, without
    /// handing Swift Charts the ~4 200 points a 70-minute ride records — S20 uses the same count.
    static let chartSampleCount = RouteDetailFeature.elevationProfileSampleCount

    @ObservableState
    struct State: Equatable {
        /// Units follow the S12 picker — the same read-through `RidesFeature` does.
        @Shared(.appPreferences) var preferences

        /// The HR chart's zone bands follow S12's zones, overrides included.
        @SharedReader(.riderProfile) var riderProfile

        /// HealthKit's terms in `riderProfile`'s `override ?? health ?? default`, as S12 and
        /// the ride dashboard read them. Nil until fetched, and nil when Health has nothing.
        var healthRestingBPM: Int?
        var healthMaxBPM: Int?
        /// Health's preferred zones as ceilings (#238), the middle term of every zone boundary.
        var healthZoneCeilingsBPM: [Int]?

        var summary: RideListSummary

        /// One polyline per stretch of riding (#263). Empty until the track loads, and empty for
        /// good for a ride with no drawable track.
        var trackSegments: [[RouteCoordinate]] = []

        /// What the metric sections take from the track (#536). Nil until it loads, and nil for
        /// good if the read fails.
        var track: RideDetailTrack?

        /// The track read threw, so no header is coming.
        var trackReadFailed = false

        /// Nil until it loads, and nil for good if the read fails.
        var stats: RideStats?

        /// The saved route the ride followed, S15's link to S20 (#426). Nil for a free ride,
        /// and for one whose route has since been deleted — `stats.routeName` still names it.
        var route: RouteSummary?

        /// Oldest first.
        var vehiclePasses: [VehiclePassEventDTO] = []

        /// The one sheet S15 shows at a time (#538): the full-screen map, the pass list, or Edit.
        @Presents var destination: Destination.State?

        init(summary: RideListSummary) {
            self.summary = summary
        }

        /// Whether S15 keeps room for the map header (#538): once a drawable track has loaded,
        /// and while the track is still loading for a ride that covered ground, so the title
        /// block doesn't drop half a screen when the track lands. A ride with distance but no
        /// GPS track, such as one on a trainer with a speed sensor, gives the room back on load.
        var reservesMapHeader: Bool {
            if !trackSegments.isEmpty { return true }
            return track == nil && !trackReadFailed && summary.distanceMeters > 0
        }

        var unitSystem: UnitSystem { preferences.preferredUnit }

        /// Each zone's bpm range as S12's table shows it, zone 1 first — the chart's bands.
        /// Resolved now rather than stored with the ride, like every zone in the app.
        var heartRateZoneBounds: [ClosedRange<Int>] {
            HeartRateZone.allCases.map {
                riderProfile.bounds(for: $0, healthResting: healthRestingBPM, healthMax: healthMaxBPM,
                                    healthZoneCeilings: healthZoneCeilingsBPM)
            }
        }

        // The metric sections (#536), each nil until both the track and the stats have landed,
        // so a section never draws half-built, and nil for good when the ride has no data for it.
        // Built here rather than stored so they follow the units and zones as they change.

        var rideMetrics: RideMetrics? {
            guard let track, let stats else { return nil }
            return .wholeRide(track: track, stats: stats, summary: summary, unit: unitSystem)
        }

        var caloriesMetrics: CaloriesMetrics? {
            guard track != nil, let stats else { return nil }
            return .wholeRide(stats: stats, summary: summary)
        }

        var cadence: RideDetailCadence? {
            guard let track, let stats else { return nil }
            return .wholeRide(track: track, stats: stats, zones: preferences.cadenceZones)
        }

        var heartRateMetrics: HeartRateMetrics? {
            guard let track, let stats else { return nil }
            return .wholeRide(track: track, stats: stats, zoneBounds: heartRateZoneBounds)
        }

        var elevationMetrics: ElevationMetrics? {
            guard let track, let stats else { return nil }
            return .wholeRide(track: track, stats: stats, unit: unitSystem)
        }
    }

    enum Action: Equatable {
        case task
        case trackLoaded(segments: [[RouteCoordinate]], track: RideDetailTrack)
        case trackLoadFailed
        /// The route arrives with the stats, so the Route row never turns into a link
        /// after it is on screen.
        case statsLoaded(RideStats, route: RouteSummary?)
        case vehiclePassesLoaded([VehiclePassEventDTO])
        case healthProfileFetched(restingBPM: Int?, maxBPM: Int?, zoneCeilingsBPM: [Int]?)
        case mapTapped
        case passesTapped
        case editTapped
        /// A write of the edit failed. The store is the authority on what was saved, so the
        /// screen reads it back.
        case editFailed
        case editReverted(title: String, notes: String)
        case destination(PresentationAction<Destination.Action>)
        case delegate(Delegate)

        enum Delegate: Equatable {
            /// The rider saved a new title or notes, for S14 to reload (#538). Other S15s and S20s
            /// read the new title back when they next appear.
            case rideEdited(id: UUID, title: String, notes: String)
        }
    }

    /// S15's sheets (#538). `Equatable` in extensions below, as TCA asks.
    @Reducer
    enum Destination {
        case mapSheet(RideMapSheetFeature)
        case passes(RidePassesFeature)
        case edit(RideEditFeature)
    }

    @Dependency(\.persistenceClient) var persistenceClient
    @Dependency(\.healthKitClient) var healthKitClient
    @Dependency(\.altimeterClient) var altimeterClient
    @Dependency(\.date) var date

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            // Independent reads, merged rather than queued. A failure in any leaves its part of
            // the screen as it was — `RouteDetailFeature`'s handling.
            case .task:
                let id = state.summary.id
                return .merge(
                    .run { [persistenceClient, altimeterClient] send in
                        do {
                            let points = try await persistenceClient.fetchTrackPoints(id)
                            // `RideFinishStats.backfill`'s guess: a phone with a barometer most
                            // likely used it.
                            let source: AltitudeResolver.Source = altimeterClient.isAvailable() ? .barometric : .gps
                            // Derived here, once per load, rather than by the view on every body pass.
                            await send(.trackLoaded(
                                segments: RideMapThumbnail.drawableSegments(points),
                                track: RideDetailTrack(points: points, altitudeSource: source)
                            ))
                        } catch {
                            logger.error("fetchTrackPoints failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                            await send(.trackLoadFailed)
                        }
                    },
                    .run { [persistenceClient] send in
                        let stats: RideStats
                        do {
                            stats = try await persistenceClient.fetchRideStats(id)
                        } catch {
                            logger.error("fetchRideStats failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                            return
                        }
                        // Nil for a deleted route by design, so only a failed read is logged; either
                        // way the stats still show, and the Route row names the route without a link.
                        var route: RouteSummary?
                        if let routeId = stats.routeId {
                            do {
                                route = try await persistenceClient.fetchRouteSummary(routeId)
                            } catch {
                                logger.error("fetchRouteSummary failed for \(routeId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                            }
                        }
                        await send(.statsLoaded(stats, route: route))
                    },
                    .run { [persistenceClient] send in
                        do {
                            await send(.vehiclePassesLoaded(try await persistenceClient.fetchVehiclePassEvents(id)))
                        } catch {
                            logger.error("fetchVehiclePassEvents failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        }
                    },
                    // `SettingsFeature`'s read, so the bands match S12's table.
                    .run { [healthKitClient, date] send in
                        async let restingBPM = try? healthKitClient.fetchRestingHeartRate()
                        async let dob = try? healthKitClient.fetchDateOfBirth()
                        async let zoneCeilings = try? healthKitClient.fetchHeartRateZoneCeilings()
                        let maxBPM = RiderProfile.estimatedMaxBPM(fromDateOfBirth: await dob, on: date.now)
                        await send(.healthProfileFetched(restingBPM: await restingBPM, maxBPM: maxBPM, zoneCeilingsBPM: await zoneCeilings))
                    }
                )

            case let .trackLoaded(segments, track):
                state.trackSegments = segments
                state.track = track
                return .none

            case .trackLoadFailed:
                state.trackReadFailed = true
                return .none

            case let .statsLoaded(stats, route):
                state.stats = stats
                state.route = route
                if let title = stats.title { state.summary.title = title }
                return .none

            case .vehiclePassesLoaded(let passes):
                state.vehiclePasses = passes
                // An open map sheet copied the passes when it opened, maybe before they landed.
                if case var .mapSheet(sheet) = state.destination {
                    sheet.passes = passes
                    state.destination = .mapSheet(sheet)
                }
                return .none

            case let .healthProfileFetched(restingBPM, maxBPM, zoneCeilingsBPM):
                state.healthRestingBPM = restingBPM
                state.healthMaxBPM = maxBPM
                state.healthZoneCeilingsBPM = zoneCeilingsBPM
                return .none

            case .mapTapped:
                // The header is drawn only for a ride with a drawable track.
                guard !state.trackSegments.isEmpty else { return .none }
                state.destination = .mapSheet(RideMapSheetFeature.State(
                    segments: state.trackSegments, passes: state.vehiclePasses, unitSystem: state.unitSystem
                ))
                return .none

            case .passesTapped:
                state.destination = .passes(RidePassesFeature.State(
                    passes: state.vehiclePasses, unitSystem: state.unitSystem
                ))
                return .none

            case .editTapped:
                // Not before the stats land: the sheet would open on no notes, and a save would
                // write over the stored ones unseen. The view keeps Edit off until then.
                guard let stats = state.stats else { return .none }
                state.destination = .edit(RideEditFeature.State(title: state.summary.title, notes: stats.notes))
                return .none

            case let .destination(.presented(.edit(.delegate(.save(title, notes))))):
                // Written from here, not from the sheet: S15 stays on the stack, so this effect
                // outlives the sheet being closed. Shown at once, and read back if a write fails.
                let id = state.summary.id
                let isRenamed = title != state.summary.title
                let isNoteChanged = notes != (state.stats?.notes ?? "")
                state.destination = nil
                state.summary.title = title
                state.stats?.notes = notes
                return .run { [persistenceClient] send in
                    do {
                        // The notes first. A rename that lands must reach S14 and the GPX below,
                        // so it goes last: a failure then leaves at most the notes written, which
                        // every S15 reads back with its stats.
                        if isNoteChanged { try await persistenceClient.updateRideNotes(id, notes) }
                        if isRenamed { try await persistenceClient.renameRide(id, title) }
                    } catch {
                        logger.error("Saving the edit of ride \(id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                        await send(.editFailed)
                        return
                    }
                    // Before the rewrite below, which reads the whole track back, so S14 shows
                    // the new name at once.
                    await send(.delegate(.rideEdited(id: id, title: title, notes: notes)))
                    // The GPX carries the title (#286). A failed rewrite leaves the file as it
                    // was; the rename stands either way — `AppFeature`'s S10 rename.
                    guard isRenamed else { return }
                    do {
                        try await GPXExporter.rewrite(rideId: id)
                    } catch {
                        logger.error("Rewriting the GPX of renamed ride \(id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    }
                }

            case .editFailed:
                let id = state.summary.id
                return .run { [persistenceClient] send in
                    do {
                        let stats = try await persistenceClient.fetchRideStats(id)
                        await send(.editReverted(title: stats.title ?? "", notes: stats.notes))
                    } catch {
                        logger.error("Reading back ride \(id, privacy: .public) after a failed edit failed: \(error.localizedDescription, privacy: .public)")
                    }
                }

            case let .editReverted(title, notes):
                state.summary.title = title
                state.stats?.notes = notes
                return .none

            case .destination, .delegate:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension RideDetailFeature.Destination.State: Equatable {}
extension RideDetailFeature.Destination.Action: Equatable {}

/// S10's and S15's series, derived from the recorded track. Plain arithmetic, so it is tested
/// directly rather than through the charts.
enum RideDetailSeries {
    /// Elevation at `sampleCount` evenly spaced distances along the ride, the same
    /// distance-spaced profile S20 charts (`RouteGeometry.elevationProfile`). Nil for a ride
    /// with no drawable track, so the chart and the map agree about whether there is one —
    /// and for one with fewer than two valid altitudes to draw a profile from (#303).
    static func elevationProfile(_ points: [TrackPointDTO], sampleCount: Int) -> [Double]? {
        guard !RideMapThumbnail.drawableSegments(points).isEmpty else { return nil }
        let coordinates = points.map {
            RouteCoordinate(latitude: $0.latitude, longitude: $0.longitude, elevationMeters: $0.altitudeMeters)
        }
        return RouteGeometry.elevationProfile(coordinates, sampleCount: sampleCount)
    }

    /// How long an Apple Watch reading stands for the seconds after it. HealthKit delivers heart
    /// rate every few seconds to few minutes, and the recorder stamps a sample only on the second
    /// it arrives (`ActiveRideFeature.State.isHeartRateRecordable`); past this, the rider is
    /// treated as having no reading rather than an old one.
    static let appleWatchHoldSeconds: TimeInterval = 300

    /// Seconds spent at each heart rate, for S10's zone breakdown (#249). A histogram rather
    /// than the readings themselves: the zones it is sorted into resolve after the track loads,
    /// and a few hundred entries is all a ride of any length needs. Empty when no second had a
    /// reading.
    ///
    /// Each recorded second counts once. A BLE strap reads every second, so a second without one
    /// is a dropout and counts for nothing. An Apple Watch sample stands for the seconds after it,
    /// up to `appleWatchHoldSeconds` and never across a pause. Counting only stamped seconds
    /// would credit a 2 h Watch ride with minutes of zone time.
    static func secondsByBPM(_ points: [TrackPointDTO]) -> [Int: Int] {
        var tally = HeartRateSecondsTally()
        points.forEach { tally.add($0) }
        return tally.secondsByBPM
    }

    /// Seconds in each zone, zone 1 first, against `zoneBounds` (zone 1 first). A reading below
    /// zone 1 counts as zone 1 and one above zone 5 as zone 5.
    static func zoneSeconds(_ secondsByBPM: [Int: Int], zoneBounds: [ClosedRange<Int>]) -> [Int] {
        var zones = Array(repeating: 0, count: zoneBounds.count)
        guard !zones.isEmpty else { return zones }
        for (bpm, seconds) in secondsByBPM {
            let zone = zoneBounds.lastIndex { $0.lowerBound <= bpm } ?? 0
            zones[zone] += seconds
        }
        return zones
    }
}

/// `RideDetailSeries.secondsByBPM`, one track point at a time, so the live ride's Heart Rate
/// sheet (#145) counts the seconds S10 will count from the saved track, by the same rule.
struct HeartRateSecondsTally: Equatable, Sendable {
    private(set) var secondsByBPM: [Int: Int] = [:]
    /// The Apple Watch reading standing for the seconds after it.
    private var held: TrackPointDTO?

    /// A tally already holding `secondsByBPM`, for previews (S08's sample ride).
    init(secondsByBPM: [Int: Int] = [:]) {
        self.secondsByBPM = secondsByBPM
    }

    mutating func add(_ point: TrackPointDTO) {
        if let bpm = point.heartRateBPM {
            held = point.heartRateSource == .appleWatch ? point : nil
            secondsByBPM[bpm, default: 0] += 1
        } else if let reading = held, let bpm = reading.heartRateBPM,
                  reading.segmentIndex == point.segmentIndex,
                  point.timestamp.timeIntervalSince(reading.timestamp) <= RideDetailSeries.appleWatchHoldSeconds {
            secondsByBPM[bpm, default: 0] += 1
        }
    }

    /// Adds a resumed ride's seconds from before the kill (#393). Summing is exact: a held Watch
    /// reading never crosses a segment, and every point after a resume is in a newer one.
    mutating func add(secondsByBPM seconds: [Int: Int]) {
        secondsByBPM.merge(seconds, uniquingKeysWith: +)
    }
}
