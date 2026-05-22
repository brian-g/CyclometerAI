# Cyclometer — Data Model Specification
**Version:** 1.1
**Date:** 2026-05-21
**Updated:** 2026-05-22 — UserProfile split into RiderProfile, AppPreferences, PairedSensor, ConnectedService; all OQDMs resolved
**Status:** Draft — Ready for Engineering Review
**Author:** Brian (UX Design) + Claude (Specification)
**Companion Documents:** PRD.md section 10, TCA.md, BLE.md

---

## 1. Persistence Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                     Persistence Boundary                        │
│                                                                 │
│  SwiftData (@Model / @Query)          CoreData (raw)            │
│  ─────────────────────────────        ─────────────────────     │
│  Ride (summary)                       TrackPoint (1 Hz series)  │
│  RadarEvent (discrete events)         (NSBatchInsertRequest)    │
│  VehiclePassEvent (discrete events)                             │
│  RiderProfile                                                   │
│  AppPreferences                                                 │
│  PairedSensor                                                   │
│  ConnectedService                                               │
│                                                                 │
│  In-Memory (RideDataBuffer)                                     │
│  Active TrackPoint ring buffer                                  │
│  Flushed to CoreData on ride end / checkpoint                   │
└─────────────────────────────────────────────────────────────────┘
```

### Rationale

| Concern | Decision |
|---|---|
| Ride, RiderProfile, AppPreferences UI queries | SwiftData — ergonomic @Query macros in SwiftUI |
| TrackPoint — up to 3,600 rows/hour at 1 Hz | CoreData NSBatchInsertRequest — batch write avoids per-object overhead |
| Active-ride telemetry buffering | In-memory ring buffer; never written until checkpoint/end |
| RadarEvent, VehiclePassEvent — discrete | SwiftData — low frequency; UI-queryable |
| PairedSensor, ConnectedService — low-frequency writes | SwiftData — relationship owned by AppPreferences |
| iOS minimum | iOS 26 — SwiftData and Swift concurrency fully supported |

### Checkpoint Policy

- CoreData TrackPoint batch flush: every **30 seconds** of active recording
- SwiftData Ride summary update: every **30 seconds** (running totals)
- Crash recovery: last 30-second checkpoint is the recovery point (acceptable data loss)
- Ride end: final flush of all pending TrackPoints, then atomic GPX write

---

## 2. Entity Relationship Diagram

```
RiderProfile (1)          AppPreferences (1)
                               │
                    ┌──────────┴──────────┐
                    │                     │
                (∞) PairedSensor    (∞) ConnectedService

(∞) Ride
    │
    ├──────────────┬────────────────┐
    │              │                │
  (∞)            (∞)             (∞)
TrackPoint    RadarEvent   VehiclePassEvent
[CoreData]
                   │
                 (∞)
             RadarVehicle
             (embedded in RadarEvent)
```

**Key relationships:**
- AppPreferences owns [PairedSensor] and [ConnectedService] with cascade delete
- Ride and RiderProfile have no SwiftData relationship — single rider; rides queried by date range
- RadarVehicle is a value type embedded as JSON in RadarEvent, not a separate table
- Phase 2: Ride gains a route: Route? relationship when Route becomes a first-class entity

---

## 3. SwiftData Entities

### 3.1 Ride

```swift
import SwiftData
import Foundation

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
    // MVP: plain string matching GPX or tribos.studio route name.
    // Phase 2: replaced by relationship to Route @Model (OQDM1 deferred).
    var routeName: String?
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
    var recordingState: RideRecordingState     // .active | .paused | .ended

    // MARK: - Relationships
    var radarEvents: [RadarEvent]
    var vehiclePassEvents: [VehiclePassEvent]
    // TrackPoints stored in CoreData, linked by rideId

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
        self.radarEvents = []
        self.vehiclePassEvents = []
    }
}

