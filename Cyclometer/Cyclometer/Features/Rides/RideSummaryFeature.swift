import ComposableArchitecture
import Foundation
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "persistence")

/// S10 — Ride Summary: the ride that just ended, presented by `AppFeature` on Finish (#249).
///
/// Seeded with only the ride's id. It opens on the same action that starts
/// `ActiveRideFeature`'s flush → GPX → `finalizeRide` chain, so `.task` waits for that to land
/// before reading anything — before it, the row holds the last checkpoint's aggregates, up to
/// 30 s stale, and the track is missing its final buffer.
///
/// An unnamed free ride's default name gains the place it started in once a reverse geocode
/// answers (#283), unless the rider has turned place names off in S12. The screen never waits
/// on it: the offline name shows first and is swapped only if the rider hasn't touched the field.
/// A failed lookup, or one still out when the sheet closes, leaves the offline name the ride was
/// given at ride end.
///
/// The rename is saved by `AppFeature` on dismissal, not here: a child's effects are cancelled
/// as it is dismissed, and a swipe-down is a dismissal like the Finish Ride button.
@Reducer
struct RideSummaryFeature {

    @ObservableState
    struct State: Equatable {
        /// Units follow the S12 picker.
        @Shared(.appPreferences) var preferences

        /// The zone breakdown follows S12's zones, overrides included — resolved now rather
        /// than stored with the ride, as S15 does.
        @SharedReader(.riderProfile) var riderProfile

        /// `RideDetailFeature`'s Health terms. Nil until fetched, and nil when Health has nothing.
        var healthRestingBPM: Int?
        var healthMaxBPM: Int?

        let rideId: UUID

        enum Load: Equatable {
            /// Waiting for the ride's finalize, then its reads.
            case waiting
            case loaded
            /// The finalize never landed. `AppFeature` closes the ride out at next launch.
            case unavailable
        }
        var load: Load = .waiting

        /// What the name field shows: the stored title, or `defaultTitle` for a ride without one.
        var title = ""
        /// The title as stored when the screen loaded: the default name, given at ride end (#286), or "" if that write failed.
        var persistedTitle = ""
        /// The name the ride gets when the rider doesn't give one. Nil until loaded.
        var defaultTitle: String?
        /// Whether the rider has focused or typed in the name field. Once they have, a late place
        /// name (#283) never replaces what the field shows, even when it still reads as the default.
        var isTitleTouched = false

        var summary: RideListSummary?
        /// Nil until loaded, and nil for good if the read fails.
        var stats: RideStats?
        /// One polyline per stretch of riding (#263). Empty for a ride with no drawable track.
        var trackSegments: [[RouteCoordinate]] = []
        var elevationProfileMeters: [Double]?
        /// Empty for a ride with no heart-rate readings.
        var heartRateSecondsByBPM: [Int: Int] = [:]

        init(rideId: UUID) {
            self.rideId = rideId
        }

        var unitSystem: UnitSystem { preferences.preferredUnit }

        /// Seconds in each zone, zone 1 first. Empty for a ride with no heart rate, so the view
        /// shows its empty state rather than a chart of nothing.
        var heartRateZoneSeconds: [Int] {
            guard !heartRateSecondsByBPM.isEmpty else { return [] }
            let bounds = HeartRateZone.allCases.map {
                riderProfile.bounds(for: $0, healthResting: healthRestingBPM, healthMax: healthMaxBPM)
            }
            return RideDetailSeries.zoneSeconds(heartRateSecondsByBPM, zoneBounds: bounds)
        }

        /// What dismissing should store, or nil when nothing changed. A field cleared to nothing
        /// means the default, never an empty title.
        var titleToSave: String? {
            let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = typed.isEmpty ? (defaultTitle ?? "") : typed
            return name.isEmpty || name == persistedTitle ? nil : name
        }
    }

    /// Everything the screen reads once the ride is finalized, delivered together. The default
    /// title is worked out in the effect, off the main actor: judging a long ride's shape
    /// compares thousands of points.
    struct Loaded: Equatable {
        var summary: RideListSummary
        var stats: RideStats?
        var trackSegments: [[RouteCoordinate]]
        var elevationProfileMeters: [Double]?
        var heartRateSecondsByBPM: [Int: Int]
        var defaultTitle: String
    }

    enum Action: Equatable {
        case task
        case loaded(Loaded)
        case finalizeTimedOut
        case healthProfileFetched(restingBPM: Int?, maxBPM: Int?)
        /// The default name with the start's place name in it, once the geocoder has answered.
        case placedTitleResolved(String)
        case titleChanged(String)
        case titleFocused
        case finishTapped
    }

