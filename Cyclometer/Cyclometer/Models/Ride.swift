import Foundation
import SwiftData

/// Top-level ride summary, persisted in SwiftData (DataModel.md §3.1).
/// High-frequency samples (speed, HR, GPS) are stored separately in CoreData,
/// linked to a Ride only by `rideId` — see `TrackPointDTO`.
///
/// Any non-optional attribute added here needs a *declaration-site* default
/// (`= 0`, not just an `init` assignment). SwiftData takes the attribute's
/// store-level default from the declaration, and lightweight migration can't
/// backfill a mandatory attribute that has none — it fails the entire store
/// load, crashing at launch for anyone with an older store (#186).
/// `RideSchemaMigrationTests` is the guard against a regression.
@Model
final class Ride {
    // MARK: - Identity
    var id: UUID
    var title: String                          // User-editable; defaults to route name or "Morning Ride"
    var notes: String                          // User-editable; no default

    // MARK: - Timing
    var startedAt: Date
    var endedAt: Date?                         // nil while ride is active

    // MARK: - Aggregate Metrics
    var distanceMeters: Double
    var durationSeconds: TimeInterval          // Excludes paused intervals
    var averageSpeedMPS: Double
    var maxSpeedMPS: Double
    var elevationGainMeters: Double
    var elevationDropMeters: Double

    // MARK: - Heart Rate
    var averageHeartRateBPM: Int?
    var maxHeartRateBPM: Int?
    var hrZoneDurations: [Int: TimeInterval]   // zone (1-5) to seconds in zone

    // MARK: - Cadence
    var averageCadenceRPM: Int?
    var maxCadenceRPM: Int?

    // MARK: - Radar & Safety
    var radarEventCount: Int?                  // nil if no radar paired
    var vehiclePassCount: Int?

    // MARK: - Route
    // FK by id, matching how TrackPoint and VehiclePassEvent link back here (#172) —
    // no SwiftData `@Relationship`. Written at ride start (#191); nil for a free ride.
    var routeId: UUID?
    // The denormalized historical copy, written alongside routeId. It stays a plain
    // String precisely so deleting a route cannot erase what a past ride *was*: the id
    // is then left dangling and this is all S15 has to show. Optional, so #186's
    // mandatory-attribute backfill trap doesn't apply to either field.
    var routeName: String?
    // How far along its route the ride had got at the last checkpoint (#197), so a ride resumed
    // after a kill looks for the rider from there rather than from the start — which, on an
    // out-and-back, is the difference between the way out and the way back. Optional for the
    // same reason as the two above.
    var routeProgressMeters: Double?
    var gpxFileURL: URL?

    // MARK: - Weather (OQDM10)
    // Fetched at ride start; stored for post-ride display.
    @Attribute(.externalStorage)
    var weatherData: Data?

