# Cyclometer — TCA Architecture Map
**Version:** 1.2  
**Date:** 2026-05-21  
**Updated:** 2026-05-22 - HKWorkout write at ride end; SyncClient + RideSummaryFeature spec; service sync from S10  
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
@Dependency(\.sync)              var sync: SyncClient
@Dependency(\.continuousClock)    var clock: any Clock<Duration>  // TCA built-in
```

### 2.1 Client Protocols

```swift
@DependencyClient struct BluetoothClient        // See BLE.md §7
@DependencyClient struct HealthKitClient
@DependencyClient struct LocationClient
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
    // Write — HKWorkout recorded automatically at ride end (MVP)
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
    let altitude: Double
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
    var fetchUserProfile: @Sendable () async throws -> UserProfile = { UserProfile() }
    var saveUserProfile: @Sendable (UserProfile) async throws -> Void = { _ in }
    var fetchRides: @Sendable () async throws -> [Ride] = { [] }
}
```

---

## 3. Feature Tree

```
AppFeature
├── OnboardingFeature
│   ├── WelcomeFeature
│   └── SensorPairingFeature
├── TabFeature                         (TabView shell + tab selection)
│   ├── RidesTabFeature                (Rides tab — ride list + start sheet)
│   │   ├── RideListFeature            (S14 — Phase 2)
│   │   ├── StartSheetFeature          (S05.1)
│   │   ├── RoutePickerFeature         (S05.2 — Phase 2)
│   │   └── ActiveRideAccessoryFeature (S05.3 — accessory strip above TabBar)
│   ├── RoutesTabFeature               (S19/S20 — Phase 2; "Coming Soon" in MVP)
│   └── SettingsTabFeature
│       ├── DeviceManagementFeature    (S11)
│       ├── HRZoneSettingsFeature      (embedded in S12)
│       └── AccountsFeature            (embedded in S12)
└── ActiveRideFeature                  (S05 — full-screen dashboard, above TabView)
    ├── RadarFeature
    ├── HeartRateFeature
    ├── SpeedFeature
    ├── CadenceFeature
    ├── LocationFeature
    ├── TrackPointRecorderFeature
    ├── WheelCalibrationFeature
    ├── AlertOrchestratorFeature
    ├── NavigationFeature              (map, GPX route, turn alerts)
    └── RideSummaryFeature             (S10 — post-ride)
