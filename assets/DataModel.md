# Cyclometer — Data Model Specification
**Version:** 1.4
**Date:** 2026-05-21
**Updated:** 2026-08-17 (#96) — §3.5 revised: RiderProfile leaves SwiftData for a `@Shared(.fileStorage)` JSON document, and stores HR *overrides* rather than values, since resting HR and date of birth are HealthKit's to own and max HR has no HealthKit type at all. `heartRateSourceIsAppleHealth` becomes derived; `dateOfBirth` is not stored. §8 gains the worked example it was already cited for, plus the zone → bpm inverse and the `minimumHRReserve` floor it requires. SwiftData now lands with M7's Ride
**Previously:** 2026-08-08 (PR #83 review) — §3.9 revised: no Wheelset entity; wheel circumference moves onto the speed-role PairedSensor; Bike gains stravaGearID; Ride gains a bikeName snapshot. §3.6 records why JSON over plist. Research basis: PRD §8.9.1
**Previously:** 2026-08-03 (#69) — AppPreferences moved out of SwiftData to a `@Shared(.fileStorage)` JSON document; PairedSensor / ConnectedService ownership reopened for #67; §3.9 added
**Previously:** 2026-05-22 — UserProfile split into RiderProfile, AppPreferences, PairedSensor, ConnectedService; all OQDMs resolved
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
│  ConnectedService (still open — §3.8)                           │
│                                                                 │
│  JSON document (@Shared / .fileStorage)                         │
│  AppPreferences (singleton)                                     │
│    └─ PairedSensor[]  (nested value, #67)                       │
│  RiderProfile (singleton, HR overrides — #96, §3.5)             │
│                                                                 │
│  In-Memory (RideDataBuffer)                                     │
│  Active TrackPoint ring buffer                                  │
│  Flushed to CoreData on ride end / checkpoint                   │
└─────────────────────────────────────────────────────────────────┘
```

### Rationale

| Concern | Decision |
|---|---|
| Ride UI queries | SwiftData — ergonomic @Query macros in SwiftUI |
| AppPreferences, RiderProfile — exactly one record, no queries | `@Shared(.fileStorage)` Codable structs, one document each — synchronous reads, no ModelContainer, no migration plan (see §3.6, §3.5) |
| TrackPoint — up to 3,600 rows/hour at 1 Hz | CoreData NSBatchInsertRequest — batch write avoids per-object overhead |
| Active-ride telemetry buffering | In-memory ring buffer; never written until checkpoint/end |
| RadarEvent, VehiclePassEvent — discrete | SwiftData — low frequency; UI-queryable |
| PairedSensor — a handful of records, never queried, read whole | Nested `Codable` array in the AppPreferences JSON document (#67, see §3.6) — synchronous reads, no ModelContainer |
| ConnectedService — low-frequency writes | Open. The Keychain-identifier pattern is a separate problem and nothing consumes it yet |
| iOS minimum | iOS 26 — SwiftData and Swift concurrency fully supported |

### Checkpoint Policy

- CoreData TrackPoint batch flush: every **30 seconds** of active recording
- SwiftData Ride summary update: every **30 seconds** (running totals)
- Crash recovery: last 30-second checkpoint is the recovery point (acceptable data loss)
- Ride end: final flush of all pending TrackPoints, then atomic GPX write

---

## 2. Entity Relationship Diagram

```
RiderProfile (1)          AppPreferences (1) [JSON document]
[JSON document]                ┆
                    ┌──────────┴──────────┐
                    │                     │
                (∞) PairedSensor    (∞) ConnectedService
                    (ownership open — see §3.6, §3.7)
                    ⇢ Phase 2: moves under Bike (§3.9)

(∞) Ride
    ⇢ Phase 2: gains bike: Bike? + bikeName snapshot
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
- AppPreferences is no longer a SwiftData entity, so it cannot own a SwiftData `@Relationship`. #67 settled PairedSensor by folding it into the AppPreferences JSON document as a nested `Codable` array; ConnectedService is still open — see §3.6
- **PairedSensor is app-wide only for MVP.** In Phase 2 sensors belong to a bike: each bike has its own speed, cadence, radar and power sensors, and the speed sensor also carries that wheel's circumference. Heart rate is the exception and stays rider-scoped, since the strap follows the rider across bikes. The MVP ownership #67 picked has to survive gaining that bike dimension — as a nested value it does: the array grows a `bikeID` field and the lookup key becomes (bike, role), which is a decode shim rather than a schema stage — see §3.9
- Ride and RiderProfile have no relationship — single rider; rides queried by date range. Since #96 RiderProfile is its own JSON document (§3.5), so a relationship is not expressible in any case
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

The rider's physiological inputs to the Karvonen zone calculation (§8). Exactly one record exists.

> **Revised 2026-08-17 (#96): stores *overrides*, and is not a SwiftData `@Model`.** Two changes from
> the original shape, for two separate reasons.
>
> **It is not a `@Model`,** for the reason §3.6 gives for `AppPreferences`: exactly one record exists,
> so there is nothing to `@Query` and no relationship worth traversing, while a `@Model` would put an
> async load in front of the S12 HR Zones section and flash defaults on each appearance. It is a
> `Codable` struct persisted as a single JSON document via `@Shared(.fileStorage)`, in its own
> `rider-profile.json` — a separate document from the preferences one because OQDM5 split physiology
> from preferences deliberately, and M5's Health read should have one file to touch. SwiftData
> infrastructure therefore does **not** land with this entity; it lands with M7's `Ride`, the first
> entity that genuinely needs querying.
>
> **It stores overrides rather than values.** Resting heart rate and date of birth are HealthKit's to
> own — `HKQuantityTypeIdentifier.restingHeartRate` is rewritten daily by an Apple Watch, and an
> app-owned copy goes stale the moment the rider's fitness changes. A field here is `nil` until the
> rider disagrees with Health or Health cannot answer. A rider wearing a Watch who never opens
> Settings persists nothing at all.
>
> Max heart rate is the exception that makes the type necessary rather than redundant: **HealthKit has
> no max-heart-rate type.** Only `heartRate`, `restingHeartRate`, `walkingHeartRateAverage`,
> `heartRateVariabilitySDNN` and `heartRateRecoveryOneMinute` exist. `.discreteMax` over historical
> `heartRate` samples yields *highest ever observed*, which is meaningless for a rider who has never
> gone near their limit wearing a watch — which is why PRD §9.4 falls back to 220 − age and UX.md §S12
> keeps manual entry as the fallback "when Health is denied or empty".

```swift
/// OQDM5 resolved: split from UserProfile. Physiology only.
struct RiderProfile: Codable, Equatable, Sendable {
    var restingOverrideBPM: Int?      // nil = defer to HealthKit (M5), then the default
    var maxOverrideBPM: Int?          // nil = defer to the 220 − age estimate, then the default

    // #103: the S12 HR Zones table's four internal boundaries. Each nil = defer
    // to the Karvonen-derived value; once a rider steps one it stays pinned
    // across a resting/max change until reset. Named by the zone each boundary
    // closes, not by position, so the field survives a future re-ordering of the
    // zone table.
    var zone1CeilingOverrideBPM: Int?  // Recovery/Light ↔ Endurance
    var zone2CeilingOverrideBPM: Int?  // Endurance ↔ Aerobic
    var zone3CeilingOverrideBPM: Int?  // Aerobic ↔ Threshold
    var zone4CeilingOverrideBPM: Int?  // Threshold ↔ Anaerobic

    /// Hand-written, per §9 — decodeIfPresent with an explicit default per field.
    init(from decoder: any Decoder) throws
}

extension SharedReaderKey where Self == FileStorageKey<RiderProfile>.Default {
    static var riderProfile: Self { /* Documents/rider-profile.json */ }
}
```

**#103 — the four boundary overrides.** Karvonen's fixed 60/70/80/90%-of-reserve thresholds (§8)
leave no independent value for the zone table's four *internal* boundaries — only resting and max
are free parameters. The S12 HR Zones section's `Stepper` on each of its first four rows needs one
anyway, so `RiderProfile` grew four more optionals, one per boundary, each resolved the same way as
resting/max: `override ?? karvonenDefault`. `RiderProfile.resolvedBoundaryBPM(afterZone:)` is the
resolver; `RiderProfile.bounds(for:)` is what S12's rows read, and is distinct from
`HeartRateZone.bounds(for:maxHR:restingHR:)` (§8), which has no override concept and keeps serving
every other live-zone consumer in the app unchanged.

A boundary override is set through `RiderProfile.settingBoundaryOverride(_:afterZone:)`, which
clamps strictly between the boundary's *live* neighbours — the adjacent boundary, or resting/max at
the table's outer edges — throwing `.boundaryOutOfOrder` otherwise. This is what keeps "no gap or
overlap representable" true for a table with independently-pinnable boundaries, where §8's "contiguous
by construction" guarantee no longer applies on its own (see §8). `RiderProfile.resettingZoneBoundaries()`
clears all four at once — the S12 "Reset HR Zones to Defaults" row — without touching
`restingOverrideBPM`/`maxOverrideBPM`, which have no S12 entry point.

**Resolution happens at read time** — `override ?? healthKit ?? default` — so zone boundaries follow a
Health value the moment it changes, with no local copy to re-sync. The HealthKit terms are
defaulted-`nil` parameters, so M5 supplies them without the resolver changing shape:

```swift
func resolvedRestingBPM(healthResting: Int? = nil) -> Int   // default 60
func resolvedMaxBPM(healthMax: Int? = nil) -> Int           // default 190
```

`heartRateSourceIsAppleHealth` is **not stored, and not a single flag.** It was one Bool over a pair
of values that can have different provenance, which under this model is ill-defined — max HR can
never come from HealthKit at all, so a `true` would routinely mean "resting is from Health, max is a
220 − age estimate". Provenance is a per-field question and reads directly off the profile where a
caller needs it (`restingOverrideBPM == nil && healthResting != nil`). It is false either way
throughout M10, since nothing supplies the Health terms yet.

`dateOfBirth` is not stored either — it is a HealthKit characteristic type, read via
`dateOfBirthComponents()` when M5 needs the 220 − age estimate.

**Validation** (manual entry, in the spirit of `WheelPreset.validRange`):

| Rule | Value | Reason |
|---|---|---|
| `restingValidRange` | `30...100` | Elite endurance athletes reach the low 30s; above 100 is tachycardic, not resting |
| `maxValidRange` | `100...230` | Junior riders record maxima above 200; 220 − age tops out near 220 |
| `minimumHRReserve` | `8` | **Derived, not chosen.** Karvonen bands are 10% of reserve wide, so below a reserve of 8 the rounding collapses two zone boundaries onto the same bpm and a band exists with no bpm of its own. Subsumes "resting < max" |

Rejection is non-destructive: `settingRestingOverride(_:healthMax:)` /
`settingMaxOverride(_:healthResting:)` return a new profile or throw `ValidationError`, so a caller
that gets nothing back still holds what it started with. They copy the profile rather than rebuilding
it field by field, so a field added later survives an HR edit. Passing `nil` clears an override and is
always allowed — deferring to Health cannot be invalid.

**The `health*` terms must be the ones the caller reads with.** The reserve floor is otherwise checked
against a value the app will not use: with a Health resting of 100 and no override, validating a max
of 105 against the *default* resting of 60 sees a reserve of 45 and accepts, while the live reserve is
5 — below the floor, and back in the range where the zone table degenerates.

---

### 3.6 AppPreferences

All non-physiological preferences. Exactly one record exists.

> **Revised 2026-08-03 (#69): not a SwiftData `@Model`.** Exactly one record exists, so there is
> nothing to `@Query` and no relationship worth traversing, while a `@Model` would put an async
> load in front of every consumer — including the Settings screen, which would flash a default
> value on each appearance. It is instead a `Codable` struct persisted as a single JSON document
> via swift-sharing's `.fileStorage` strategy, which TCA already vends (`@Shared`). Reads are
> synchronous, tests get quarantined storage for free, and there is no `ModelContainer` or
> `SchemaMigrationPlan` in the path. SwiftData remains the store for Ride, RadarEvent and
> VehiclePassEvent, which do need querying.
>
> > **RiderProfile left this list at #96 (2026-08-17).** It is one record of two scalars, so every
> > word of the reasoning above applied to it verbatim — see §3.5. SwiftData now has no entity in
> > MVP until M7's `Ride`.

**Why JSON rather than a plist** (asked in the PR #83 review). Both are available — swift-sharing's
`fileStorage(_:decoder:encoder:)` overload is JSON-specific, but the lower-level
`fileStorage(_:decode:encode:)` takes arbitrary closures, so `PropertyListEncoder` /
`PropertyListDecoder` drop straight in. At this size neither wins on performance: the document is
one `Int` today and a few scalars plus a handful of sensor records at its largest, so binary plist's
compactness and parse speed buy nothing measurable.

The tiebreakers are tooling and fidelity, and they point in opposite directions:

| | JSON | Plist |
|---|---|---|
| swift-sharing support | The documented default overload | Works, via the manual encode/decode closures |
| Debug inspection | `cat` — and in DEBUG swift-sharing's default encoder is `[.prettyPrinted, .sortedKeys]`, so the file is stably ordered and diffable | Binary needs `plutil -p`; XML is readable but verbose |
| `Date` / `Data` fidelity | `Date` encodes as a bare `Double` (`timeIntervalSinceReferenceDate`) — exact, but opaque when reading the file | Native date and data types |
| Portability | Trivially readable by anything, if preferences are ever exported or inspected off-device | Apple-only in practice |

JSON wins today because the document is all scalars, where plist's one real advantage — native
`Date` and `Data` — has nothing to apply to. **Revisit if `AppPreferences` gains date fields**
(calibration timestamps, token expiry): at that point the file stops being self-describing and plist
becomes the better read. The strategy lives behind the single `.appPreferences` static key, so the
switch is a one-line change plus a one-shot re-encode.

> Note: "use a plist" is also, in effect, what `UserDefaults` is — `UserDefaults` *is* a plist store,
> and `@Shared(.appStorage)` is the idiomatic way to reach it. That was considered and rejected when
> this was designed: `appStorage` handles scalars and `RawRepresentable`s, not a `Codable` struct,
> so it cannot hold AppPreferences as one value.

**Implemented today** (`Cyclometer/Cyclometer/Models/AppPreferences.swift`) — fields land as their
consumers do, so wheel circumference and paired sensors are present:

```swift
struct AppPreferences: Codable, Equatable, Sendable {
    /// OQDM9 noted: one global value for MVP — the app assumes a single bike.
    /// Phase 2 moves this onto the speed-role PairedSensor, since a hub-mounted
    /// CSC sensor is already bound to one wheel and bikes own their sensors. See §3.9.
    var wheelCircumferenceMM: Int = WheelPreset.default.circumferenceMM   // 2096
    /// §3.7. The source of truth for which peripherals the app connects to —
    /// BLECSCClient adopts nothing on its own and is told via setPairedSensors.
    var pairedSensors: [PairedSensor] = []

    /// #110. Gates the idle dim only — the wake lock is not a preference.
    var isAutoDimEnabled: Bool = true
    /// #94. Defaults to the device locale's measurement system via `UnitSystem(.current)`.
    /// Not yet read: ActiveRideFeature.unitSystem is still seeded from Locale per-feature
    /// and the S12 picker is still a disconnected String — unifying them is #102 and #8.
    var preferredUnit: UnitSystem = .system
    /// #94. Not yet read: SettingsFeature still toggles its own copy, and the stop
    /// detection the ride state machine needs lands with #102.
    var isAutoPauseEnabled: Bool = true

    func pairedSensor(for role: SensorRole) -> PairedSensor?
    /// CSC-role records only (#93). The collection also holds radar and HR records,
    /// and BLECSCClient only speaks 0x1816 — see §3.7's role enum note.
    var cscAssignments: [UUID: Set<SensorRole>]   // peripheral → roles

    /// Hand-written: the synthesised init(from:) throws on a missing key rather
    /// than using the property default. See §9.
    init(from decoder: any Decoder) throws
}

extension SharedReaderKey where Self == FileStorageKey<AppPreferences>.Default {
    static var appPreferences: Self {
        Self[
            .fileStorage(.documentsDirectory.appending(component: "app-preferences.json")),
            default: AppPreferences()
        ]
    }
}
```

Consumed by `SettingsFeature` (read/write, pushing each change to
`BLECSCClient.setWheelCircumference`), `SpeedFeature` (`@SharedReader`, applied at ride start),
`DeviceManagementFeature` (read/write, pushing each pairing change to
`BLECSCClient.setPairedSensors`) and `AppFeature` (`@SharedReader`, pushing the assignments once at
launch so paired sensors reconnect without the Sensors screen being open).

**Still to land**, with the feature that consumes it:

```swift
// OQDM8 resolved: mapOrientation is real — PRD section 8.6 specifies heading-up vs north-up
// as a user-toggleable setting. Persisted so the rider's choice survives app restarts.
var mapOrientation: MapOrientation  // default .headingUp

enum MapOrientation: String, Codable { case headingUp, northUp }
```

> **`mapOrientation` deferred at #94 (2026-08-16).** The other three fields of that issue landed;
> this one did not, because it has no consumer and none planned in M10. PRD §8.6 puts the
> heading-up/north-up choice on the map's own compass, not in Settings, and UX.md §S12 has no row
> for it — so the field would persist a value nothing writes and nothing reads. It lands with the
> issue that makes `ActiveRideMapView`'s camera orientation survive a relaunch.

> **`shouldSetDoNotDisturb` removed 2026-08-14 (M10).** iOS exposes no public API for an app to enable a
> Focus, so the field had no behavior to persist and the S12 toggle it backed has been deleted — from
> UX.md §S12 then, and from `SettingsFeature`/`SettingsView` at #94. Nothing ever shipped reading or
> writing it, so there is no migration and no shim: §9's rule is *leniency*, not strictness, so a
> document carrying an unrecognised key decodes normally with the key ignored and every other
> preference intact. No such document exists in the first place.

> **`isAutoDimEnabled` is real and implementable**, unlike its neighbor: `UIApplication.shared
> .isIdleTimerDisabled` is public API, and auto-dim means declining to hold the idle timer open during a
> ride rather than setting screen brightness directly.

**Resolved (#67) — PairedSensor is a nested `Codable` array, not a `@Model`.** §3.6 previously held
these as cascade-deleting `@Relationship` collections. With AppPreferences out of SwiftData that is
no longer possible as written, and the choice was between standalone `@Model`s queried by
`role` / `serviceType`, and nested `Codable` arrays inside this document. #67 took the latter, and
§3.7 is written against it:

- **Nothing to query.** Three to five records exist, always read whole and always by role. The
  criterion §3.6 applies to AppPreferences itself — "is there anything to `@Query`?" — answers the
  same way here.
- **Synchronous reads.** `DeviceManagementFeature.State` derives its Paired and Available sections
  from `preferences.pairedSensors` directly, the way `SettingsFeature.wheelSelection` derives from
  `wheelCircumferenceMM`. A `@Model` would put an async load in front of that.
- **The infrastructure already exists.** #69 shipped `@Shared(.fileStorage)` with a proven
  test-quarantine idiom (`FileStorage.inMemory`). SwiftData has no `@Model` in the app but the
  Xcode template's `Item`, no `ModelContainer` test fixture, and `SwiftDataStack` is unreferenced
  with an empty schema. **Still true after #96** — `RiderProfile` was expected to land that
  infrastructure and did not, having gone the same way for the same reasons (§3.5). M7's `Ride` is
  now the first entity that needs it.

`ConnectedService` is untouched and still open — its Keychain-identifier pattern is a different
problem, and nothing consumes it yet.

---

### 3.7 PairedSensor

One BLE sensor in a specific role. A single physical device may appear twice — once for .speed, once for .cadence — when a combo CSC sensor is assigned both roles (same peripheralIdentifierString, different role values).

> **Not a SwiftData `@Model` (#67).** A `Codable` struct nested in the AppPreferences document — the reasoning is in §3.6's resolved note.

> **Role-keyed lookup is an MVP simplification.** One sensor per role, app-wide. Phase 2 gives every bike its own speed, cadence, radar and power sensors, so the lookup key becomes (bike, role) — see §3.9. Heart rate is the exception: the strap follows the rider, not the bike.

**One record per role, enforced by a prompt (2026-08-14, M10).** Pairing a sensor into an occupied role does
not append a second record and does not silently overwrite the first. S11 raises a replace-or-cancel
confirmation naming the incumbent, and only Replace writes (UX.md §S11). The consequences for this entity:

- **The collection stays keyed by role.** `pairedSensor(for:)` returns at most one record, and no arbitration
  rule is needed at connect time. An earlier reading of UX.md §S11 — "active source by connection order,
  first wins" — was taken to mean several sensors of one type could be paired simultaneously. It does not:
  the rider resolves the collision at pairing time, so there is never more than one candidate to arbitrate
  between.
- **Replace is a two-part write.** The incumbent's record for the colliding role is removed and the new one
  added in the same `withLock` mutation, so no intermediate state has the role vacant or doubly occupied.
- **A partial replace can leave a peripheral holding no roles**, when a combo sensor is displaced on one role
  and never held the other. That peripheral is unpaired outright — `setRoles` rejects an empty set (BLE.md
  §5.0), so a zero-role record is not representable.

**Implemented today** (`Cyclometer/Cyclometer/Models/PairedSensor.swift`):

```swift
/// OQDM6 resolved: replaces fixed UUID string fields on AppPreferences.
struct PairedSensor: Codable, Equatable, Sendable {
    var peripheralID: UUID            // CBPeripheral.identifier — stable per device per iOS install
    var role: SensorRole
    var displayName: String?          // From BLE advertisement, at pairing time
}
```

Three departures from the `@Model` sketch this replaces, each because the record is now a value in a
JSON document rather than a row:

- **`peripheralID` is a `UUID`,** not `peripheralIdentifierString` plus a parsing accessor. The string
  was a SwiftData accommodation; JSON round-trips `UUID` natively.
- **No synthetic `id`.** Nothing addresses a record by identity — lookup is by role, and a peripheral's
  records are replaced wholesale when its roles change.
- **No `modelIdentifier`.** Nothing reads it. It lands with the screen that shows it.

`displayName` is retained rather than always read live so a paired sensor that is out of range still
has a name on the Sensors screen, where there is no advertisement to name it.

**Role enum.** Nested inside `BLECSCClient` with two cases until #93, which moved it to
`Cyclometer/Cyclometer/Models/SensorRole.swift` and added radar and heart rate for S11 — additive, and
enum cases need no migration (§9). Shipped shape:

```swift
enum SensorRole: String, Codable, Hashable, CaseIterable, Sendable {
    case radar
    case heartRate
    case speed      // CSC profile — wheel revolution data
    case cadence    // CSC profile — crank revolution data
    case power      // Phase 3

    /// The roles BLECSCClient can fill; `AppPreferences.cscAssignments` filters on it.
    static let cscRoles: Set<SensorRole> = [.speed, .cadence]
}
```

`Hashable` and `CaseIterable` are load-bearing rather than incidental: `Set<SensorRole>` needs the
first, and `allCases` supplies both the S11 row subtitle's role order and the order records are written
in, so `Set`'s non-determinism never reaches the file. Declaration order is therefore part of the
contract too, and `AppPreferencesTests` pins it.

`power` is declared now though Phase 3 owns the hardware: the raw value is then fixed by the same test
that pins the rest, rather than being chosen later against live records.

**Not every role is a CSC role.** `cscRoles` is what keeps radar, HR and power peripherals away from a
client that only speaks 0x1816, and `PairedSensor.isCSC` is the per-record form of the same test. Both
matter because the collection is shared: S11 is CSC-only until #98 unifies discovery, so every
membership test and every removal that screen performs has to scope itself, or a peripheral serving
more than one profile loses its other pairings — or is hidden from the screen because something else
already claimed it (#93).

> **The raw values are the persisted contract.** Renaming a case silently orphans every record that
> used it; `AppPreferencesTests` pins them for that reason.

---

### 3.8 ConnectedService

A connected third-party service. OAuth tokens live in the iOS Keychain; this entity holds only the lookup key and display metadata.

> **Deferred to Phase 2 (M13), 2026-08-14.** The S12 Accounts section that would create these records has
> moved out of MVP (UX.md §S12), and its only other consumer — the Ride Summary sync sheet — was already
> Phase 2. Nothing in MVP reads or writes this entity, so it stays specified and unimplemented. The ownership
> question below is deferred with it.

> Same open ownership question as §3.7 — no `@Relationship` owner since #69.

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

### 3.9 Bike (Phase 2 — not implemented)

**A rider owns more than one bike, and the model must eventually reflect that.** MVP deliberately
does not: wheel circumference is a single global value on AppPreferences (§3.6) and paired sensors
are keyed by role alone (§3.7), which means one road bike's speed sensor and one gravel bike's are
indistinguishable to the app. That is a scoping decision for MVP, not a belief that riders have one
bike. Everything below is the shape the schema grows into; it is recorded here so MVP choices are
made with the destination in view, not discovered as a rewrite in Phase 2.

> **Revised 2026-08-08 (PR #83 review).** An earlier draft of this section gave each bike a
> collection of `Wheelset` records. That entity is gone — see "Why there is no Wheelset entity"
> below. Circumference belongs on the speed sensor. Research basis is in PRD §8.9.1.

**What belongs to a bike, not to the app:**

| Today (MVP) | Phase 2 |
|---|---|
| `AppPreferences.wheelCircumferenceMM` — one global value | Moves to the speed-role `PairedSensor`. A BLE CSC speed sensor mounts on the wheel hub, so the sensor is already bound to exactly one wheel — it *is* the wheel's identity, and no separate wheelset entity is needed |
| `PairedSensor` keyed by `SensorRole` alone — one sensor per role, app-wide | Sensors belong to a bike. Each bike has its own speed, cadence, radar and (Phase 3) power sensors. The same physical HR strap follows the *rider* across bikes, so heart rate stays rider-scoped, not bike-scoped |
| Ride has no bike association | `Ride.bike: Bike?` **plus a denormalized `bikeName` snapshot.** Ride history must be able to tell the rider which bike they rode, and that must survive deleting or renaming the bike — the same pattern §3.1 already uses for `routeName` |

```swift
/// Sketch only — not built. Relationships and delete rules settle when this lands.
@Model
final class Bike {
    var id: UUID
    var name: String                            // "Tarmac", "Checkpoint"
    var isDefault: Bool                         // Pre-selected in the S05.1 bike picker
    var sensors: [PairedSensor]                 // Speed, cadence, radar, power — per bike

    /// Strava calls bikes "gear" and keys them by an id like "b1234567". Uploading
    /// an activity can name the gear it was ridden on, so a Cyclometer bike needs
    /// to map onto the rider's Strava bike or the association is lost on export.
    /// Fetched from the Strava athlete endpoint; nil until the rider links them.
    var stravaGearID: String?
}

// §3.7 PairedSensor gains, for the .speed role only:
//     var wheelCircumferenceMM: Int?
//     var isAutoCalibrated: Bool     // whether §8.9 has adjusted the value
```

**Why there is no Wheelset entity.** A rider with two wheelsets is already served: a hub-mounted
speed sensor travels with its wheel, so each wheelset that has a sensor carries its own
circumference and its own calibration history for free. A rider who owns two wheelsets but only one
sensor moves the sensor between them and re-enters the circumference — which is exactly what a
Garmin Edge does today, and is not a gap worth an entity. If per-wheelset naming and swap-without-
re-entry ever justify themselves, that is a **third major release** conversation at the earliest;
it is explicitly out of scope for both MVP and Phase 2. Evidence and target-audience reasoning:
PRD §8.9.1.

**Consequences to keep in mind while building MVP:**

- **Ride start must eventually ask which bike.** UX.md S05.1 and S05.2 already reserve a bike picker
  for Phase 2. Anything that reads wheel circumference or paired sensors at ride start (today
  `SpeedFeature.startListening`) becomes "read it *for the selected bike*" — so that read wants to
  stay in one place rather than spreading across features.
- **Sensor pairing (#67) is where this bites first, and it is the natural home for circumference.**
  #67 creates `PairedSensor`; if circumference is going to live there, that is worth knowing while
  its shape is being decided, even though the field itself is not in #67's scope.
- **Auto-calibration (#70) writes globally in MVP.** Once circumference moves to the speed sensor,
  calibration writes to the sensor that produced the distance — which is the correct scope, since
  that sensor is on the wheel being calibrated. Until then it writes the single global value: a
  rider who swaps a single sensor between bikes gets the last bike's calibration applied to the
  next. Accepted MVP limitation, not a bug to file.

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
// Not @Query — a synchronous read off the AppPreferences document (#67)
let speedSensor = preferences.pairedSensor(for: .speed)
let cadenceSensor = preferences.pairedSensor(for: .cadence)
// These may return the same peripheralID for a combo sensor assigned both roles.
// Grouped the other way for the client, which connects per peripheral, not per role:
let assignments = preferences.cscAssignments   // [UUID: Set<SensorRole>], CSC roles only
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

Implemented as `HeartRateZone` (`Models/HeartRateZone.swift`), which owns both directions. Callers go
through `RiderProfile.zone(forBPM:)`, which feeds it the resolved values from §3.5.

```swift
enum HeartRateZone: Int { case zone1 = 1, zone2, zone3, zone4, zone5 }

/// bpm → zone. intensity = (bpm − restingHR) / (maxHR − restingHR)
static func zone(bpm: Int, maxHR: Int, restingHR: Int) -> HeartRateZone {
    let hrr = Double(maxHR - restingHR)
    guard hrr > 0 else { return .zone1 }
    switch Double(bpm - restingHR) / hrr {
    case ..<0.60: return .zone1   // Recovery
    case ..<0.70: return .zone2   // Endurance
    case ..<0.80: return .zone3   // Tempo
    case ..<0.90: return .zone4   // Threshold
    default:      return .zone5   // VO2 Max
    }
}

/// zone → bpm range, the inverse. What a zone table displays (UX.md §S12).
static func bounds(for zone: HeartRateZone, maxHR: Int, restingHR: Int) -> ClosedRange<Int>
```

`bounds` uses integer arithmetic — `restingHR + ⌈percent × HRR / 100⌉` — rather than rounding a
`Double` product back to a bpm, so **within the reserve** it is the exact inverse of the forward
formula. Both ends are closed at the profile (zone 1 opens at `restingHR`, zone 5 closes at `maxHR`)
because that is what a table should show; a reading outside the reserve is still classified — below
`restingHR` is zone 1, above `maxHR` is zone 5 — but falls outside the range returned. Display uses
the closed form; membership tests use the forward formula. Ceiling, not
rounding: a threshold is inclusive at the bottom, so a boundary bpm belongs to the zone it opens.
Ranges are contiguous by construction (each zone ends one bpm below the next one's start), which is
what makes "no gaps or overlaps are representable" true for the *unoverridden* table rather than
merely intended. `RiderProfile.bounds(for:)` (§3.5) is what S12's rows actually read: once a rider
pins one of the table's four internal boundaries (#103), that boundary no longer moves with resting
or max HR, and contiguity is guaranteed instead by `RiderProfile.settingBoundaryOverride(_:afterZone:)`
clamping every write against the boundary's live neighbours — a second guarantee doing the same job
this construction argument does for the default case.

> The two directions agree exactly **only above `RiderProfile.minimumHRReserve` (8)**. At a reserve of
> 7 or less the ceiling collapses two zone boundaries onto one bpm, leaving a band with no bpm of its
> own, and `bounds` would return a range for a zone no reading can fall in. That is why the floor is a
> validation rule (§3.5) rather than a rounding tweak here.

### Worked example

Resting 60, max 190 — the §3.5 defaults. HRR = 130.

| Zone | Name | % HRR | Lower bpm | Range |
|---|---|---|---|---|
| 1 | Recovery | < 60% | resting | **60–137** |
| 2 | Endurance | 60% | 60 + ⌈78.0⌉ = 138 | **138–150** |
| 3 | Tempo | 70% | 60 + ⌈91.0⌉ = 151 | **151–163** |
| 4 | Threshold | 80% | 60 + ⌈104.0⌉ = 164 | **164–176** |
| 5 | VO2 Max | ≥ 90% | 60 + ⌈117.0⌉ = 177 | **177–190** |

Readings below resting resolve to zone 1 and above max to zone 5. A non-positive reserve resolves to
zone 1 rather than dividing by zero — unreachable through validation, but the guard is pinned by test.

---

## 9. Migration Strategy

| Schema Version | Changes |
|---|---|
| 1.0 (MVP) | All entities as specified above |
| 1.1 (Phase 2 — Routes) | Add Route @Model; add Ride.route: Route?; migrate Ride.routeName |
| 1.2 (Phase 2 — Bikes) | Add Bike @Model (§3.9) — no Wheelset entity. Add `wheelCircumferenceMM` + `isAutoCalibrated` to PairedSensor and move the value there from the AppPreferences document's top level. Re-key PairedSensor from role to (bike, role), migrating existing records onto a default Bike; leave heart-rate sensors rider-scoped. **None of the PairedSensor work is a schema stage** — since #67 it is a nested `Codable` value, so this is a one-shot read-then-write at launch plus a decode shim. Add `Bike.stravaGearID`, `Ride.bike` and the `Ride.bikeName` snapshot |
| 2.0 (Phase 3 — Power) | Add TrackPointMO.powerWatts column; add Ride.powerAverageWatts |

Key rules:
- Never rename SwiftData properties without a SchemaMigrationPlan stage
- AppPreferences **and RiderProfile** are outside the SwiftData schema (§3.6, §3.5), but **adding a field is only free because they have a hand-written `init(from:)`**. The synthesised `Decodable` does *not* fall back to a property's default when its key is absent — it throws `keyNotFound`, `.fileStorage` swallows that and hands back a default-constructed value, and the rider silently loses every *other* preference in the document. #67 found this the first time a second field was added. Every field is decoded with `decodeIfPresent` and an explicit default; new fields must follow. Renaming or removing one still needs a shim on top of that
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
| Karvonen zone calculation | Unit — RiderProfileTests, HeartRateZoneTests | All 5 zone boundaries against §8's worked example; HR below resting; HR above max; non-positive reserve. `bounds` round-trips through `zone(bpm:)` at every range endpoint across the full validated profile sweep, and the ranges are contiguous |
| RiderProfile resolution and validation | Unit — RiderProfileTests | `override ?? health ?? default` per field, resolved independently; both ranges at their edges; `reserveTooSmall`; rejection leaves the profile untouched; clearing to nil always allowed; decode leniency for a missing key, an explicit null and an unrecognised key |
| VehiclePassEvent detection | Unit — VehiclePassDetectionTests | Overtake vs turn-off; 2s minimum tracking; closing speed sign |
| NSBatchInsertRequest flush | Integration — PersistenceTests | 3,600 rows (1 hour); count and rideId linkage verified |
| GPXExporter output | Unit — GPXExporterTests | Schema validation; namespace declarations; absent vs zero fields |
| RideDataBuffer concurrency | Unit — RideDataBufferTests | Concurrent appends; drain ordering; capacity ring behaviour |
| Ride summary aggregates | Unit — RideAggregateTests | Running avg/max; zone duration accumulation; paused interval exclusion |
| SensorSource priority switching | Unit via TCA TestStore | All transitions in priority chain; source badge updates |
| Wheel auto-calibration math | Unit — WheelCalibrationTests | 2% trigger; 10% cap; out-of-range rejection; GPS accuracy gating |
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
| OQDM5 | Why is the entity called UserProfile? | Resolved — split into RiderProfile (physiology) and AppPreferences (preferences, sensors, services). #96 kept them separate documents and narrowed RiderProfile to HR overrides: the rest of "physiology" (resting HR, date of birth) is HealthKit's, not the app's |
| OQDM6 | Sensor storage limited to fixed fields | Resolved. PairedSensor @Model with role: SensorRole. Any number of sensors of any role |
| OQDM7 | Connected services list is fixed | Resolved. ConnectedService @Model with serviceType: ExternalService. New services add an enum case |
| OQDM8 | What is mapOrientation for? | Resolved — it is real. PRD section 8.6 specifies heading-up vs north-up as a user-toggleable setting; stored in AppPreferences to persist across sessions |
| OQDM9 | Store bike information | Deferred to Phase 2, shape recorded in §3.9. A rider owns several bikes; each bike owns its speed/cadence/radar/power sensors and maps to a Strava gear id. Wheel circumference lives on the speed sensor, not on the bike and not on a wheelset entity — a hub-mounted CSC sensor is already bound to one wheel (research: PRD §8.9.1). Heart rate stays rider-scoped. Ride gains `bike` + a `bikeName` snapshot so history always names the bike ridden |
| OQDM10 | Capture weather conditions for a ride | Resolved. RideWeather Codable value type stored as JSON on Ride. Fields: temperature, wind speed, wind direction, conditions, humidity, capture timestamp |

---

*Cyclometer Data Model Spec v1.4 · 2026-08-17*