    var weather: RideWeather? {
        get { weatherData.flatMap { try? JSONDecoder().decode(RideWeather.self, from: $0) } }
        set { weatherData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    // MARK: - Sync Status
    // Per-service sync tracking. Written by RideSyncSheetFeature after upload.
    @Attribute(.externalStorage)
    var syncRecordsData: Data?

    var syncRecords: [RideSyncRecord] {
        get { syncRecordsData.flatMap { try? JSONDecoder().decode([RideSyncRecord].self, from: $0) } ?? [] }
        set { syncRecordsData = try? JSONEncoder().encode(newValue) }
    }

    func syncRecord(for service: ExternalService) -> RideSyncRecord? {
        syncRecords.first { $0.service == service }
    }

    // MARK: - State
    var recordingState: RecordingState
    /// Whether the current `.paused` state was auto-triggered (stoplight, #102)
    /// rather than a manual Pause tap. Persisted (#175) so a resumed ride can
    /// tell the two apart — auto-resume-on-motion only applies to the former.
    var isAutoPaused: Bool = false
    /// Consecutive zero-speed seconds while active, mirroring
    /// `ActiveRideFeature.State.zeroSpeedSeconds` (#175) — persisted so a kill
    /// near the auto-pause/auto-end threshold doesn't hand a resumed ride a
    /// fresh grace window. Bounded to the same one-checkpoint-window staleness
    /// as every other resumed aggregate.
    var zeroSpeedSeconds: Int = 0
    /// Sample counts backing the running averages above, persisted (#175) so a
    /// resumed ride can seed its true prior weight instead of fabricating one —
    /// `averageSpeedMPS`/`averageHeartRateBPM`/`averageCadenceRPM` alone can't
    /// be un-averaged back into a (sum, count) pair without this.
    var speedSampleCount: Int = 0
    var hrSampleCount: Int = 0
    var cadenceSampleCount: Int = 0

    // MARK: - Relationships
    // TrackPoints and VehiclePassEvents are linked by rideId only (TrackPoint's
    // CoreData FK pattern, #172) — no SwiftData `@Relationship` array here.
    // radarEvents deferred until RadarEvent exists (a future issue).

    init(id: UUID = UUID(), startedAt: Date = .now) {
        self.id = id
        self.title = ""
        self.notes = ""
        self.startedAt = startedAt
        self.distanceMeters = 0
        self.durationSeconds = 0
        self.averageSpeedMPS = 0
        self.maxSpeedMPS = 0
        self.elevationGainMeters = 0
        self.elevationDropMeters = 0
        self.recordingState = .active
        self.hrZoneDurations = [:]
        self.isAutoPaused = false
        self.zeroSpeedSeconds = 0
        self.speedSampleCount = 0
        self.hrSampleCount = 0
        self.cadenceSampleCount = 0
    }

    /// Nested rather than top-level to avoid colliding with the TCA-side
    /// `RideRecordingState` (ActiveRideFeature.swift), which has a distinct
    /// `.idle` case with no on-disk meaning — a Ride record doesn't exist until
    /// a ride actually starts.
    enum RecordingState: String, Codable {
        case active, paused, ended
    }
}

extension Ride {
    /// Snapshot of this ride's current aggregates, in the same shape a
    /// checkpoint write applies (`RidePersistenceActor.apply`) — the read-side
    /// counterpart used by `fetchResumableRide` (#175), kept as a single named
    /// accessor rather than a second hand-duplicated field list (#172 review
    /// precedent: this same duplication, one level down, was already
    /// consolidated once in `RidePersistenceActor.savingChanges`).
    var summarySnapshot: RideSummaryUpdate {
        RideSummaryUpdate(
            rideId: id,
            recordingState: recordingState,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            averageSpeedMPS: averageSpeedMPS,
            maxSpeedMPS: maxSpeedMPS,
            averageHeartRateBPM: averageHeartRateBPM,
            maxHeartRateBPM: maxHeartRateBPM,
            averageCadenceRPM: averageCadenceRPM,
            maxCadenceRPM: maxCadenceRPM,
            vehiclePassCount: vehiclePassCount,
            isAutoPaused: isAutoPaused,
            zeroSpeedSeconds: zeroSpeedSeconds,
            speedSampleCount: speedSampleCount,
            hrSampleCount: hrSampleCount,
            cadenceSampleCount: cadenceSampleCount,
            // `createRide` writes the id and name together, so this is both or neither.
            route: routeId.flatMap { id in routeName.map { RouteReference(id: id, name: $0) } },
            routeProgressMeters: routeProgressMeters
        )
    }
}

/// Weather conditions at ride start. Captured once; stored as JSON on Ride.
struct RideWeather: Codable, Sendable {
    var temperatureCelsius: Double?
    var windSpeedKph: Double?
    var windDirectionDegrees: Double?          // Meteorological: 0=N, 90=E, 180=S, 270=W
    var conditions: WeatherCondition?
    var humidityPercent: Double?
    var capturedAt: Date?
}

enum WeatherCondition: String, Codable, Sendable {
    case clear, partlyCloudy, cloudy, foggy, drizzle, rain, heavyRain, snow, thunderstorm
}

/// Per-service sync record stored on Ride. Written by RideSyncSheetFeature after upload.
/// Phase 2 — structure defined in MVP for architecture continuity.
struct RideSyncRecord: Codable, Sendable {
    var service: ExternalService
    var status: SyncStatus
    var syncedAt: Date?                        // nil until successfully synced
    var remoteActivityId: String?              // e.g. Strava activity ID; used for deep linking
    var errorMessage: String?                  // Last failure reason; nil when synced
}

enum SyncStatus: String, Codable, Sendable {
    case pending    // Not yet attempted
    case uploading  // In progress
    case synced     // Successfully uploaded
    case failed     // Upload failed; see RideSyncRecord.errorMessage
}

/// DataModel.md §3.8's ConnectedService is deferred to M13/Phase 2, but
/// RideSyncRecord.service needs this enum now for architecture continuity.
enum ExternalService: String, Codable, Sendable {
    case strava
    case rideWithGPS
    case tribosDotStudio
    case komoot
}