```

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
        var userProfile: UserProfile = UserProfile()
    }

    enum Action {
        case onboarding(OnboardingFeature.Action)
        case tab(TabFeature.Action)
        case activeRide(ActiveRideFeature.Action)
        case appLaunched
        case onboardingCompleted
        case userProfileLoaded(UserProfile)
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
        var recordingState: RideRecordingState = .active

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

        // Ride summary (Phase 2: running HR zone durations)
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
        var userProfile: UserProfile?             // Injected from parent for Karvonen calc
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
        var silentModeOverrideEnabled: Bool = false  // From UserProfile
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

                return .run(priority: .userInteractive) { [level, previous, silentOverride = state.silentModeOverrideEnabled] send in
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

> **Note:** `priority: .userInteractive` ensures the haptic/audio Effect is not starved by lower-priority Effects. The L3 danger haptic and audio tone are guaranteed to fire within the 200ms budget.

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

        // HKWorkout write fires automatically on appear; status tracked here
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
RideSummaryFeature.reduce(.onAppear)
    │
    │ guard healthKitWorkoutStatus == .pending
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
    │ .run(priority: .userInteractive)
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

```
Cyclometer/
├── App/
│   ├── CyclometerApp.swift                    // @main; AppFeature store; font registration
│   └── AppFeature.swift
│
├── Features/
│   ├── Tab/
│   │   ├── TabFeature.swift
│   │   ├── TabView+Cyclometer.swift
│   │   └── RidesTab/
│   │       ├── RidesTabFeature.swift
│   │       ├── RideListFeature.swift          // Phase 2
│   │       ├── StartSheetFeature.swift
│   │       └── ActiveRideAccessoryFeature.swift
│   │
│   ├── ActiveRide/
│   │   ├── ActiveRideFeature.swift
│   │   ├── ActiveRideDashboardView.swift
│   │   │
│   │   ├── Radar/
│   │   │   ├── RadarFeature.swift
│   │   │   ├── VehiclePassDetection.swift
│   │   │   └── RadarSidebarView.swift         // W7 widget
│   │   │
│   │   ├── HeartRate/
│   │   │   ├── HeartRateFeature.swift
│   │   │   └── HeartRateWidget.swift          // W4 widget
│   │   │
│   │   ├── SpeedCadence/
│   │   │   ├── SpeedCadenceFeature.swift
│   │   │   ├── CSCCalculator.swift
│   │   │   └── SpeedWidget.swift              // W1/W2 widgets
│   │   │
│   │   ├── Location/
│   │   │   ├── LocationFeature.swift
│   │   │   └── MapWidget.swift                // W8 widget
│   │   │
│   │   ├── TrackRecorder/
│   │   │   ├── TrackPointRecorderFeature.swift
│   │   │   └── RideDataBuffer.swift
│   │   │
│   │   ├── WheelCalibration/
│   │   │   └── WheelCalibrationFeature.swift
│   │   │
│   │   ├── AlertOrchestrator/
│   │   │   └── AlertOrchestratorFeature.swift
│   │   │
│   │   └── Navigation/
│   │       ├── NavigationFeature.swift
│   │       └── DirectionsWidget.swift         // W9 widget
│   │
│   ├── RideSummary/
│   │   ├── RideSummaryFeature.swift
│   │   └── RideSummaryView.swift
│   │
│   ├── Onboarding/
│   │   ├── OnboardingFeature.swift
│   │   ├── WelcomeFeature.swift
│   │   └── SensorPairingFeature.swift
│   │
│   ├── Settings/
│   │   ├── SettingsTabFeature.swift
│   │   ├── DeviceManagementFeature.swift
│   │   ├── HRZoneSettingsFeature.swift
│   │   └── AccountsFeature.swift
│   │
│   └── Routes/                                // Phase 2
│       ├── RoutesTabFeature.swift
│       ├── RouteManagementFeature.swift
│       └── RouteDetailFeature.swift
│
├── Clients/
│   ├── BluetoothClient.swift
│   ├── BluetoothClient+Live.swift
│   ├── BluetoothClient+Mock.swift
│   ├── HealthKitClient.swift
│   ├── LocationClient.swift
│   ├── HapticClient.swift
│   ├── AudioAlertClient.swift
│   ├── PersistenceClient.swift
│   ├── NavigationClient.swift
│   └── WheelCalibrationClient.swift
│
├── Models/
│   ├── AlertLevel.swift
│   ├── RadarVehicle.swift
│   ├── SensorSource.swift
│   ├── TrackPointDTO.swift
│   ├── UserProfile.swift                      // SwiftData @Model
│   ├── Ride.swift                             // SwiftData @Model
│   ├── RadarEvent.swift                       // SwiftData @Model
│   ├── VehiclePassEvent.swift                 // SwiftData @Model
│   └── TrackPointMO.swift                     // CoreData NSManagedObject
│
├── Persistence/
│   ├── PersistenceClient+Live.swift
│   ├── CyclometerSchema.swift                 // SwiftData schema + migration plan
│   └── TrackPointCoreDataStore.swift
│
├── Export/
│   ├── GPXExporter.swift
│   └── GPXExporter+VehiclePass.swift
│
├── DesignSystem/
│   ├── Color+Cyclometer.swift
│   ├── AppFonts.swift                         // D-DIN registration (from prototype)
│   ├── HeroNumber.swift                       // From prototype; adapted for TCA
│   └── Components/
│       ├── DashboardMetricCard.swift
│       ├── DashboardSpeedCard.swift
│       └── OpenRingProgressView.swift
│                                              // The shared sensor row lives at
│                                              // UI/Components/SensorListRow/; see §9
│
└── Tests/
    ├── RadarFeatureTests.swift
    ├── VehiclePassDetectionTests.swift
    ├── AlertOrchestratorTests.swift
    ├── HeartRateFeatureTests.swift
    ├── SpeedFeatureTests.swift
    ├── CadenceFeatureTests.swift
    ├── WheelCalibrationTests.swift
    ├── TrackPointRecorderTests.swift
    ├── GPXExporterTests.swift
    ├── RideRecordingTests.swift               // Full ride state machine
    └── PersistenceTests.swift
```

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
| `RouteStub` data structures | Replace with `Route` SwiftData model | Shape matches; swap stub for real persistence |
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
| `AlertOrchestratorFeature` | Effect dispatched at `userInteractive` priority; < 200ms mock latency |
| `GPXExporter` | Schema validation; absent fields (not zero) for missing sensors; vehicle pass waypoints |
| `VehiclePassDetection` | Overtake vs. turn-off discrimination; 2s minimum tracking |
| Full ride state machine | `idle → active → paused → active → ended`; crash recovery from checkpoint |
| `RideSummaryFeature` | HKWorkout write on appear; failure handled gracefully; sync sheet presented on tap |
| `RideSyncSheetFeature` | Services loaded; toggle selection; upload per service; status updates; remoteId stored |

---

*Cyclometer TCA Architecture Map v1.2 · 2026-05-22*