    @Dependency(\.persistenceClient) var persistenceClient
    @Dependency(\.healthKitClient) var healthKitClient
    @Dependency(\.geocodingClient) var geocodingClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date) var date
    @Dependency(\.calendar) var calendar
    @Dependency(\.dismiss) var dismiss

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .task:
                let id = state.rideId
                let isPlaceNameLookupEnabled = state.preferences.isPlaceNameLookupEnabled
                return .merge(
                    .run { [persistenceClient, geocodingClient, clock, calendar] send in
                        guard let summary = try await RidesFeature.awaitFinalized(
                            id, persistenceClient: persistenceClient, clock: clock
                        ) else {
                            await send(.finalizeTimedOut)
                            return
                        }
                        async let stats = Self.fetchStats(id, persistenceClient)
                        async let points = Self.fetchTrackPoints(id, persistenceClient)
                        let track = await points
                        let rideStats = await stats
                        let segments = RideMapThumbnail.drawableSegments(track)
                        let routeName = rideStats?.routeName
                        let defaultTitle = RideTitle.defaultTitle(
                            routeName: routeName,
                            startedAt: summary.startedAt,
                            segments: segments,
                            calendar: calendar
                        )
                        await send(.loaded(Loaded(
                            summary: summary,
                            stats: rideStats,
                            trackSegments: segments,
                            elevationProfileMeters: RideDetailSeries.elevationProfile(
                                track, sampleCount: RideDetailFeature.chartSampleCount
                            ),
                            heartRateSecondsByBPM: RideDetailSeries.secondsByBPM(track),
                            defaultTitle: defaultTitle
                        )))
                        // Only after the screen has its numbers, so it never waits on the network.
                        guard isPlaceNameLookupEnabled,
                              Self.isKnownFreeRide(stats: rideStats, storedTitle: summary.title, defaultTitle: defaultTitle),
                              let start = segments.first?.first,
                              let place = try? await geocodingClient.locality(start)
                        else { return }
                        await send(.placedTitleResolved(RideTitle.placed(defaultTitle, in: place)))
                    },
                    // `RideDetailFeature`'s read, so the zones match S12's table.
                    .run { [healthKitClient, date] send in
                        async let restingBPM = try? healthKitClient.fetchRestingHeartRate()
                        async let dob = try? healthKitClient.fetchDateOfBirth()
                        let maxBPM = RiderProfile.estimatedMaxBPM(fromDateOfBirth: await dob, on: date.now)
                        await send(.healthProfileFetched(restingBPM: await restingBPM, maxBPM: maxBPM))
                    }
                )

            case .loaded(let loaded):
                state.load = .loaded
                state.summary = loaded.summary
                state.stats = loaded.stats
                state.trackSegments = loaded.trackSegments
                state.elevationProfileMeters = loaded.elevationProfileMeters
                state.heartRateSecondsByBPM = loaded.heartRateSecondsByBPM
                let defaultTitle = loaded.defaultTitle
                state.defaultTitle = defaultTitle
                state.persistedTitle = loaded.summary.title
                // Typing before the load lands is kept: the rider's name beats the default.
                if state.title.isEmpty {
                    state.title = loaded.summary.title.isEmpty ? defaultTitle : loaded.summary.title
                }
                return .none

            case .finalizeTimedOut:
                state.load = .unavailable
                return .none

            case let .healthProfileFetched(restingBPM, maxBPM):
                state.healthRestingBPM = restingBPM
                state.healthMaxBPM = maxBPM
                return .none

            case .placedTitleResolved(let placedTitle):
                // The field is the rider's once they have touched it. The default moves either
                // way, so a field cleared later saves this one.
                if !state.isTitleTouched {
                    state.title = placedTitle
                }
                state.defaultTitle = placedTitle
                return .none

            case .titleChanged(let title):
                state.title = title
                state.isTitleTouched = true
                return .none

            case .titleFocused:
                state.isTitleTouched = true
                return .none

            case .finishTapped:
                return .run { [dismiss] _ in await dismiss() }
            }
        }
    }

    /// Whether the start may go to the geocoder (PRD §12): only for a ride known not to be on a
    /// route, and still named by default. Stats that failed to load can't rule out a route, so they
    /// rule the lookup out — the route's name is in `storedTitle` then, but a failed ride-end rename
    /// would leave it empty too.
    static func isKnownFreeRide(stats: RideStats?, storedTitle: String, defaultTitle: String) -> Bool {
        guard let stats, stats.routeName?.isEmpty ?? true else { return false }
        return storedTitle.isEmpty || storedTitle == defaultTitle
    }

    /// Nil on failure, leaving the stats rows as dashes — logged, as S15 does.
    private static func fetchStats(_ id: UUID, _ persistenceClient: PersistenceClient) async -> RideStats? {
        do {
            return try await persistenceClient.fetchRideStats(id)
        } catch {
            logger.error("fetchRideStats failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Empty on failure, which the screen shows as a ride with no track.
    private static func fetchTrackPoints(_ id: UUID, _ persistenceClient: PersistenceClient) async -> [TrackPointDTO] {
        do {
            return try await persistenceClient.fetchTrackPoints(id)
        } catch {
            logger.error("fetchTrackPoints failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
