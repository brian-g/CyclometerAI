# Cyclometer — TCA Architecture Map
**Version:** 1.2  
**Date:** 2026-05-21  
**Updated:** 2026-05-22 - HKWorkout write at ride end; SyncClient + RideSummaryFeature spec; service sync from S10  
**Updated:** 2026-11-21 - Strava (Phase 2, PRD §8.12): new §4.15 `KeychainClient`, `StravaAuthClient`, `StravaClient`, `AccountsFeature`, `SyncQueueFeature`, `StravaRoutesFeature`; S10's Sync To replaces `RideSyncSheetFeature`  
**Updated:** 2026-09-30 - §3 and §8 rewritten to match the implemented tree (#339, #342)  
**Updated:** 2026-10-09 - `AltimeterClient` and `LocationUpdate.verticalAccuracy` (#387)  
**Updated:** 2026-11-24 - §4.15 `StravaClient` built (#627): `refreshAccessToken(rejected:)` on `StravaAuthClient`, `StravaError`, rate-limit reset at midnight UTC when a daily count is spent  
**Updated:** 2026-11-25 - §4.15 follows Strava's API terms (PRD §8.12 v0.6.28): `StravaRoutesFeature` caches Strava routes rather than importing them, `AppFeature` purges Strava data older than seven days, and S15's `segments` child refetches after a day and presents S15.1. S20's `segments` child and `RouteSegmentMatcher` are dropped with S20 segments (#637)  
**Updated:** 2026-11-25 - §4.15 `AccountsFeature` built (#629): S12.1 only, pushed on `SettingsFeature.path`; S12's Strava row is Settings' own state. Disconnect is confirmed in S12.1 and run by `SettingsFeature` after the pop. `StravaClient.athlete` built  
**Status:** Draft — Ready for Engineering Review  
**Author:** Brian (UX Design) + Claude (Specification)  
**Companion Documents:** `PRD.md §11`, `BLE.md`, `DataModel.md`

---

## 1. Why The Composable Architecture

Cyclometer has five concurrent real-time data streams active during a ride:

| Stream | Source | Update Rate |
|---|---|---|
| Radar alerts | Garmin Varia BLE | ~2 Hz (variable) |
| Heart rate | BLE HR strap or Apple Watch | ~1 Hz |
| Speed / cadence | BLE CSC sensor | ~1 Hz |
| GPS position | CoreLocation | 1 Hz |
| Track point recording | Derived from above | 1 Hz (timer) |

All five must be combined, prioritized, and translated into UI state, haptics, audio, and GPX data — simultaneously — without race conditions, without global mutable state, and with every unit of alert logic fully testable without hardware.

TCA's `Effect`, `@Dependency`, `Reducer`, and `TestStore` are the best available Swift primitives for this problem.

---

## 2. Dependency Clients

All side effects are injected as `@Dependency` values. No feature directly imports CoreBluetooth, CoreLocation, AVFoundation, or CoreData.

```swift
// Registered in DependencyValues:

@Dependency(\.bluetooth)          var bluetooth: BluetoothClient
@Dependency(\.healthKit)          var healthKit: HealthKitClient
@Dependency(\.location)           var location: LocationClient
@Dependency(\.haptic)             var haptic: HapticClient
@Dependency(\.audioAlert)         var audioAlert: AudioAlertClient
@Dependency(\.persistence)        var persistence: PersistenceClient
@Dependency(\.navigation)         var navigation: NavigationClient
@Dependency(\.wheelCalibration)   var wheelCalibration: WheelCalibrationClient
@Dependency(\.sync)              var sync: SyncClient            // Phase 2: superseded by SyncQueueFeature + StravaClient (§4.15)
@Dependency(\.keychain)          var keychain: KeychainClient    // Phase 2 (§4.15)
@Dependency(\.stravaAuth)        var stravaAuth: StravaAuthClient
@Dependency(\.strava)            var strava: StravaClient
@Dependency(\.continuousClock)    var clock: any Clock<Duration>  // TCA built-in
```

### 2.1 Client Protocols

```swift
@DependencyClient struct BluetoothClient        // See BLE.md §7
@DependencyClient struct HealthKitClient
@DependencyClient struct LocationClient
struct AltimeterClient                          // #387: CMAltimeter readings; AltitudeResolver picks the ride's altitude
@DependencyClient struct HapticClient
@DependencyClient struct AudioAlertClient
@DependencyClient struct PersistenceClient
@DependencyClient struct NavigationClient
@DependencyClient struct WheelCalibrationClient
@DependencyClient struct SyncClient
```

Key client outlines (not in BLE.md):

```swift
@DependencyClient
struct HealthKitClient: Sendable {
    // Read — used at onboarding and ride start
    var readRiderProfile: @Sendable () async throws -> HealthKitRiderData = { HealthKitRiderData() }
    // Write — HKWorkout recorded when S10 closes with Sync To's Apple Health on (revised 2026-11-22; not automatic)
    var recordWorkout: @Sendable (HKWorkoutPayload) async throws -> Void = { _ in }
    // Stream — HR updates when Apple Watch is active HR source
    var heartRateStream: @Sendable () -> AsyncStream<Int> = { AsyncStream { _ in } }
}

struct HealthKitRiderData: Sendable {
    var restingHeartRateBPM: Int?
    var maxHeartRateBPM: Int?
    var dateOfBirth: Date?
}

struct HKWorkoutPayload: Sendable {
    var startDate: Date
    var endDate: Date
    var distanceMeters: Double
    var activeEnergyBurnedKcal: Double?    // nil if not calculable in MVP
}

@DependencyClient
struct SyncClient: Sendable {
    /// Upload a ride GPX to a connected service. Returns the remote activity ID on success.
    var uploadRide: @Sendable (UUID, ExternalService) async throws -> String = { _, _ in "" }
    /// Fetch connected services that are enabled and have valid tokens.
    var availableServices: @Sendable () async -> [ExternalService] = { [] }
}

@DependencyClient
struct HapticClient: Sendable {
    var fireL1Advisory: @Sendable () async -> Void = {}
    var fireL2Warning: @Sendable () async -> Void = {}
    var fireL3Danger: @Sendable () async -> Void = {}
}

@DependencyClient
struct AudioAlertClient: Sendable {
    var playWarning: @Sendable () async -> Void = {}   // L2
    var playDanger: @Sendable () async -> Void = {}    // L3; overrides Silent Mode if user opt-in
    var playAllClear: @Sendable () async -> Void = {}  // L0 (after L2 or L3)
}

@DependencyClient
struct LocationClient: Sendable {
    var startUpdates: @Sendable () -> AsyncStream<LocationUpdate> = { AsyncStream { _ in } }
    var stopUpdates: @Sendable () async -> Void = {}
}

struct LocationUpdate: Sendable {
    let coordinate: Coordinate
    let altitude: Double?             // nil when CoreLocation marks it invalid (#303)
    var verticalAccuracy: Double?     // #387: what may anchor the relative barometer
    let speed: Double          // m/s (-1 if invalid)
    let horizontalAccuracy: Double
    let heading: Double        // degrees; -1 if unavailable
    let timestamp: Date
}

@DependencyClient
struct PersistenceClient: Sendable {
    var createRide: @Sendable (UUID, Date) async throws -> Void = { _, _ in }
    var updateRideSummary: @Sendable (RideSummaryUpdate) async throws -> Void = { _ in }
    var finalizeRide: @Sendable (UUID, Date) async throws -> Void = { _, _ in }
    var flushTrackPoints: @Sendable ([TrackPointDTO]) async throws -> Void = { _ in }
    var appendRadarEvent: @Sendable (RadarEvent) async throws -> Void = { _ in }
    var appendVehiclePassEvent: @Sendable (VehiclePassEvent) async throws -> Void = { _ in }
    // No profile or preferences calls: RiderProfile and AppPreferences are JSON documents read
    // through @Shared(.riderProfile) / @Shared(.appPreferences) (DataModel.md §3.5, §3.6).
    var fetchRides: @Sendable () async throws -> [Ride] = { [] }
}
```

---

## 3. Feature Tree

As implemented. `AppFeature` owns the tab shell directly (there is no `TabFeature`), and the ride
dashboard and post-ride summary both hang off the app root rather than a tab.

```
AppFeature                             (App/ — tab selection, ride lifecycle, presentation)
├── OnboardingFeature                  (optional; first launch)
│   ├── WelcomeFeature
│   └── SensorPairingFeature
│       └── DeviceManagementFeature    (shared with Settings)
├── RidesFeature                       (Rides tab — S14 list)
│   └── path: RideDetailFeature        (StackState)
├── RoutesFeature                      (S19 — list, map-as-filter, import, filter sheet)
│   └── path: RouteDetailFeature       (S20, StackState)
├── SettingsFeature                    (S12)
│   ├── DeviceManagementFeature        (S11)
│   └── path: AccountsFeature          (S12.1, StackState)
├── StartSheetFeature                  (@Presents — S05.1)
│   └── path: RoutePickerFeature       (S05.2, pushed on the sheet's own stack)
├── ActiveRideFeature                  (optional — S05 dashboard; accessory is a view, not a feature)
│   ├── SpeedFeature
│   ├── CadenceFeature
│   ├── WheelCalibrationFeature
│   ├── AlertOrchestratorFeature
│   ├── TrackPointRecorderFeature
│   └── NavigationFeature              (route, turn alerts)
└── RideSummaryFeature                 (@Presents — S10, post-ride)
```

Heart rate, radar and location are not child features: `ActiveRideFeature` consumes their
clients (`bleHRClient`/`healthKitClient`, `variaRadarClient`, `locationClient`) directly. The
per-sensor specs in §4 describe that state and behaviour; where §4 names a `RadarFeature`,
`HeartRateFeature` or `LocationFeature`, read it as that slice of `ActiveRideFeature`.

---

## 4. Feature Specifications

### 4.1 AppFeature

The root reducer. Manages onboarding state and passes control to TabFeature when onboarding is complete.

```swift
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var onboarding: OnboardingFeature.State?   // non-nil during onboarding
        var tab: TabFeature.State = TabFeature.State()
        var activeRide: ActiveRideFeature.State?   // non-nil when ride is active
        @SharedReader(.appPreferences) var preferences   // DataModel.md §3.6; loads itself
    }

    enum Action {
        case onboarding(OnboardingFeature.Action)
        case tab(TabFeature.Action)
        case activeRide(ActiveRideFeature.Action)
        case appLaunched
        case onboardingCompleted
    }
}
```

---

### 4.2 TabFeature

Manages the three-tab `TabView`. The `ActiveRideAccessory` is driven by `RidesTabFeature` state, not a separate tab.

```swift
@Reducer
struct TabFeature {
    @ObservableState
    struct State: Equatable {
        var selectedTab: Tab = .rides
        var ridesTab: RidesTabFeature.State = .init()
        var routesTab: RoutesTabFeature.State = .init()
        var settingsTab: SettingsTabFeature.State = .init()
    }

    enum Tab: Hashable { case rides, routes, settings }

    enum Action {
        case tabSelected(Tab)
        case ridesTab(RidesTabFeature.Action)
        case routesTab(RoutesTabFeature.Action)
        case settingsTab(SettingsTabFeature.Action)
    }
}
```

---

### 4.3 RidesTabFeature

Manages the Rides tab, start sheet, and active ride accessory strip.

```swift
@Reducer
struct RidesTabFeature {
    @ObservableState
    struct State: Equatable {
        var rides: [RideSummary] = []              // Phase 2: populated from persistence
        var isShowingStartSheet: Bool = false
        var startSheet: StartSheetFeature.State?
        var hasActiveRide: Bool = false            // Drives accessory strip visibility
        var accessory: ActiveRideAccessoryFeature.State? // Non-nil when ride active
    }

    enum Action {
        case startRideButtonTapped
        case startSheet(StartSheetFeature.Action)
        case rideStarted(UUID)
        case rideEnded
        case accessory(ActiveRideAccessoryFeature.Action)
        case deleteRide(RideSummary)
    }
}
```

---

### 4.4 ActiveRideFeature

The primary ride feature. Coordinates all sensor sub-features and drives the dashboard UI.

```swift
@Reducer
struct ActiveRideFeature {
    @ObservableState
    struct State: Equatable {
        var rideId: UUID
        var recordingState: RideRecordingState = .idle

        // Sub-feature states
        var radar: RadarFeature.State
        var heartRate: HeartRateFeature.State
        var speed: SpeedFeature.State
        var cadence: CadenceFeature.State
        var location: LocationFeature.State
        var trackRecorder: TrackPointRecorderFeature.State
        var wheelCalibration: WheelCalibrationFeature.State
        var alertOrchestrator: AlertOrchestratorFeature.State
        var navigation: NavigationFeature.State
        var rideSummary: RideSummaryFeature.State?   // Non-nil after ride ends

        // Derived dashboard display values
        var currentSpeedMPS: Double { speed.speedMPS ?? location.speedMPS }
        var currentHRBPM: Int? { heartRate.currentBPM }
        var currentCadenceRPM: Int? { cadence.cadenceRPM }
        var elapsedSeconds: TimeInterval = 0
        var distanceMeters: Double = 0
        var activeAlertLevel: AlertLevel { alertOrchestrator.currentAlertLevel }

        // Paused state
        var pausedAt: Date? = nil

        // Running HR zone durations. As built (#145): `hrSecondsTally`, recorded seconds per
        // bpm by S10's rule, sorted into zones when the Heart rate sheet reads it
        var hrZoneDurations: [Int: TimeInterval] = [:]
    }

    enum Action {
        case rideStarted
        case pauseTapped
        case resumeTapped
        case finishTapped
        case finishConfirmed
        case timerTick                             // 1 Hz
        case checkpointFired                       // Every 30s
        case rideEnded(RideSummary)

        // Sub-feature actions
        case radar(RadarFeature.Action)
        case heartRate(HeartRateFeature.Action)
        case speed(SpeedFeature.Action)
        case cadence(CadenceFeature.Action)
        case location(LocationFeature.Action)
        case trackRecorder(TrackPointRecorderFeature.Action)
        case wheelCalibration(WheelCalibrationFeature.Action)
        case alertOrchestrator(AlertOrchestratorFeature.Action)
        case navigation(NavigationFeature.Action)
        case rideSummary(RideSummaryFeature.Action)
    }
}
```

---

### 4.5 RadarFeature

Manages the BLE connection to the Varia radar and produces typed `AlertLevel` state.

```swift
@Reducer
struct RadarFeature {
    @ObservableState
    struct State: Equatable {
        var connectionState: BLEConnectionState = .disconnected // Drives sidebar visibility
        var isPaired: Bool = false                 // True if a radar was ever paired; 
        var currentAlertLevel: AlertLevel = .clear
        var vehicles: [RadarVehicle] = []
        var lastAlertLevelChangeAt: Date?          // For 3-second re-trigger guard
        var capability: RadarCapabilityPayload?    // Read on first connect
    }

    enum Action {
        case startListening
        case stopListening
        case connectionChanged(BLEConnectionEvent)
        case alertReceived(RadarAlertPayload)
        case capabilityRead(RadarCapabilityPayload)
        case reconnectionTimerFired
    }

    @Dependency(\.bluetooth) var bluetooth
    @Dependency(\.continuousClock) var clock

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .startListening:
                guard state.isPaired else { return .none }
                return .run { send in
                    for await event in bluetooth.connect(state.pairedRadarId) {
                        await send(.connectionChanged(event))
                    }
                }

            case .alertReceived(let payload):
                // Only update if payload level differs OR vehicles changed
                let previousLevel = state.currentAlertLevel
                state.currentAlertLevel = payload.alertLevel
                state.vehicles = payload.vehicles

                let now = Date()
                let minInterval: TimeInterval = 3.0
                let canRetrigger = state.lastAlertLevelChangeAt.map {
                    now.timeIntervalSince($0) >= minInterval
                } ?? true

                guard canRetrigger && payload.alertLevel != previousLevel else { return .none }
                state.lastAlertLevelChangeAt = now

                return .send(.alertOrchestrator(.radarAlertChanged(payload.alertLevel)))
                // (AlertOrchestratorFeature is the parent — action bubbles up via scope)

            // ... other cases
            }
        }
    }
}
```

---

### 4.6 HeartRateFeature

```swift
@Reducer
struct HeartRateFeature {
    @ObservableState
    struct State: Equatable {
        var connectionState: BLEConnectionState = .disconnected
        var currentBPM: Int? = nil
        var activeSource: SensorSource = .none
        var currentZone: Int? = nil               // Computed from BPM at read time; never persisted. BRG: I don't understand why this would be true? Explain. 
        @SharedReader(.riderProfile) var riderProfile  // HR overrides for Karvonen (DataModel.md §3.5)
    }

    enum Action {
        case startListening
        case bleConnected
        case bleMeasurementReceived(HRMeasurementPayload)
        case bleDisconnected
        case healthKitUpdateReceived(Int)          // bpm from Apple Watch stream
        case sourceChanged(SensorSource)
    }

    @Dependency(\.bluetooth) var bluetooth
    @Dependency(\.healthKit) var healthKit
}
```

---

### 4.7 SpeedFeature

Manages the BLE connection to the paired Speed-role peripheral and GPS fallback. See BLE.md §5.0 for role assignment at pairing.

```swift
@Reducer
struct SpeedFeature {
    @ObservableState
    struct State: Equatable {
        var connectionState: BLEConnectionState = .disconnected
        var speedMPS: Double? = nil
        var activeSpeedSource: SensorSource = .none  // .bleWheel or .gps
        var calculator: CSCSpeedCalculator
        var wheelCircumferenceMM: Int = 2096
        var pairedPeripheralId: UUID?
    }

    enum Action {
        case startListening
        case bleMeasurementReceived(CSCMeasurementPayload)
        case bleDisconnected
        case gpsSpeedReceived(Double)
        case wheelCircumferenceUpdated(Int)
        case sourceChanged(SensorSource)
    }

    @Dependency(\.bluetooth) var bluetooth
}
```

---

### 4.8 CadenceFeature

Manages the BLE connection to the paired Cadence-role peripheral. No fallback source — cadence shows "--" when disconnected. The peripheral UUID may match SpeedFeature’s when a combo device serves both roles; both features subscribe independently.

```swift
@Reducer
struct CadenceFeature {
    @ObservableState
    struct State: Equatable {
        var connectionState: BLEConnectionState = .disconnected
        var cadenceRPM: Int? = nil
        var calculator: CSCCadenceCalculator
        var pairedPeripheralId: UUID?
    }

    enum Action {
        case startListening
        case bleMeasurementReceived(CSCMeasurementPayload)
        case bleDisconnected
    }

    @Dependency(\.bluetooth) var bluetooth
}
```

---

### 4.9 AlertOrchestratorFeature

The most safety-critical reducer. Receives level changes from `RadarFeature` and dispatches haptic + audio effects with correct timing guarantees.

```swift
@Reducer
struct AlertOrchestratorFeature {
    @ObservableState
    struct State: Equatable {
        var currentAlertLevel: AlertLevel = .clear
        var previousAlertLevel: AlertLevel = .clear
        var silentModeOverrideEnabled: Bool = false  // Not a setting in MVP (UX.md §S12); AudioClient holds the flag
    }

    enum Action {
        case radarAlertChanged(AlertLevel)
        case hapticCompleted
        case audioCompleted
    }

    @Dependency(\.haptic) var haptic
    @Dependency(\.audioAlert) var audioAlert

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .radarAlertChanged(let level):
                let previous = state.currentAlertLevel
                state.previousAlertLevel = previous
                state.currentAlertLevel = level

                return .run(priority: .high) { [level, previous, silentOverride = state.silentModeOverrideEnabled] send in
                    // Haptic first — tightest latency requirement
                    switch level {
                    case .clear:
                        break // No haptic on clear
                    case .advisory:
                        await haptic.fireL1Advisory()
                    case .caution:
                        await haptic.fireL2Warning()
                    case .danger:
                        await haptic.fireL3Danger()
                    }

                    // Audio
                    switch level {
                    case .clear where previous >= .caution:
                        await audioAlert.playAllClear()
                    case .caution:
                        await audioAlert.playWarning()
                    case .danger:
                        await audioAlert.playDanger()   // Respects silent mode flag internally
                    default:
                        break
                    }

                    await send(.hapticCompleted)
                }

            default:
                return .none
            }
        }
    }
}
```

> **Note:** `priority: .high` (`.userInteractive` is deprecated as of the Xcode 27 SDK) ensures the haptic/audio Effect is not starved by lower-priority Effects. The L3 danger haptic and audio tone are guaranteed to fire within the 200ms budget.

---

### 4.10 TrackPointRecorderFeature

Records one `TrackPointDTO` per second and batches to persistence on the 30-second checkpoint.

```swift
@Reducer
struct TrackPointRecorderFeature {
    @ObservableState
    struct State: Equatable {
        var rideId: UUID
        var isRecording: Bool = false
        var pendingPoints: [TrackPointDTO] = []
        var totalPointsRecorded: Int = 0
    }

    enum Action {
        case startRecording
        case pauseRecording
        case resumeRecording
        case timerTick                             // Fires from parent 1 Hz timer
        case checkpointFired                       // Fires from parent 30s timer
        case flushCompleted(Result<Void, Error>)
        case stopRecording                         // On ride end; flushes remaining points
    }

    @Dependency(\.persistence) var persistence
    @Dependency(\.continuousClock) var clock

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .timerTick:
                guard state.isRecording else { return .none }
                // Parent injects current sensor values via state composition — no direct dependency
                // TrackPointDTO is built in parent (ActiveRideFeature) and sent as part of action
                return .none

            case .checkpointFired:
                let points = state.pendingPoints
                state.pendingPoints = []
                return .run { send in
                    do {
                        try await persistence.flushTrackPoints(points)
                        await send(.flushCompleted(.success(())))
                    } catch {
                        await send(.flushCompleted(.failure(error)))
                    }
                }

            default:
                return .none
            }
        }
    }
}
```

---

### 4.11 WheelCalibrationFeature

Compares BLE-derived distance against GPS-derived distance over 1,500 m windows and adjusts `wheelCircumferenceMM`. Thresholds and their rationale are in PRD §8.9 / §8.9.2; the constants live on `WheelCalibration`.

```swift
@Reducer
struct WheelCalibrationFeature {
    @ObservableState
    struct State: Equatable {
        var isActive: Bool = true
        var bleDistanceAccumulator: Double = 0     // meters since window start
        var gpsDistanceAccumulator: Double = 0     // meters since window start
        var windowThresholdMeters: Double = 1500
        var discrepancyThresholdPct: Double = 0.02
        var currentCircumferenceMM: Int = 2096
        var lastCalibrationAt: Date? = nil
    }

    enum Action {
        case locationUpdateReceived(LocationUpdate)
        case speedCadenceUpdateReceived(CSCMeasurementPayload)
        case calibrationTriggered(newCircumferenceMM: Int)
        case calibrationSuspended                  // L2/L3 alert or poor GPS
        case calibrationResumed
    }

    @Dependency(\.persistence) var persistence
}
```

---

### 4.12 VehiclePassDetectionFeature

Embedded within `RadarFeature`. Monitors vehicle tracking history to detect genuine overtakes.

```swift
// Detection runs inline within RadarFeature.reduce on each .alertReceived action.
// Produces VehiclePassEvent values that bubble up to TrackPointRecorderFeature.

struct VehicleTrackingRecord: Equatable {
    let vehicleIndex: Int
    var firstSeenAt: Date
    var lastDistance: Double              // meters
    var closingSpeedHistory: [Double]     // km/h values; used to confirm approaching direction
    var minimumDistance: Double
}

// Pass detection criteria:
// 1. Vehicle tracked for >= 2 continuous seconds
// 2. closingSpeedHistory majority positive (approaching)
// 3. Vehicle disappears from radar data (no longer in payload)
// → Emit VehiclePassEvent at current rider position
```

---


### 4.13 RideSummaryFeature

Presented after ride end. Displays post-ride metrics and drives service sync.

```swift
@Reducer
struct RideSummaryFeature {
    @ObservableState
    struct State: Equatable {
        var ride: Ride
        var isShowingSyncSheet: Bool = false
        var syncSheet: RideSyncSheetFeature.State?

        // HKWorkout write fires when S10 closes, only with Sync To's Apple Health on; status tracked here
        var healthKitWorkoutStatus: WorkoutWriteStatus = .pending
    }

    enum Action {
        case onAppear                              // Triggers HKWorkout write if not yet done
        case healthKitWorkoutWriteCompleted(Result<Void, Error>)
        case syncButtonTapped                      // Opens service selection sheet
        case syncSheet(RideSyncSheetFeature.Action)
        case doneTapped                            // Dismisses summary; returns to Rides tab
    }

    @Dependency(\.healthKit) var healthKit
}

enum WorkoutWriteStatus: Equatable {
    case pending, writing, written, failed(String)
}

// MARK: - RideSyncSheetFeature

/// Sheet presented when rider taps Sync. Shows connected services as toggleable options.
/// Phase 2 — not implemented in MVP; architecture defined here for planning.
@Reducer
struct RideSyncSheetFeature {
    @ObservableState
    struct State: Equatable {
        var rideId: UUID
        var availableServices: [ExternalService] = []
        var selectedServices: Set<ExternalService> = []
        var syncStatuses: [ExternalService: ServiceSyncStatus] = [:]
        var isSyncing: Bool = false
    }

    enum Action {
        case onAppear
        case servicesLoaded([ExternalService])
        case serviceToggled(ExternalService)
        case syncConfirmed                         // Upload to all selected services
        case serviceUploadCompleted(ExternalService, Result<String, Error>)
        case dismissed
    }

    @Dependency(\.sync) var sync
}

enum ServiceSyncStatus: Equatable {
    case idle, uploading, synced(remoteId: String), failed(String)
}
```

**HKWorkout write flow:**
```
RideSummaryFeature.reduce(.finishTapped / .dismissed)
    │
    │ guard syncDestinations[.appleHealth] == true, healthKitWorkoutStatus == .pending
    ▼
HealthKitClient.recordWorkout(HKWorkoutPayload(
    startDate: ride.startedAt,
    endDate:   ride.endedAt,
    distanceMeters: ride.distanceMeters,
    activeEnergyBurnedKcal: nil          // Phase 2 via HKQuantitySample
))
    │
    ▼
.healthKitWorkoutWriteCompleted(.success)  // Ride appears in iOS Fitness app
```

**Service sync flow (Phase 2):**
```
RideSummaryFeature.reduce(.syncButtonTapped)
    │ → present RideSyncSheetFeature
    │
SyncClient.availableServices()
    │ → [.strava, .rideWithGPS]  (enabled services with valid tokens)
    │
Rider selects services → taps "Sync"
    │
For each selected service:
    SyncClient.uploadRide(rideId, service)
    → POST GPX to service API
    → Returns remoteActivityId on success
    → Updates Ride.syncRecords in SwiftData
```

---

### 4.14 NavigationFeature

Scoped into `ActiveRideFeature`. Follows the route a ride was started on: places the rider on its
polyline, tracks how far along it they are, announces each turn at the rider's lead distance, and
says when they have left it. Nothing reroutes — PRD §15 keeps that out of scope, so off-route is a
banner and no more. Built in M8 (#197); W9 (#200) and the pipeline tests (#201) read from it.

**How the parent drives it.**
- `.task` sends `.navigation(.loadRoute(id))` for any ride that has a `routeId`, fresh or resumed.
- `.locationUpdated` forwards a fix only while `navigation.isFollowingRoute`, so a free ride — and a
  ride with the S05.1 Turn-by-Turn toggle off, whose route is only drawn on the map — never reaches
  the matching at all.
- `progressMeters` rides out to the `Ride` on every `updateRideSummary` and `finalizeRide`, and comes
  back through `fetchResumableRide` (DataModel.md §3.1, `Ride.routeProgressMeters`).
- `.delegate(.turnAnnounced)` goes to `AlertOrchestratorFeature`, which plays the turn tone unless
  radar has the speaker (#198).
- `isTurnAlertActive` suspends wheel calibration (PRD §8.9).

```swift
@Reducer
struct NavigationFeature {
    @ObservableState
    struct State: Equatable {
        @SharedReader(.appPreferences) var preferences   // lead distance; turn-by-turn on/off

        // The route, nil for a free ride and for a routeId whose route has been deleted
        var activeRoute: NavigationRoute?        // polyline + cumulative distances + maneuvers

        // Where the rider is on it
        var progressMeters: Double?              // checkpointed to Ride; the floor a resume searches from
        var snappedIndex: Int?                   // this session's last match; nil until a fix confirms one
        var lapCoveredMeters = 0.0               // route metres actually ridden this lap (loops)

        // Turns
        var nextManeuverIndex = 0
        var announcedManeuverIndex: Int?         // fired, not yet passed
        var turnInstruction: Maneuver?           // the centred overlay, nil when hidden

        // Off route and route end
        var offRouteStreak = 0
        var isOffRoute = false
        var isRouteComplete = false

        var isFollowingRoute: Bool               // a route exists AND turn-by-turn is on
        var nextManeuver: Maneuver?
        var distanceToNextTurnMeters: Double?    // what W9 (#200) reads; nil off-route or complete
        var isTurnAlertActive: Bool              // suspends wheel calibration (PRD §8.9)
    }

    enum Action: Equatable {
        case loadRoute(UUID)                     // sent by ActiveRideFeature.task
        case routeLoaded(NavigationRoute?)
        case locationUpdated(LocationUpdate)
        case instructionDismissed
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable { case turnAnnounced(Maneuver.Direction) }
    }

    @Dependency(\.persistenceClient) var persistenceClient
    @Dependency(\.continuousClock) var clock
}
```

`.loadRoute` does its work in an effect, not the reducer: decoding the polyline and deriving its
turns (`TurnDerivation`) walks every point, and a route exported from a recorded ride can carry tens
of thousands. Maneuvers are derived at load and never persisted, so a later fix to the derivation
cannot leave old routes on stale output.

**Snapping.** The nearest point anywhere on the polyline is the wrong answer for any route that
passes the same place twice — on an out-and-back a rider still riding out is as near the way back.
Four rules keep the match on the leg actually being ridden. The two searches are
`RouteGeometry.candidates` (windowed) and `RouteGeometry.passes` (first pass); the constants and
the continuity scoring live on `NavigationFeature`:

| Rule | Constant | What it buys |
|---|---|---|
| A window around the last match | `backWindowMeters` 100, `forwardWindowMeters` 500 | A match cannot jump legs; a run of dropped fixes still cannot outpace it |
| Direction | `courseSpeedFloorMPS` 2.0 | Once the GPS course means anything, a segment running against it is not a candidate — which tells the way back from a rider who turned round short of the turnaround |
| Continuity | `continuityWeight` 0.1 | The match that moves the rider least far from where they were expected wins, not simply the nearest. A stopped rider has no course, and a metre of scatter would otherwise move them past turns they would never be told about |
| *First* pass, not nearest | — | Wherever there is no match to window around — ride start, off-route, a relaunch mid-ride — searched from just behind `progressMeters` |

**Loops.** A loop's end is also its start, so arriving there is ambiguous. A loop counts as finished
only once `lapCoveredMeters` reaches half of it; short of that the match carries on round from the
start, as the road does. That counter accumulates only the step between consecutive *on-route*
fixes, so a rejoin credits nothing — measuring the rider's span along the route instead is wrong in
both directions, letting a rider who bailed 200 m in and came back to the start be told they had
finished, while a detour late in a loop left it uncompletable. `loopClosureMeters` (50) is how close
a route's two ends have to be to count as a loop.

**Turn timing.** PRD §8.6 allows ±10 m of the lead distance, but at 40 km/h a rider covers 11.1 m
between fixes, so announcing at the first fix inside the lead distance can be 11 m late. A turn is
announced instead when what remains beyond the lead distance is at most half the ground the next fix
is expected to cover — `distance − lead ≤ speed · expectedFixInterval / 2`. That halves the worst
case to ±5.6 m at 40 km/h.

**Off route and arrival.** Raised after `offRouteConsecutiveFixes` (5) fixes beyond `offRouteMeters`
(50) — at CoreLocation's 1 Hz the fifth lands inside PRD §8.6's five seconds. Cleared by
`rejoinConsecutiveFixes` (2) fixes back within the same 50 m: the flap a rider running 40–50 m out
would cause is handled the same way leaving the route is, rather than with a tighter radius, which
used to cost them 20 m of riding still being told they were off a route they were on. Within
`arrivalMeters` (30) of the end the route is done: no more turns, and riding on past the finish is
not being off-route. A turn already within `minimumAnnounceDistanceMeters` (10) is not announced at
all — reachable by rejoining right at a junction, where the tone would land after the decision.

---

### 4.15 Strava (Phase 2)

PRD §8.12. Three clients and four features; every network call goes through `StravaClient`, so reducers test
against its mock and the transport tests against recorded responses.

```swift
@DependencyClient
struct KeychainClient {
    var read:   @Sendable (_ account: String) throws -> Data?
    var write:  @Sendable (_ account: String, _ data: Data) throws -> Void
    var delete: @Sendable (_ account: String) throws -> Void
}

/// ASWebAuthenticationSession or the Strava app, then the token service. Owns refresh: an actor inside the live
/// value (`StravaSession`) serializes it, so concurrent requests refresh once and the rotated refresh token is
/// written first. Owns Strava's `ConnectedService` record in the AppPreferences document: connect saves it, a
/// refused refresh or a missing Keychain item flags `isDisconnected`, disconnect removes it (#626). A refused refresh
/// also deletes the Strava caches, as disconnect does (PRD §8.12): no feature sees the refusal, so the client owns it.
@DependencyClient
struct StravaAuthClient {
    var connect:        @Sendable () async throws -> ConnectedService    // OAuth + exchange + Keychain write + record
    var accessToken:    @Sendable () async throws -> String              // refreshes under 5 min left
    var refreshAccessToken: @Sendable (_ rejected: String) async throws -> String  // after a 401; skipped when already replaced (#627)
    var disconnect:     @Sendable () async throws -> Void                // Keychain + record + caches, then revoke
    var handleRedirect: @MainActor @Sendable (URL) -> Bool               // the Strava app's redirect, from AppFeature.urlOpened
}

@DependencyClient
struct StravaClient {
    var upload:          @Sendable (StravaUpload) async throws -> StravaUploadID
    var uploadStatus:    @Sendable (StravaUploadID) async throws -> StravaUploadStatus   // .processing / .ready(activityID) / .duplicate(activityID) / .failed(reason)
    var segmentEfforts:  @Sendable (_ activityID: String) async throws -> [StravaSegmentEffort]
    var routes:          @Sendable (_ page: Int) async throws -> [StravaRouteSummary]
    var route:           @Sendable (_ routeID: String) async throws -> StravaRouteDetail  // segments; kept, not called (#637)
    var routeGPX:        @Sendable (_ routeID: String) async throws -> Data
    var athlete:         @Sendable () async throws -> StravaAthlete                      // name, photo URL; S12.1, each appearance
    var bikes:           @Sendable () async throws -> [StravaGear]                       // later, Multi-bike; same GET /athlete
    var setGear:         @Sendable (_ activityID: String, _ gearID: String) async throws -> Void
}
```

`KeychainClient` items are generic passwords under service `xyz.acmeapps.ride.oauth`, one account per service
(`strava`). The Strava app's redirect reaches the app through the `cyclometer` scheme (`CFBundleURLTypes`):
`AppView.onOpenURL` sends `AppFeature.urlOpened`, which imports a file as before and hands any other URL to
`handleRedirect`. The web session catches its redirect itself.

`StravaClient`'s live value (`StravaAPI`, #627) adds the bearer token from `StravaAuthClient`, and retries once
after a 401 with `refreshAccessToken(rejected:)`. A token that is still good by the clock can be revoked, and
concurrent 401s refresh once. It reads the `X-RateLimit-*` / `X-ReadRateLimit-*` headers (`StravaRateLimit`) and
throws `StravaError.rateLimited(until:)` on a 429. `until` is the next midnight UTC when a daily count is spent,
otherwise the next quarter hour; an upload counts only against the overall limit, so a spent read count doesn't hold it. Its other errors are `.unauthorized` (a 401 after the refresh), `.http(status:)`
and `.invalidResponse`; a missing or disconnected account throws `StravaAuthError`. Uploads are multipart, the GPX
gzipped (`gpx.gz`, `sport_type=Ride`). `StravaWire` decodes Strava's JSON into the cached models
(DataModel.md §3.8.1). It reads no best time: Strava's activity and route answers don't carry one, whatever its
reference shows (checked with `StravaLiveTests`). Route `type` is passed through: its values aren't
documented, and the browser (#634) picks the rides. Reducers use `StravaClient.mock(...)`.

| Feature | Scope | Does |
|---|---|---|
| `AccountsFeature` | `SettingsFeature` | S12 Accounts rows and S12.1: connect, disconnect, granted scopes. S12.1's `.task` fetches `athlete` each time it appears, for the name and photo, and stores neither: the photo loads through a session with no URL cache, so it never reaches the disk; a disconnected account shows as not connected. **As built (#629):** S12.1 alone, pushed on `SettingsFeature.path` (`NavigationLink(state:)`); the Strava row reads `SettingsFeature.State.stravaNeedsReconnect`. Connect and Reconnect are one `stravaAuth.connect()`. Disconnect is confirmed in S12.1, which sends `delegate(.disconnectConfirmed)`; `SettingsFeature` pops it and runs `stravaAuth.disconnect()`, since the client removes the record before its revoke answers and the revoke must outlive the screen. `StravaSession` runs a disconnect in an unstructured task that a connect's code exchange waits out (Strava's deauthorize revokes every token for the athlete, so an exchange that beat it would be killed), and finishes a connect in one once Strava has redirected back, so leaving S12.1 doesn't lose a finished sign-in. The photo loads through `AsyncImage` with `asyncImageURLSession` on an ephemeral session with no `urlCache` |
| `SyncQueueFeature` | `AppFeature` (app-lifetime) | Runs uploads after S10 closes: upload, poll `uploadStatus` (1, 2, 4, then 8 s, for 2 min), write `RideSyncRecord`. On launch resumes records left `pending` or `processing`. **As built (#630):** `Features/Rides/SyncQueueFeature.swift`. `enqueue(rideId)` is the rider's choice, and reads the ride's record first (`PersistenceClient.fetchSyncRecord`): a ride already `synced` is skipped, because Strava doesn't catch the same GPX sent twice and would make a second activity; an owed record carries on from where it stands; a `failed` one starts over; `resume` reads `PersistenceClient.fetchRidesOwedSync` and runs on each `.active` scene phase (the launch's first included; not from `.task`, whose `finish()` would cancel an upload) and when `AppPreferences.canUploadToStrava` turns true (connect, or a Reconnect granting `activity:write`). Nothing calls Strava without a connected account holding `activity:write`, or before a 429's reset (`heldUntil`): the record waits `pending` with its reason. Each step is written before the next: `uploading`, then `processing` with `RideSyncRecord.remoteUploadId`, then `synced` (`.ready` or `.duplicate`, with the activity id) or `failed` (Strava's reason). Two minutes still processing keeps `processing` and its upload id, polled again at the next `resume`; a record found `uploading` uploads again, which can make a second activity if the earlier POST landed but its reply was lost (#663). `SyncFailure` sorts errors: offline, 5xx, 429, a missing account or scope wait (record keeps its place, reason in `errorMessage`); a poll answered 404 drops the upload id to send again; other 4xx and an unreadable answer fail, for Retry (#632). `Ride.isSyncOwed` mirrors "any record pending, uploading or processing" so the resume can use a predicate; `saveSyncRecord` writes both together. A DEBUG-only "Upload Latest Ride" long-press menu on S12.1's athlete card enqueues the newest ride until #631's Sync To replaces it |
| `RideSummaryFeature` | — | Gains `syncDestinations: [SyncDestination: Bool]` for S10's Sync To; `.task` loads the defaults; `.finishTapped` and dismissal save them and send the chosen services to `SyncQueueFeature`. Health is a destination like the services: on, the close sets `isHealthWorkoutOwed` and writes the workout; off, it clears the flag and nothing is written. No write at save. `RideSyncSheetFeature` is retired |
| `StravaRoutesFeature` | S19 and S05.2 | Paged list of the rider's Strava routes, refetched when shown and more than a day old. A cached route is deleted as gone from Strava only when its own fetch answers 404, or when the list has been read to its last page without it: the list is paged, so a route missing from a partial read stays. Opening or choosing one fetches `routeGPX`, parses and analyses through `GPXRouteImporter` without the surface lookup or narrative, and writes a cached Strava route row under its derived id (DataModel.md §3.8.1). Nothing is imported into the library |

Strava data is a cache of at most seven days (PRD §8.12, DataModel.md §3.8.1). `AppFeature` purges what is older,
at launch and when the scene becomes active, through `PersistenceClient`: cached Strava routes are deleted and ride
efforts cleared. Disconnecting, or a refused refresh, deletes all of it in the same way.

S15's `RideDetailFeature` gains a `segments` child: load the cache, fetch when it is missing or more than a day old
and the device is online (also when empty and the upload is under ten minutes old), save it. It presents S15.1
(UX.md §S15.1). S20 has no segments: dropped from Phase 2 (#637). `RouteDetailFeature` still refetches a Strava
route it shows that is more than a day old, when the device is online (PRD §8.12), replacing the row in place, and
deletes it when Strava answers 404: S20 is reached from S15's Route section too, not only from the Strava tab. `StravaClient.route` and `StravaRouteSegment` stay, built and
tested in #627, for a later feature that shows a route's segments, but nothing calls them: no screen shows a route's
segments, and each call would spend the app's shared read limit on data that is cached and then thrown away.

---

## 5. Data Flow Diagram — L3 Danger Alert

```
Varia RTL515 (BLE hardware)
    │
    │ BLE characteristic notification
    ▼
BluetoothClient.notifications()
    │
    │ AsyncStream<Data>
    ▼
RadarFeature.reduce(.alertReceived(payload))
    │
    │ Parses payload → AlertLevel.danger
    │ Guards 3s re-trigger window
    ▼
AlertOrchestratorFeature.reduce(.radarAlertChanged(.danger))
    │
    │ .run(priority: .high)
    ├──▶ HapticClient.fireL3Danger()        ← < 200ms budget
    │        (Core Haptics: 3× 0.14s burst)
    └──▶ AudioAlertClient.playDanger()      ← < 200ms budget
             (AVAudioSession .playback)
             (Overrides Silent Mode if user opt-in)
    │
    ▼
ActiveRideFeature.State.activeAlertLevel = .danger
    │
    │ @Observable state change
    ▼
DashboardView re-renders W7 (Radar widget)
    • Strip background: brRatingBadBg
    • Vehicle icon: brRatingBad
    • Smooth 0.3s color transition
```

---

## 6. Data Flow Diagram — 1 Hz Track Point Recording

```
ContinuousClock (1 Hz timer in ActiveRideFeature)
    │
    │ Action.timerTick
    ▼
ActiveRideFeature.reduce(.timerTick)
    │
    │ Reads current state from:
    │   speed.speedMPS
    │   cadence.cadenceRPM
    │   heartRate.currentBPM
    │   location.coordinate, altitude
    │
    ▼
Builds TrackPointDTO
    │
    ▼
TrackPointRecorderFeature.reduce(.timerTick)
    │ Appends to pendingPoints
    │
    ├── Every 1s: State.elapsedSeconds += 1
    ├── Every 1s: State.distanceMeters += speed × 1.0
    ├── Every 30s: Action.checkpointFired
    │               → PersistenceClient.flushTrackPoints(pendingPoints)
    │               → NSBatchInsertRequest (CoreData background context)
    └── Ride end: Action.stopRecording
                  → Final flush
                  → GPXExporter.generate(rideId:)
                  → HealthKitClient.recordWorkout(payload)
                  → RideSummaryFeature presented to rider
```

---

## 7. Navigation — ActiveRideFeature Presentation

The active ride dashboard is presented as a `fullScreenCover` from the root `TabView`, matching the prototype pattern.

```swift
// In TabView body (RidesTabFeature)
.fullScreenCover(
    item: $store.scope(state: \.activeRide, action: \.activeRide)
) { store in
    ActiveRideDashboardView(store: store)
}

// Dismiss (swipe down) → activeRide = nil
// Minimized state → accessory strip shown above TabBar
// Re-open from accessory strip → fullScreenCover re-presented
```

This exactly mirrors `ContentView.fullScreenCover(item: $dashboardRide)` from the prototype.

---

## 8. Project File Structure

As implemented, under `Cyclometer/Cyclometer/`. Features are grouped by area; `ActiveRide/` is
split one level further by capability, keeping each sub-feature beside its widget (#339). The
project uses `PBXFileSystemSynchronizedRootGroup`, so new files need no `.xcodeproj` edits.

```
Cyclometer/
├── App/                                   // AppFeature, AppView, CyclometerApp (@main),
│                                          // Logger+Cyclometer, DocumentFolders, AutoDim bridge,
│                                          // AppLinks (acmeapps.xyz URLs, #598)
├── Features/
│   ├── ActiveRide/
│   │   ├── ActiveRideFeature.swift        // parent reducer for the ride
│   │   ├── RideDashboardView.swift        // S05 dashboard
│   │   ├── ActiveRideAccessoryView.swift  // S05.3 accessory
│   │   ├── Dashboard/                     // DashboardPageView, DashboardGridLayout, DashboardWidget, DashboardChrome (grabber, banner, controls — #352), DashboardEditChrome (S07), AddWidgetSheet (S08)
│   │   │                                  // (protocol + catalog) — #139; each widget folder has its adapter
│   │   ├── Speed/                         // SpeedFeature, SpeedWidgetView (W1), AverageSpeed (W2),
│   │   │                                  // Duration (W3), Distance (W6), PaceWidgetView (W11),
│   │   │                                  // RideMetricsSheet + RideMetricsCharts (#144),
│   │   │                                  // MaxSpeedGate (#540)
│   │   ├── HeartRate/                     // HeartRateWidgetView (W4, W12), HeartRateSheet — HR state lives
│   │   │                                  // on ActiveRideFeature (§3)
│   │   ├── Cadence/                       // CadenceFeature, CadenceWidgetView (W5)
│   │   ├── Elevation/                     // ElevationWidgetView (W14–W18), ElevationSheet (#387),
│   │   │                                  // ClimbWidgetView (W22, #463) — altitude and ElevationTracker
│   │   │                                  // live on ActiveRideFeature; the route's climbs in Models/RouteClimb
│   │   ├── Map/                           // MapWidgetView (W8), ActiveRideMapView,
│   │   │                                  // LiveMapCamera, MapSheetButtons
│   │   ├── Navigation/                    // NavigationFeature, DirectionsWidgetView (W9),
│   │   │                                  // TurnInstructionOverlay
│   │   ├── Sunset/                        // SunsetWidgetView (W21, #462) — the NOAA sunset lives in
│   │   │                                  // Models/Sunset
│   │   ├── Weather/                       // RideWeatherFeature, WeatherWidgetView (W10, #150),
│   │   │                                  // WeatherSheet, WeatherMap + ActiveRideFeature+RouteWind (#561),
│   │   │                                  // ActiveRideFeature+RainAhead (#152)
│   │   │                                  // — RelativeWind, RainOutlook, RainAhead, WindSampling in Models/
│   │   ├── Calories/                      // CaloriesWidgetView (W23, #465), CaloriesSheet — the series
│   │   │                                  // lives on ActiveRideFeature; rebuilds in Models/CalorieSeries
│   │   ├── LiveActivity/                  // RideActivityAttributes, RideLockScreenView (PRD §8.10) — shared with the extension;
│   │   │                                  // LiveActivityFeature (app only)
│   │   ├── Recording/                     // TrackPointRecorderFeature, GPSFixFilter
│   │   ├── Alerts/                        // AlertOrchestratorFeature, VehiclePassDetector,
│   │   │                                  // RideBanner
│   │   ├── SensorHealth/                  // SensorHealthFeature (#391), SensorsButton + SensorsSheet (#464, #466)
│   │   └── Calibration/                   // WheelCalibrationFeature, WheelCalibration, CalibrationWindowProbe
│   ├── Rides/                             // RidesFeature/View, RideDetail*, RideSummary*, SyncQueueFeature (#630),
│   │                                      // StartSheet*, RoutePicker*, RideWeatherSummary +
│   │                                      // RideWindExposure (S15 Weather, #151)
│   ├── Routes/                            // RoutesFeature/View, RouteDetail*, RouteFilter,
│   │                                      // RouteLibrary, RoutesMapCamera, RouteWindFeature
│   │                                      // (#561, also scoped by RideWeatherFeature)
│   ├── Settings/                          // SettingsFeature/View, DeviceManagement*, Accounts* (S12.1)
│   └── Onboarding/                        // Onboarding*, Welcome*, SensorPairing*
│
├── Clients/                               // one folder per dependency client
│   ├── Altimeter/  Audio/  BLE/  Geocoding/  Haptics/  HealthKit/  Keychain/  Location/
│   ├── LiveActivity/  MapSnapshot/  Overpass/  Permissions/  Screen/  Weather/
│   ├── Strava/                            // StravaAuthClient, StravaSession (actor), StravaAuthPresenter,
│   │                                      // StravaConfig (#626); StravaClient(+Mock), StravaAPI, StravaWire,
│   │                                      // StravaModels, StravaRateLimit, StravaGzip (#627)
│   ├── Persistence/                       // PersistenceClient, Ride/RoutePersistenceActor,
│   │                                      // SwiftDataStack, CoreDataStack, RideDataBuffer,
│   │                                      // TrackPointMO, CyclometerTimeSeries.xcdatamodeld
│   └── RideEndIntentClient.swift
│
├── Models/                                // value types and SwiftData @Models (Ride, Route, …)
├── Export/                                // GPXExporter, GPXParsing, GPXRouteImporter
├── Intents/                               // App Intents (PRD §8.11): RideEntity, RouteEntity,
│                                          // the intents, CyclometerShortcuts, IntentCommandCenter
├── UI/
│   ├── DesignSystem/                      // Color+Cyclometer, AppFonts, Typography,
│   │                                      // Spacing, Opacity, WidgetSize
│   └── Components/                        // HeroNumber, WidgetLabel, SensorListRow,
│                                          // RouteMap, RadarColumn, HRZoneBadge, WidgetDetail, WidgetSymbol, DonutChart,
│                                          // OpenRingProgressView (S05.3 ring), …
├── PreviewContent/
└── Resources/Fonts/                       // D-DIN
```

The `CyclometerWidgets/` folder beside it is the widget extension (target `CyclometerWidgetsExtension`,
#306), holding the ride's Live Activity: `CyclometerWidgetsBundle` and `RideLiveActivity`. It has no
copies of app code. Instead it compiles these app files through target membership, recorded as an
exception set on the `Cyclometer` folder in `project.pbxproj`: `LiveActivity/RideActivityAttributes`,
`LiveActivity/RideLockScreenView` (#309), `Models/UnitSystem`, `HeroNumber`, `OpenRingProgressView`,
`DesignSystem/Spacing`, `DesignSystem/AppFonts`, `DesignSystem/Opacity`,
`Assets.xcassets` and the D-DIN font. Keep that set free of app-only types (TCA, features, clients):
the extension build fails on the first one, which is how `UnitSystem`'s pace helpers came to live in
`Speed/UnitSystem+Pace.swift`.

Tests live in `Cyclometer/CyclometerTests/`, mirroring the top level only (`App/`, `Clients/`,
`DesignSystem/`, `Export/`, `Features/`, `Models/`); within each folder they are flat, and
snapshot references sit in that folder's `__Snapshots__/`.

---

## 9. Prototype Component Reuse

The following components from `Test-ToolbarAndAccessoryView` are production-ready and should be carried forward with minimal changes:

| Prototype Component | Target File | Notes |
|---|---|---|
| `HeroNumber` | `DesignSystem/HeroNumber.swift` | Make non-private; add TCA binding support |
| `DashboardSpeedCard` | `DesignSystem/Components/DashboardSpeedCard.swift` | Strip mock data; wire to TCA state |
| `DashboardMetricCard` | `DesignSystem/Components/DashboardMetricCard.swift` | As above |
| `OpenRingProgressView` | `DesignSystem/Components/OpenRingProgressView.swift` | Production-ready as-is |
| `SensorListRowView` | `UI/Components/SensorListRow/SensorListRowView.swift` | **Shared** (closes #11). The row skeleton behind both sensor lists: tinted icon tile, title over optional subtitle, trailing control. The two callers model different things — `SensorStatusRow` (private to `StartSheetView`) a fixed *category* (Radar / HR / Speed / Cadence), `DeviceRow` (private to `DeviceManagementView`) a *device* that appears and disappears while scanning — so each keeps its own thin wrapper and passes the trailing control in as a view. `SensorRowButton`, in the same file, is the shared capsule button ("Pair" / "Unpair" / "Tap to Pair") |
| `AppFonts` | `DesignSystem/AppFonts.swift` | Production-ready |
| `RouteStub` data structures | **Done (M8).** Replaced by the `Route` SwiftData model | DataModel.md §3.10. `RouteSummary` / `RouteDetail` / `RouteReference` are the `Sendable` boundary values that cross `PersistenceClient` |
| `CSCMeasurementPayload` layout | Formalize in `SpeedFeature` + `CadenceFeature` | Prototype has `DemoRideData` shape to reference |

Navigation structure from prototype is **directly adopted**:
- `TabView` with 3 tabs (Rides, Routes, Settings) — matches prototype exactly
- `tabViewBottomAccessory` for active ride accessory — matches prototype exactly
- `fullScreenCover(item:)` for dashboard — matches prototype exactly
- `tabBarMinimizeBehavior(.onScrollDown)` — keep from prototype
- `fontDesign(.rounded)` on TabView — keep from prototype

**Issues**

- [x] **Priority 1** Speed and Cadence are now separate features (SpeedFeature, CadenceFeature). Role assigned at pairing time. See BLE.md §5.0.

  

---

## 10. Test Strategy

### TCA TestStore Pattern

Every feature is tested without hardware via `withDependencies`:

```swift
func testL3AlertFiresHapticAndAudio() async {
    let hapticFired = ActorIsolated(false)
    let audioFired = ActorIsolated(false)

    let store = TestStore(initialState: ActiveRideFeature.State(rideId: UUID())) {
        ActiveRideFeature()
    } withDependencies: {
        $0.bluetooth = .mock(scenario: .singleVehicleApproach)
        $0.haptic.fireL3Danger = { await hapticFired.setValue(true) }
        $0.audioAlert.playDanger = { await audioFired.setValue(true) }
    }

    await store.send(.rideStarted)
    // Advance through mock BLE scenario to L3 event
    await store.receive(.alertOrchestrator(.radarAlertChanged(.danger)))
    await store.receive(.alertOrchestrator(.hapticCompleted))

    let didFire = await hapticFired.value
    XCTAssertTrue(didFire, "L3 haptic must fire on danger alert")
}
```

### Test Coverage Targets

| Feature | Key Test Cases |
|---|---|
| `RadarFeature` | Payload parsing; 3s re-trigger guard; disconnection handling; sidebar absent when unpaired |
| `AlertOrchestratorFeature` | L1/L2/L3 escalation; All Clear only after L2+; Silent Mode override flag |
| `HeartRateFeature` | BLE → Apple Watch fallback transition; zone calculation at all 5 boundaries |
| `SpeedFeature` | BLE, GPS fallback, CSC wheel calc, source badge; shared-peripheral scenarios |
| `CadenceFeature` | BLE, CSC crank calc; "--" when no source; shared-peripheral with SpeedFeature |
| `TrackPointRecorderFeature` | 30s checkpoint flush; ride end flush; paused intervals excluded |
| `WheelCalibrationFeature` | 2% trigger over two consecutive windows; correction averaged across the confirming windows; ±10% cap; out-of-range rejection; GPS accuracy gating; calibration suspension during L3 |
| `AlertOrchestratorFeature` | Effect dispatched at `.high` priority; < 200ms mock latency |
| `GPXExporter` | Schema validation; absent fields (not zero) for missing sensors; vehicle pass waypoints |
| `VehiclePassDetection` | Overtake vs. turn-off discrimination; 2s minimum tracking |
| Full ride state machine | `idle → active → paused → active → ended`; crash recovery from checkpoint |
| `RideSummaryFeature` | HKWorkout write on appear; failure handled gracefully; sync sheet presented on tap |
| `NavigationFeature` | The ±10 m turn sweep across every fix phase; the rider's own lead distance; multi-turn order and apex; out-and-back followed both ways though the other leg is nearer; a turnaround short of the turnaround; loops (joined near the end, left and re-entered, ridden whole, stood still on); off-route hysteresis at 50/30 m and the five-fix streak; rejoin re-announcing a dropped turn; route end; no route; turn-by-turn off; resume from a checkpointed `progressMeters` |
| `NavigationPipelineTests` | End to end over a real `.gpx` on disk and a live store: each turn's tone within ±10 m at 20/30/40 km/h; Off route raised within 5 s and cleared on rejoin; a route never joined; a ride with no route through a checkpoint and a relaunch; a deleted route leaving its rides' `routeName`; a ride killed mid-route relaunching still navigating |
| `RoutesFeature` / `RouteDetailFeature` | Import, list, map-as-filter, filter sheet, swipe-to-use (S19 → S05.1); S20 detail, elevation section hidden on nil gain, "Use This Route" |
| `RideSyncSheetFeature` | Services loaded; toggle selection; upload per service; status updates; remoteId stored |

---

*Cyclometer TCA Architecture Map v1.3 · 2026-09-17*
