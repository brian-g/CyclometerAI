import ComposableArchitecture
import Foundation
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "persistence")

/// S15 — Ride Detail: one finished ride's track, elevation and heart rate, its stats, and the
/// vehicles that passed it (#251).
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

    /// Points in each chart. Enough for a smooth line at any phone width, without handing Swift
    /// Charts the ~4 200 points a 70-minute ride records — S20 uses the same count.
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

        var summary: RideListSummary

        /// One polyline per stretch of riding (#263). Empty until the track loads, and empty for
        /// good for a ride with no drawable track.
        var trackSegments: [[RouteCoordinate]] = []

        /// Nil until the track loads, and nil for a ride with no drawable track.
        var elevationProfileMeters: [Double]?

        /// Empty for a ride with no heart-rate readings — never zeros standing in for them.
        var heartRateSamples: [Int] = []

        /// Nil until it loads, and nil for good if the read fails.
        var stats: RideStats?

        /// Oldest first.
        var vehiclePasses: [VehiclePassEventDTO] = []

        init(summary: RideListSummary) {
            self.summary = summary
        }

        var unitSystem: UnitSystem { preferences.preferredUnit }

        /// Each zone's bpm range as S12's table shows it, zone 1 first — the chart's bands.
        /// Resolved now rather than stored with the ride, like every zone in the app.
        var heartRateZoneBounds: [ClosedRange<Int>] {
            HeartRateZone.allCases.map {
                riderProfile.bounds(for: $0, healthResting: healthRestingBPM, healthMax: healthMaxBPM)
            }
        }
    }

    enum Action: Equatable {
        case task
        case trackLoaded(segments: [[RouteCoordinate]], elevationProfile: [Double]?, heartRate: [Int])
        case statsLoaded(RideStats)
        case vehiclePassesLoaded([VehiclePassEventDTO])
        case healthProfileFetched(restingBPM: Int?, maxBPM: Int?)
    }

    @Dependency(\.persistenceClient) var persistenceClient
    @Dependency(\.healthKitClient) var healthKitClient
    @Dependency(\.date) var date

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            // Independent reads, merged rather than queued. A failure in any leaves its part of
            // the screen as it was — `RouteDetailFeature`'s handling.
            case .task:
                let id = state.summary.id
                return .merge(
                    .run { [persistenceClient] send in
                        do {
                            let points = try await persistenceClient.fetchTrackPoints(id)
                            // Derived here, once per load, rather than by the view on every body pass.
                            await send(.trackLoaded(
                                segments: RideMapThumbnail.drawableSegments(points),
                                elevationProfile: RideDetailSeries.elevationProfile(points, sampleCount: Self.chartSampleCount),
                                heartRate: RideDetailSeries.heartRate(points, sampleCount: Self.chartSampleCount)
                            ))
                        } catch {
                            logger.error("fetchTrackPoints failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        }
                    },
                    .run { [persistenceClient] send in
                        do {
                            await send(.statsLoaded(try await persistenceClient.fetchRideStats(id)))
                        } catch {
                            logger.error("fetchRideStats failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
                        let maxBPM = RiderProfile.estimatedMaxBPM(fromDateOfBirth: await dob, on: date.now)
                        await send(.healthProfileFetched(restingBPM: await restingBPM, maxBPM: maxBPM))
                    }
                )

            case let .trackLoaded(segments, elevationProfile, heartRate):
                state.trackSegments = segments
                state.elevationProfileMeters = elevationProfile
                state.heartRateSamples = heartRate
                return .none

            case .statsLoaded(let stats):
                state.stats = stats
                return .none

            case .vehiclePassesLoaded(let passes):
                state.vehiclePasses = passes
                return .none

            case let .healthProfileFetched(restingBPM, maxBPM):
                state.healthRestingBPM = restingBPM
                state.healthMaxBPM = maxBPM
                return .none
            }
        }
    }
}

/// S15's chart series, derived from the recorded track. Plain arithmetic, so it is tested
/// directly rather than through the charts.
enum RideDetailSeries {
    /// Elevation at `sampleCount` evenly spaced distances along the ride, the same
    /// distance-spaced profile S20 charts (`RouteGeometry.elevationProfile`). Nil for a ride
    /// with no drawable track, so the chart and the map agree about whether there is one.
    static func elevationProfile(_ points: [TrackPointDTO], sampleCount: Int) -> [Double]? {
        guard !RideMapThumbnail.drawableSegments(points).isEmpty else { return nil }
        let coordinates = points.map {
            RouteCoordinate(latitude: $0.latitude, longitude: $0.longitude, elevationMeters: $0.altitudeMeters)
        }
        return RouteGeometry.elevationProfile(coordinates, sampleCount: sampleCount)
    }

    /// Heart rate over the ride's recorded time, averaged into at most `sampleCount` buckets.
    /// Only seconds with a reading count. A point is recorded once a second while riding and
    /// never while paused, so position in the series reads as moving time. Empty when no
    /// second had a reading.
    static func heartRate(_ points: [TrackPointDTO], sampleCount: Int) -> [Int] {
        let readings = points.compactMap(\.heartRateBPM)
        guard readings.count > sampleCount, sampleCount > 0 else { return readings }
        return (0..<sampleCount).map { bucket in
            let bucketReadings = readings[(bucket * readings.count / sampleCount)..<((bucket + 1) * readings.count / sampleCount)]
            return Int((Double(bucketReadings.reduce(0, +)) / Double(bucketReadings.count)).rounded())
        }
    }
}
