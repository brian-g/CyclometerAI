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

        /// How the recorded wind met the rider (#151). Worked out once both the track and the
        /// stats are in, rather than by the view on every body pass. Nil without either, or for a
        /// ride with no weather or no moving track.
        var windExposure: RideWindExposure?

        /// WeatherKit's mark and legal link for the Weather section's footer (#151). Nil until
        /// it loads, and for a ride with no weather; `.offline` when WeatherKit can't be reached.
        var weatherAttribution: WeatherSourceAttribution?

        /// The saved route the ride followed, S15's link to S20 (#426). Nil for a free ride,
        /// and for one whose route has since been deleted — `stats.routeName` still names it.
        var route: RouteSummary?

        /// Oldest first.
        var vehiclePasses: [VehiclePassEventDTO] = []

        /// The one sheet S15 shows at a time (#538): the full-screen map, the pass list, or Edit.
        @Presents var destination: Destination.State?

        /// Strava records written since launch (#632), laid over the one the stats carried, so the
        /// Synced To row follows an upload and a reset.
        @SharedReader(.liveStravaSyncRecords) var liveSyncRecords
        /// Whether the ride is in Health (#632). Nil until read, after the stats.
        var healthPresence: HealthWorkoutPresence?
        /// The Strava activity was found deleted on Strava when the rider tapped it (#632).
        var isStravaActivityDeleted = false

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

        /// The ride's Strava record as last written: the live one, else the one the stats carried.
        var stravaRecord: RideSyncRecord? {
            liveSyncRecords.record(for: summary.id, stored: stats?.stravaRecord)
        }

        /// S15's Synced To row (#632, UX §S15), nil while it isn't shown: for a ride sent anywhere,
        /// or one never sent while Strava is connected. Not before the stats: they carry the record.
        var syncedTo: SyncedTo? {
            guard let stats else { return nil }
            let inHealth = stats.isHealthWorkoutOwed || healthPresence == .ours || healthPresence == .otherSource
            let record = stravaRecord
            let offersStrava = record != nil || preferences.stravaAccount != nil
            guard inHealth || record != nil || offersStrava else { return nil }
            var capsules = [SyncedTo.Capsule(destination: .appleHealth, isSent: inHealth)]
            if offersStrava {
                // Filled from the moment it's queued: S15 shows no progress, S12.1 does.
                capsules.append(SyncedTo.Capsule(destination: .service(.strava), isSent: record.map { $0.status != .failed } ?? false))
            }
            let status: SyncedTo.Status? = if record?.status == .failed {
                .failed(record?.errorMessage ?? String(localized: "Couldn't upload to Strava"))
            } else if isStravaActivityDeleted && record == nil {
                .deletedOnStrava
            } else {
                nil
            }
            return SyncedTo(capsules: capsules, status: status)
        }

        mutating func updateWindExposure() {
            guard let track, let stats else { return }
            windExposure = RideWindExposure(headings: track.movingHeadings, samples: stats.weather)
        }
    }

    /// S15's Synced To row (#632): one capsule per destination, and what went wrong, if anything.
    struct SyncedTo: Equatable {
        struct Capsule: Equatable, Identifiable {
            let destination: SyncDestination
            /// Sent, or on its way: drawn filled.
            let isSent: Bool
            var id: SyncDestination { destination }
        }

        /// The status line under the capsules.
        enum Status: Equatable {
            /// Strava's own reason, with Retry.
            case failed(String)
            /// The activity was deleted on Strava, so the ride can go again.
            case deletedOnStrava
        }

        let capsules: [Capsule]
        let status: Status?
    }

    enum Action: Equatable {
        case task
        case trackLoaded(segments: [[RouteCoordinate]], track: RideDetailTrack)
        case trackLoadFailed
        /// The route arrives with the stats, so the Route row never turns into a link
        /// after it is on screen.
        case statsLoaded(RideStats, route: RouteSummary?)
        case vehiclePassesLoaded([VehiclePassEventDTO])
        case weatherAttributionLoaded(WeatherSourceAttribution)
        case healthProfileFetched(restingBPM: Int?, maxBPM: Int?, zoneCeilingsBPM: [Int]?)
        case healthPresenceLoaded(HealthWorkoutPresence)
        /// A Synced To capsule (#632): an unfilled one sends the ride there at once, a filled one
        /// opens it.
        case syncedToTapped(SyncDestination)
        /// Retry on the status line under a failed upload.
        case syncRetryTapped
        /// The tapped activity is gone from Strava, and its record was removed.
        case stravaActivityDeleted
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
            /// Send the ride to Strava (#632): `AppFeature` queues it.
            case uploadToStrava(rideId: UUID)
            /// Write the ride's workout to Apple Health (#632): `AppFeature` marks it owed and
            /// writes it.
            case addToAppleHealth(rideId: UUID)
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
    @Dependency(\.weatherClient) var weatherClient
    @Dependency(\.date) var date
    @Dependency(\.strava) var strava
    @Dependency(\.openURL) var openURL
    @Dependency(\.continuousClock) var clock

    private enum CancelID { case openStravaActivity }

    /// How long a filled Strava capsule waits on the deleted-on-Strava check before opening the
    /// activity as it stands: a weak connection would otherwise hold the tap for the session's
    /// 60 s timeout.
    static let stravaActivityCheckTimeout: Duration = .seconds(3)

    /// What a filled Apple Health capsule opens. iOS has no public link to one workout, so Health
    /// itself.
    static let healthAppURL = URL(string: "x-apple-health://")!

    /// The activity in the Strava app, which `openURL` reports false for when it isn't installed.
    static func stravaAppURL(activityID: String) -> URL? { URL(string: "strava://activities/\(activityID)") }
    static func stravaWebURL(activityID: String) -> URL? { URL(string: "https://www.strava.com/activities/\(activityID)") }

    /// True only when Strava answers 404 within `stravaActivityCheckTimeout`. A failure, a slow
    /// answer or a cancellation is false, so the activity opens as it stands.
    private static func isDeletedOnStrava(_ activityID: String, strava: StravaClient, clock: any Clock<Duration>) async -> Bool {
        await withTaskGroup(of: Bool?.self) { group in
            group.addTask { (try? await strava.activityExists(activityID)).map { !$0 } }
            group.addTask {
                try? await clock.sleep(for: stravaActivityCheckTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? false
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            // Independent reads, merged rather than queued. A failure in any leaves its part of
            // the screen as it was — `RouteDetailFeature`'s handling.
            case .task:
                let id = state.summary.id
                let startedAt = state.summary.startedAt
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
                    .run { [persistenceClient, weatherClient, healthKitClient] send in
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
                        // Both need the stats, and neither waits on the other.
                        await withDiscardingTaskGroup { group in
                            // Synced To's Apple Health capsule (#632). Needs the end, which the stats carry.
                            if let endedAt = stats.endedAt {
                                group.addTask {
                                    await send(.healthPresenceLoaded(await healthKitClient.workoutPresence(id, startedAt, endedAt)))
                                }
                            }
                            // Only the attribution, and only for a ride with weather to credit: the weather
                            // itself is the ride's, stored at the time, and a ride without any shows no
                            // Weather section. Offline, the footer still credits it, by name and with the
                            // fixed legal link. Failures are logged in WeatherClient.
                            if !stats.weather.isEmpty {
                                group.addTask {
                                    await send(.weatherAttributionLoaded((try? await weatherClient.attribution()) ?? .offline))
                                }
                            }
                        }
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
                state.updateWindExposure()
                return .none

            case .trackLoadFailed:
                state.trackReadFailed = true
                return .none

            case let .statsLoaded(stats, route):
                state.stats = stats
                state.route = route
                state.updateWindExposure()
                if let title = stats.title { state.summary.title = title }
                // A map sheet opened before the stats landed has no stops and no pass layer yet.
                if case var .mapSheet(sheet) = state.destination {
                    sheet.stops = RideStops.stops(pauses: stats.pauses, track: sheet.track)
                    sheet.hasRadar = stats.vehiclePassCount != nil
                    state.destination = .mapSheet(sheet)
                }
                return .none

            case .weatherAttributionLoaded(let attribution):
                state.weatherAttribution = attribution
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
                // An open map sheet colored by heart rate redraws against the zones as they now are.
                guard case .mapSheet = state.destination else { return .none }
                return .send(.destination(.presented(.mapSheet(.heartRateZonesChanged(state.heartRateZoneBounds)))))

            case .healthPresenceLoaded(let presence):
                state.healthPresence = presence
                return .none

            case .syncedToTapped(let destination):
                let id = state.summary.id
                guard let capsule = state.syncedTo?.capsules.first(where: { $0.destination == destination }) else { return .none }
                switch destination {
                case .appleHealth where capsule.isSent:
                    return .run { [openURL] _ in await openURL(Self.healthAppURL) }
                case .appleHealth:
                    // Drawn sent at once: the write is owed from here, as S10's close makes it.
                    state.stats?.isHealthWorkoutOwed = true
                    return .send(.delegate(.addToAppleHealth(rideId: id)))
                case .service(.strava) where capsule.isSent:
                    // Still on its way: nothing to open yet.
                    guard let activityID = state.stravaRecord?.remoteActivityId else { return .none }
                    let canTellDeleted = state.preferences.stravaAccount?.grantedScopes.contains(StravaConfig.privateActivitiesScope) ?? false
                    return .run { [strava, persistenceClient, openURL, clock] send in
                        // Only a 404 Strava can mean as deleted: without the private-activities scope a
                        // private activity answers 404 too, and resetting it would upload it twice.
                        // Offline, slow, or any other failure, it's opened as it stands.
                        if canTellDeleted, await Self.isDeletedOnStrava(activityID, strava: strava, clock: clock) {
                            do {
                                try await persistenceClient.deleteSyncRecord(id, .strava)
                                logger.notice("ride \(id, privacy: .public)'s Strava activity was deleted there; its record is reset")
                                await send(.stravaActivityDeleted)
                                return
                            } catch {
                                logger.error("Resetting ride \(id, privacy: .public)'s Strava record failed: \(error.localizedDescription, privacy: .public)")
                            }
                        }
                        // A cancelled check reads as "not deleted": popped, or replaced by a second
                        // tap, nothing opens behind the rider's back.
                        guard !Task.isCancelled else { return }
                        if let app = Self.stravaAppURL(activityID: activityID), await openURL(app) { return }
                        guard !Task.isCancelled else { return }
                        if let web = Self.stravaWebURL(activityID: activityID) { await openURL(web) }
                    }
                    .cancellable(id: CancelID.openStravaActivity, cancelInFlight: true)
                case .service(.strava):
                    state.isStravaActivityDeleted = false
                    return .send(.delegate(.uploadToStrava(rideId: id)))
                case .service:
                    return .none
                }

            case .syncRetryTapped:
                guard state.stravaRecord?.status == .failed else { return .none }
                return .send(.delegate(.uploadToStrava(rideId: state.summary.id)))

            case .stravaActivityDeleted:
                // The live record goes too, from the store's own write; this covers the copy the
                // stats carried.
                state.stats?.stravaRecord = nil
                state.isStravaActivityDeleted = true
                return .none

            case .mapTapped:
                // The header is drawn only for a ride with a drawable track.
                guard !state.trackSegments.isEmpty else { return .none }
                let map = state.track?.map ?? RideMapTrack(segments: [])
                state.destination = .mapSheet(RideMapSheetFeature.State(
                    segments: state.trackSegments,
                    track: map,
                    passes: state.vehiclePasses,
                    stops: RideStops.stops(pauses: state.stats?.pauses ?? [], track: map),
                    unitSystem: state.unitSystem,
                    hasRadar: state.stats?.vehiclePassCount != nil,
                    heartRateZones: state.heartRateZoneBounds,
                    cadenceZones: state.preferences.cadenceZones
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
            zones[zoneIndex(bpm, zoneBounds: zoneBounds)] += seconds
        }
        return zones
    }

    /// The zone `bpm` falls in, 0 for zone 1, against `zoneBounds` (zone 1 first): the highest zone
    /// whose floor it reaches, so a reading below zone 1 counts as zone 1. The rule the zone
    /// breakdowns and the map's heart rate coloring share.
    static func zoneIndex(_ bpm: Int, zoneBounds: [ClosedRange<Int>]) -> Int {
        zoneBounds.lastIndex { $0.lowerBound <= bpm } ?? 0
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