enum RideRecordingState: String, Codable {
    case active, paused, ended
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
```

> **OQDM2 resolved — speedSourceAtEnd removed.** The active speed source is recorded per TrackPoint in speedSourceRaw. Derivable from the last TrackPoint; no separate persisted field needed.

> **OQDM1 — Route relationship deferred to Phase 2.** routeName is a plain String for MVP. Phase 2 schema v1.1 migrates it to a Route relationship.

---

### 3.2 RadarEvent

```swift
@Model
final class RadarEvent {
    var id: UUID
    var rideId: UUID
    var timestamp: Date
    var vehicleCount: Int
    var alertLevel: AlertLevel

    @Attribute(.externalStorage)
    var vehiclesData: Data

    var vehicles: [RadarVehicle] {
        get { (try? JSONDecoder().decode([RadarVehicle].self, from: vehiclesData)) ?? [] }
        set { vehiclesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(rideId: UUID, timestamp: Date, alertLevel: AlertLevel, vehicles: [RadarVehicle]) {
        self.id = UUID()
        self.rideId = rideId
        self.timestamp = timestamp
        self.vehicleCount = vehicles.count
        self.alertLevel = alertLevel
        self.vehiclesData = (try? JSONEncoder().encode(vehicles)) ?? Data()
    }
}

enum AlertLevel: Int, Codable, Comparable, Sendable {
    case clear = 0, advisory = 1, caution = 2, danger = 3

    static func < (lhs: AlertLevel, rhs: AlertLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayString: String {
        switch self {
        case .clear:    return "clear"
        case .advisory: return "advisory"
        case .caution:  return "caution"
        case .danger:   return "danger"
        }
    }
}
```

---

### 3.3 RadarVehicle (Value Type)

```swift
/// Embedded within RadarEvent as JSON-encoded Data. Not a separate SwiftData entity.
/// OQDM3 resolved: persisted via RadarEvent.vehiclesData.
struct RadarVehicle: Codable, Sendable {
    var vehicleIndex: Int
    var distanceMeters: Double
    var closingSpeedKph: Double                // Positive = approaching; negative = receding
    var alertLevel: AlertLevel
    var estimatedSize: VehicleSize             // .unknown in MVP (see PRD OQ11)
}

enum VehicleSize: String, Codable, Sendable {
    case unknown, small, medium, large
}
```

---

### 3.4 VehiclePassEvent

```swift
/// OQDM4 resolved: persisted as SwiftData @Model.
@Model
final class VehiclePassEvent {
    var id: UUID
    var rideId: UUID
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var alertLevelAtPass: AlertLevel
    var riderSpeedKph: Double
    var estimatedPassSpeedKph: Double?

    init(
        rideId: UUID, timestamp: Date,
        latitude: Double, longitude: Double,
        alertLevelAtPass: AlertLevel,
        riderSpeedKph: Double,
        estimatedPassSpeedKph: Double?
    ) {
        self.id = UUID()
        self.rideId = rideId
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.alertLevelAtPass = alertLevelAtPass
        self.riderSpeedKph = riderSpeedKph
        self.estimatedPassSpeedKph = estimatedPassSpeedKph
    }
}
```

---

### 3.5 RiderProfile

Stores the rider's physiological data for Karvonen HR zone calculation. Exactly one record exists, created during onboarding.

```swift
/// OQDM5 resolved: split from UserProfile. Physiology only.
@Model
final class RiderProfile {
    var id: UUID
    var restingHeartRateBPM: Int               // From HealthKit or manual entry
    var maxHeartRateBPM: Int                   // From HealthKit, age estimate, or manual
    var heartRateSourceIsAppleHealth: Bool
    var dateOfBirth: Date?                     // For age-based max HR estimate (220 - age)

    init() {
        self.id = UUID()
        self.restingHeartRateBPM = 60
        self.maxHeartRateBPM = 190
        self.heartRateSourceIsAppleHealth = false
    }
}
```

---

### 3.6 AppPreferences

All non-physiological preferences. Owns PairedSensor and ConnectedService collections. Exactly one record exists.

```swift
/// OQDM5 resolved: split from UserProfile. Preferences, sensors, services.
@Model
final class AppPreferences {
    var id: UUID

    // MARK: - Display & Units
    var preferredUnit: UnitSystem              // Defaults from iOS device locale
    // OQDM8 resolved: mapOrientation is real — PRD section 8.6 specifies heading-up
    // vs north-up as a user-toggleable setting. Persisted so the rider's choice survives
    // app restarts.
    var mapOrientation: MapOrientation

    // MARK: - Ride Behaviour
    // OQDM9 noted: wheelCircumferenceMM is a global default for MVP.
    // Phase 2: migrates to Bike entity when multi-bike support is added.
    var wheelCircumferenceMM: Int
    var isAutoPauseEnabled: Bool
    var isAutoDimEnabled: Bool
    var shouldSetDoNotDisturb: Bool

    // MARK: - Paired BLE Devices (OQDM6 resolved)
    // Extensible collection keyed by SensorRole. Replaces fixed UUID string fields.
    // A combo CSC sensor may appear twice (speed + cadence) with the same peripheralIdentifierString.
    @Relationship(deleteRule: .cascade) var pairedSensors: [PairedSensor]

    // MARK: - Connected Services (OQDM7 resolved)
    // Extensible collection. Replaces fixed stravaAccessToken / rideWithGPSAccessToken fields.
    @Relationship(deleteRule: .cascade) var connectedServices: [ConnectedService]

    func pairedSensor(for role: SensorRole) -> PairedSensor? {
        pairedSensors.first { $0.role == role }
    }

    func connectedService(of type: ExternalService) -> ConnectedService? {
        connectedServices.first { $0.serviceType == type }
    }

    init() {
        self.id = UUID()
        self.preferredUnit = .imperial
        self.mapOrientation = .headingUp
        self.wheelCircumferenceMM = 2096
        self.isAutoPauseEnabled = true
        self.isAutoDimEnabled = true
        self.shouldSetDoNotDisturb = false
        self.pairedSensors = []
        self.connectedServices = []
    }
}

enum UnitSystem: String, Codable { case metric, imperial }
enum MapOrientation: String, Codable { case headingUp, northUp }
```

---

### 3.7 PairedSensor

One BLE sensor in a specific role. A single physical device may appear twice — once for .speed, once for .cadence — when a combo CSC sensor is assigned both roles (same peripheralIdentifierString, different role values).

```swift
/// OQDM6 resolved: replaces fixed UUID string fields on AppPreferences.
@Model
final class PairedSensor {
    var id: UUID
    var peripheralIdentifierString: String     // CBPeripheral.identifier — stable per device per iOS install
    var role: SensorRole
    var displayName: String?                   // From BLE advertisement; user-editable in S11
    var modelIdentifier: String?               // Inferred from advertisement (e.g. "RTL515")

    var peripheralIdentifier: UUID? {
        UUID(uuidString: peripheralIdentifierString)
    }

    init(peripheralId: UUID, role: SensorRole, displayName: String? = nil) {
        self.id = UUID()
        self.peripheralIdentifierString = peripheralId.uuidString
        self.role = role
        self.displayName = displayName
    }
}

/// Defined in BLE.md section 7; mirrored here for persistence.
enum SensorRole: String, Codable, Sendable {
    case radar
    case heartRate
    case speed      // CSC profile — wheel revolution data
    case cadence    // CSC profile — crank revolution data
    case power      // Phase 3
}
```

---

### 3.8 ConnectedService

A connected third-party service. OAuth tokens live in the iOS Keychain; this entity holds only the lookup key and display metadata.

```swift
/// OQDM7 resolved: replaces fixed stravaAccessToken / rideWithGPSAccessToken fields.
@Model
final class ConnectedService {
    var id: UUID
    var serviceType: ExternalService
    var keychainIdentifier: String             // kSecAttrAccount key for Keychain lookup
    var accountDisplayName: String?            // e.g. "brian@strava.com" — shown in S12
    var isEnabled: Bool

    init(serviceType: ExternalService, keychainIdentifier: String) {
        self.id = UUID()
        self.serviceType = serviceType
        self.keychainIdentifier = keychainIdentifier
        self.isEnabled = true
    }
}

/// Extensible without schema migration — new cases store cleanly as new string values.
enum ExternalService: String, Codable, Sendable {
    case strava
    case rideWithGPS
    case tribosDotStudio
    case komoot
}
```

> **Security note:** Raw OAuth tokens are stored in the iOS Keychain under kSecClassGenericPassword. keychainIdentifier is the kSecAttrAccount key. Tokens never touch SwiftData.

---

## 4. CoreData Entity — TrackPoint

### 4.1 CoreData Schema

```swift
@objc(TrackPointMO)
final class TrackPointMO: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var rideId: UUID
    @NSManaged var timestamp: Date
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var altitudeMeters: Double
    @NSManaged var horizontalAccuracyMeters: Double
    @NSManaged var speedMPS: Double            // -1.0 = no source
    @NSManaged var speedSourceRaw: String      // SensorSource.rawValue
    @NSManaged var heartRateBPM: Int16         // 0 = no source
    @NSManaged var heartRateSourceRaw: String
    @NSManaged var cadenceRPM: Int16           // 0 = no source
    @NSManaged var powerWatts: Int16           // 0 = no source (Phase 3)
}
```

### 4.2 NSBatchInsertRequest Flow

```swift
func batchInsertTrackPoints(_ points: [TrackPointDTO]) async throws {
    let context = persistentContainer.newBackgroundContext()
    context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    var index = 0
    let request = NSBatchInsertRequest(
        entityName: "TrackPoint",
        managedObjectHandler: { managedObject in
            guard index < points.count else { return true }
            let point = points[index]
            let mo = managedObject as! TrackPointMO
            mo.id = point.id
            mo.rideId = point.rideId
            mo.timestamp = point.timestamp
            mo.latitude = point.latitude
            mo.longitude = point.longitude
            mo.altitudeMeters = point.altitudeMeters
            mo.horizontalAccuracyMeters = point.horizontalAccuracyMeters
            mo.speedMPS = point.speedMPS ?? -1.0
            mo.speedSourceRaw = point.speedSource.rawValue
            mo.heartRateBPM = Int16(point.heartRateBPM ?? 0)
            mo.heartRateSourceRaw = point.heartRateSource.rawValue
            mo.cadenceRPM = Int16(point.cadenceRPM ?? 0)
            mo.powerWatts = Int16(point.powerWatts ?? 0)
            index += 1
            return false
        }
    )
    request.resultType = .statusOnly
    try await context.perform {
        let result = try context.execute(request) as! NSBatchInsertResult
        guard result.result as? Bool == true else { throw PersistenceError.batchInsertFailed }
    }
}
```

### 4.3 SensorSource

```swift
enum SensorSource: String, Codable, Sendable {
    case bleHR           // BLE Heart Rate Profile
    case bleWheel        // BLE CSC — Speed role (wheel revolutions)
    case bleCadence      // BLE CSC — Cadence role (crank revolutions)
    case blePower        // Phase 3
    case appleWatch      // HealthKit HR stream
    case gps             // CoreLocation speed/distance
    case none            // Field omitted from GPX
}
```

---

## 5. In-Memory Buffer — RideDataBuffer

```swift
actor RideDataBuffer {
    private let maxCapacity = 1_800           // 30 minutes at 1 Hz
    private var points: [TrackPointDTO] = []
    private var flushedCount = 0

    func append(_ point: TrackPointDTO) {
        points.append(point)
        if points.count > maxCapacity { points.removeFirst() }
    }

    func drainForFlush() -> [TrackPointDTO] {
        let toFlush = points
        points = []
        flushedCount += toFlush.count
        return toFlush
    }

    var totalPointCount: Int { flushedCount + points.count }
}

struct TrackPointDTO: Sendable {
    var id: UUID = UUID()
    var rideId: UUID
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var altitudeMeters: Double
    var horizontalAccuracyMeters: Double
    var speedMPS: Double?
    var speedSource: SensorSource
    var heartRateBPM: Int?
    var heartRateSource: SensorSource
    var cadenceRPM: Int?
    var powerWatts: Int?                       // Phase 3
}
```

---

## 6. GPX Export Data Surface

The GPXExporter reads from:
- Ride (SwiftData) — metadata, title, timestamps, weather
- [TrackPointMO] (CoreData query by rideId) — track segments
- [VehiclePassEvent] (SwiftData via Ride) — waypoints
- AppPreferences (SwiftData) — unit preference for metadata display only

Ride end sequence:
```
1. Flush RideDataBuffer to CoreData (NSBatchInsertRequest)
2. Update Ride.endedAt, Ride.recordingState = .ended (SwiftData)
3. GPXExporter.generate(rideId:) — writes file atomically to Documents/Rides/
4. Update Ride.gpxFileURL (SwiftData)
5. Post ride-ended notification to TCA AppFeature
```

---

## 7. Query Patterns

### Ride History List (S14)
```swift
@Query(sort: \Ride.startedAt, order: .reverse)
var rides: [Ride]
```

### Previous Rides for Route (S20, Phase 2)
```swift
@Query(
    filter: #Predicate<Ride> { $0.routeName == routeName },
    sort: \Ride.startedAt, order: .reverse
)
var previousRides: [Ride]
// Phase 2: replaced by filter on Ride.route?.id == routeId
```

### Paired Sensor for a Role
```swift
// Not @Query — read directly from AppPreferences relationship
let speedSensor = appPreferences.pairedSensor(for: .speed)
let cadenceSensor = appPreferences.pairedSensor(for: .cadence)
// These may return the same peripheral UUID for a combo sensor assigned both roles
```

### TrackPoints for GPX / Ride Detail
```swift
let request = NSFetchRequest<TrackPointMO>(entityName: "TrackPoint")
request.predicate = NSPredicate(format: "rideId == %@", rideId as CVarArg)
request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
request.fetchBatchSize = 500
```

### Phase 2 Route Queries (noted for future)
```swift
// Routes starting within 30 miles of a coordinate:
// NSPredicate on Route.startLatitude / .startLongitude; Haversine distance computed app-side
//
// Routes where return is with prevailing winds:
// Route.bearing vs RideWeather.windDirectionDegrees — computed at query time
```

---

## 8. Karvonen Zone Calculation

Zone is computed at query time from stored BPM. Computing at query time means zone boundaries automatically update if the rider adjusts their HR profile — no historical data becomes stale.

```swift
extension RiderProfile {
    var hrReserve: Int { maxHeartRateBPM - restingHeartRateBPM }

    func hrZone(forBPM bpm: Int) -> Int {
        guard hrReserve > 0 else { return 0 }
        let pct = Double(bpm - restingHeartRateBPM) / Double(hrReserve)
        switch pct {
        case ..<0.60: return 1   // Recovery
        case ..<0.70: return 2   // Endurance
        case ..<0.80: return 3   // Tempo
        case ..<0.90: return 4   // Threshold
        default:      return 5   // VO2 Max
        }
    }
}
```

---

## 9. Migration Strategy

| Schema Version | Changes |
|---|---|
| 1.0 (MVP) | All entities as specified above |
| 1.1 (Phase 2 — Routes) | Add Route @Model; add Ride.route: Route?; migrate Ride.routeName |
| 1.2 (Phase 2 — Bikes) | Add Bike @Model; migrate AppPreferences.wheelCircumferenceMM to Bike |
| 2.0 (Phase 3 — Power) | Add TrackPointMO.powerWatts column; add Ride.powerAverageWatts |

Key rules:
- Never rename SwiftData properties without a SchemaMigrationPlan stage
- CoreData TrackPoint changes require a NSMigrationManager mapping model
- ExternalService and SensorRole enum cases can be added without migration

```swift
enum CyclometerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] = [CyclometerSchemaV1.self]
    static var stages: [MigrationStage] = []
}
```

---

## 10. Test Matrix

| Component | Test Type | Coverage Target |
|---|---|---|
| Karvonen zone calculation | Unit — RiderProfileTests | All 5 zone boundaries; HR below resting; HR above max |
| VehiclePassEvent detection | Unit — VehiclePassDetectionTests | Overtake vs turn-off; 2s minimum tracking; closing speed sign |
| NSBatchInsertRequest flush | Integration — PersistenceTests | 3,600 rows (1 hour); count and rideId linkage verified |
| GPXExporter output | Unit — GPXExporterTests | Schema validation; namespace declarations; absent vs zero fields |
| RideDataBuffer concurrency | Unit — RideDataBufferTests | Concurrent appends; drain ordering; capacity ring behaviour |
| Ride summary aggregates | Unit — RideAggregateTests | Running avg/max; zone duration accumulation; paused interval exclusion |
| SensorSource priority switching | Unit via TCA TestStore | All transitions in priority chain; source badge updates |
| Wheel auto-calibration math | Unit — WheelCalibrationTests | 5% trigger; 10% cap; GPS accuracy gating |
| PairedSensor role lookup | Unit — AppPreferencesTests | Correct sensor per role; nil when role unpaired; combo sensor at two roles |
| ConnectedService Keychain round-trip | Integration — ConnectedServiceTests | Token stored in Keychain; keychainIdentifier retrieves correct token |
| RideWeather encoding/decoding | Unit — RideWeatherTests | Round-trips through JSON; nil fields handled; partial data graceful |
| RideSyncRecord encoding/decoding | Unit — RideSyncTests | Round-trips through JSON; correct status transitions; remoteActivityId stored on success |

---

## 11. Open Questions Resolution Log

| # | Question | Status |
|---|---|---|
| OQDM1 | Route should be a first-class entity referenced by Ride | Deferred to Phase 2. routeName is a String for MVP; migrated to Ride.route: Route? in schema v1.1 |
| OQDM2 | Why store speedSourceAtEnd? | Resolved — removed. Active source is recorded per TrackPoint in speedSourceRaw; derivable from last TrackPoint |
| OQDM3 | Is RadarVehicle persisted? | Resolved — yes. Embedded as JSON-encoded Data in RadarEvent via @Attribute(.externalStorage) |
| OQDM4 | VehiclePassEvent should be persisted | Resolved — it is. Full @Model with initializer |
| OQDM5 | Why is the entity called UserProfile? | Resolved — split into RiderProfile (physiology) and AppPreferences (preferences, sensors, services) |
| OQDM6 | Sensor storage limited to fixed fields | Resolved. PairedSensor @Model with role: SensorRole. Any number of sensors of any role |
| OQDM7 | Connected services list is fixed | Resolved. ConnectedService @Model with serviceType: ExternalService. New services add an enum case |
| OQDM8 | What is mapOrientation for? | Resolved — it is real. PRD section 8.6 specifies heading-up vs north-up as a user-toggleable setting; stored in AppPreferences to persist across sessions |
| OQDM9 | Store bike information | Deferred to Phase 2. Bike @Model in schema v1.2; wheelCircumferenceMM migrates there |
| OQDM10 | Capture weather conditions for a ride | Resolved. RideWeather Codable value type stored as JSON on Ride. Fields: temperature, wind speed, wind direction, conditions, humidity, capture timestamp |

---

*Cyclometer Data Model Spec v1.2 · 2026-05-22*
