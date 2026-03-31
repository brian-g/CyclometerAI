# CyclometerAI — Product Requirements Document
**Version:** 0.1 Draft  
**Date:** 2026-03-30  
**Status:** In Review  
**Author:** Brian (UX Design) + Claude (Specification)  
**Platform:** iOS 17+ · iPhone-first · Apple Watch companion  

---

## Table of Contents

1. [Product Vision](#1-product-vision)
2. [Problem Statement](#2-problem-statement)
3. [Target Users](#3-target-users)
4. [Competitive Landscape](#4-competitive-landscape)
5. [Design Principles](#5-design-principles)
6. [Feature Scope](#6-feature-scope)
7. [Screen Inventory](#7-screen-inventory)
8. [Core Features — Detailed Requirements](#8-core-features--detailed-requirements)
9. [Hardware Integrations](#9-hardware-integrations)
10. [Data Model](#10-data-model)
11. [Architecture](#11-architecture)
12. [Non-Functional Requirements](#12-non-functional-requirements)
13. [Phased Milestones](#13-phased-milestones)
14. [Open Questions](#14-open-questions)
15. [Out of Scope](#15-out-of-scope)
16. [Appendix — Design Tokens](#16-appendix--design-tokens)

---

## 1. Product Vision

CyclometerAI is a **safety-first cycling companion for iPhone and Apple Watch** that transforms real-time sensor data — rear radar, heart rate, GPS, and speed — into an eyes-free, glanceable riding experience. Where most cycling apps treat safety as an add-on alert, CyclometerAI treats it as a first-class architectural concern: every design decision, interaction pattern, and data priority is evaluated through the lens of a rider who cannot safely look at a screen.

The central insight: **a cycling computer's most critical job is not to display data — it's to keep the rider alive when something dangerous is approaching from behind.**

---

## 2. Problem Statement

### Current State
Cyclists using a smartphone as a cycling computer face a dangerous information gap. Existing apps (Strava, Wahoo, Garmin Connect) are optimized for post-ride analysis, not real-time safety. When a radar alert fires — indicating an approaching vehicle — the rider must:

1. Look down at the screen
2. Parse a complex dashboard
3. Locate the radar visualization
4. Assess threat severity
5. Decide on evasive action

Steps 1–4 typically take 1–3 seconds of eyes-off-road time. At 30 km/h, that is 8–25 meters of blind riding.

### The Opportunity
The Garmin Varia RearVue 820 provides BLE-accessible radar data with vehicle distance, closing speed, and count. CyclometerAI's opportunity is to make that data immediately useful **without requiring the rider to look at the phone** — through progressive haptic escalation, peripheral color cues, audio alerts, and future AR glasses integration.

---

## 3. Target Users

### Primary — Recreational Road Cyclist
- Rides 3–5× per week on public roads
- Already owns or is considering a Garmin Varia radar
- Uses iPhone; may have Apple Watch
- Safety-conscious; rides routes with vehicle traffic
- Wants performance data but prioritizes ride safety

### Secondary — Enthusiast / Gran Fondo Rider
- Rides 5+ hours per week
- Cares about heart rate zones, power, and training load
- Uses cycling-specific hardware (Varia, Apple Watch)
- Wants a comprehensive dashboard with deep health data
- Comfortable pairing multiple Bluetooth devices

### Tertiary — Commuter Cyclist
- Rides in urban environments with frequent stops
- Cares about radar alerts more than performance metrics
- May use the app in lock-screen / always-on mode

### Non-Target
- Mountain bikers (off-road, no vehicle traffic context)
- Professional racers (require ANT+ power meters, not in MVP)
- Triathletes (multi-sport switching is complex; future consideration)

---

## 4. Competitive Landscape

| App | Radar Support | HR Zones | Eyes-Free | AR |
|---|---|---|---|---|
| **Cadence (Seven Bold)** | ✅ Best-in-class | Partial | ❌ | ❌ |
| **Wahoo ELEMNT** | ✅ (hardware only) | ✅ | Partial | ❌ |
| **Strava** | ❌ | Basic | ❌ | ❌ |
| **Garmin Connect Mobile** | ✅ (own device) | ✅ | ❌ | ❌ |
| **CyclometerAI** | ✅ First-class | ✅ Zone-aware | ✅ Core | 🔜 Planned |

**Key differentiator:** CyclometerAI is the only app designed from the ground up around eyes-free interaction patterns as a primary design constraint, not a post-launch feature.

---

## 5. Design Principles

### P1 — Eyes-Free First
Every safety-critical interaction must work without the rider looking at the screen. Haptics, audio, and peripheral color cues are primary. The screen is secondary for safety events.

### P2 — Glanceability
When the rider does look, information must be parsed in under one second. Large numerics, high-contrast colors, and strict information hierarchy are non-negotiable.

### P3 — Sunlight Legibility
The app operates in direct sunlight. All color choices must meet WCAG AA contrast ratios under bright ambient conditions. Saturated hues (not pastel) for safety-critical states.

### P4 — Progressive Escalation
Radar alerts must escalate proportionally to threat severity. A distant vehicle warrants a gentle haptic pulse. A rapidly closing vehicle warrants a full-screen color wash + continuous haptic + audio alert.

### P5 — Hardware Agnostic Degradation
The app must be fully functional without the Varia radar. Radar features activate when hardware is detected; core metrics (HR, speed, GPS) remain fully available without it.

### P6 — Minimal Interaction During Ride
Controls must be large enough to tap without looking. The active ride screen must require zero navigation to reach the most critical information.

---

## 6. Feature Scope

### MVP (Phase 1)
- Active ride dashboard with speed, HR, elapsed time, distance
- Garmin Varia RVR820 BLE integration with radar visualization
- Heart rate zone display (Zones 1–5) via Apple Watch / HealthKit
- Haptic alert system (3 escalation levels)
- Audio alerts for high-severity radar events
- GPS track recording
- Basic ride summary (post-ride)
- BLE device pairing screen
- Settings screen

### Phase 2
- Ride history with map replay
- Heart rate zone training graphs
- Cadence sensor support (BLE)
- Customizable metric tiles on dashboard
- Lock screen / Dynamic Island integration
- Apple Watch standalone companion app

### Phase 3
- ENGO 2 / ActiveLook AR glasses integration
- Route planning with turn-by-turn
- Segment detection and leaderboards
- Export to Strava, Garmin Connect, Apple Health

### Explicitly Out of Scope (MVP)
- ANT+ direct integration (iOS hardware limitation)
- SRAM AXS / electronic shifting data (no public write API)
- Power meter support
- Navigation / maps during ride
- Social features
- Subscription / paywall

---

## 7. Screen Inventory

| ID | Screen | Phase | Description |
|---|---|---|---|
| S01 | Onboarding — Welcome | MVP | App intro, permission requests (BLE, HealthKit, Location) |
| S02 | Onboarding — Hardware Pairing | MVP | BLE scan + pair Varia radar |
| S03 | Onboarding — Profile Setup | MVP | Age, resting HR, max HR for zone calculation |
| S04 | Home | MVP | Pre-ride summary; last ride, current conditions, quick-start |
| S05 | Active Ride Dashboard | MVP | **Primary screen.** Speed, HR zone, radar arc, elapsed time, distance |
| S06 | Radar Alert — Low | MVP | Peripheral amber wash; subtle haptic |
| S07 | Radar Alert — Medium | MVP | Amber border pulse; escalating haptic |
| S08 | Radar Alert — High | MVP | Full-screen red wash; continuous haptic + audio |
| S09 | Ride Paused | MVP | Pause state with resume / end ride options |
| S10 | Ride Summary | MVP | Distance, time, avg speed, HR zone breakdown, map thumbnail |
| S11 | Device Settings | MVP | BLE device management, pairing, signal strength |
| S12 | App Settings | MVP | Units, alert thresholds, haptic intensity, audio alerts |
| S13 | HR Zone Configuration | MVP | Manual zone entry OR calculated from profile |
| S14 | Ride History List | Phase 2 | Scrollable list of past rides |
| S15 | Ride Detail | Phase 2 | Full ride replay: map, HR graph, radar event timeline |
| S16 | Training Zones Graph | Phase 2 | Time-in-zone breakdown across recent rides |
| S17 | Apple Watch Face | Phase 2 | Glanceable watch complication |
| S18 | AR HUD Configuration | Phase 3 | Configure ENGO 2 / ActiveLook display layout |

---

## 8. Core Features — Detailed Requirements

### 8.1 Active Ride Dashboard (S05)

**Purpose:** The primary screen during a ride. Must convey all critical real-time information at a glance.

**Layout — Top Third:**
- Current speed (large numeral, `brTextPrimary`, minimum 64pt)
- Speed unit label (km/h or mph)
- Elapsed time (secondary size, `brTextSecondary`)

**Layout — Middle Third:**
- Radar arc visualization (described in §8.2)
- Vehicle count badge

**Layout — Bottom Third:**
- Heart rate (with zone color indicator, e.g., `brHRZone4`)
- Zone label ("Zone 4 · Threshold")
- Distance traveled

**Acceptance Criteria:**
- [ ] Screen renders within 100ms of ride start
- [ ] Speed updates at minimum 1Hz
- [ ] HR updates reflected within 2 seconds of Apple Watch reading
- [ ] Radar arc updates within 500ms of BLE data arrival
- [ ] All text meets WCAG AA at minimum in both light and dark mode
- [ ] Dashboard is accessible with VoiceOver disabled (ride mode does not use VoiceOver)

---

### 8.2 Radar Visualization

**Purpose:** Represent the approaching-vehicle threat state visually on the ride dashboard.

**Design:** A semi-circular arc spanning the bottom of the dashboard, representing the road behind the rider. Vehicles appear as dots on the arc, positioned by relative distance. Color of dots maps to closing speed severity.

**Dot Color Mapping:**
| Closing Speed | Color Token | Meaning |
|---|---|---|
| Stationary / receding | `brRatingGood` | Safe |
| < 30 km/h differential | `brRatingOkay` | Caution |
| ≥ 30 km/h differential | `brRatingBad` | Danger |

**Data Requirements:**
- Vehicle count (0–8 from Varia)
- Distance per vehicle (meters)
- Closing speed per vehicle (km/h differential)

**Acceptance Criteria:**
- [ ] Arc renders correctly with 0 vehicles (empty state)
- [ ] Arc renders correctly with 1–8 vehicles
- [ ] Dot position updates smoothly (no jumping) as vehicle approaches
- [ ] Color transitions are animated (0.3s ease)
- [ ] No radar hardware → arc displays "Radar not connected" state gracefully

---

### 8.3 Haptic Alert System

**Purpose:** Communicate radar threat severity without requiring the rider to look at the phone.

**Three Escalation Levels:**

| Level | Trigger | Haptic Pattern | Screen Effect |
|---|---|---|---|
| L1 — Advisory | 1–2 vehicles, low closing speed | Single gentle tap (`UIImpactFeedbackGenerator` .light) | Peripheral amber tint (10% opacity overlay) |
| L2 — Caution | 1+ vehicle, moderate closing speed OR 3+ vehicles | Double tap, 0.5s interval (.medium) | Amber border pulse animation |
| L3 — Danger | Any vehicle ≥ 30 km/h closing speed | Continuous rhythmic tap (.heavy, 0.3s on/off) + audio tone | Full-screen `brRatingBad` wash + audio alert |

**Alert Rules:**
- Alerts must escalate but not spam. Minimum 3 seconds between same-level re-triggers.
- L3 alert must not be dismissible by the rider (persists until threat recedes).
- Audio alert (L3 only) uses system sound channel, respects Silent Mode toggle — **do not** override Silent Mode unless user has explicitly enabled "Override Silent for Safety Alerts" in settings.
- On Apple Watch (Phase 2): mirror haptic pattern on wrist.

**Acceptance Criteria:**
- [ ] L1 haptic fires within 500ms of threshold crossing
- [ ] L2 fires within 500ms
- [ ] L3 fires within 200ms (tighter budget due to safety criticality)
- [ ] Haptic pattern is perceptible through cycling gloves (validated by testing with `.heavy` generator at minimum)
- [ ] L3 audio alert is audible at 70dB ambient noise with phone in jersey pocket
- [ ] All three levels are testable without Varia hardware (using mock BLE data)

---

### 8.4 Heart Rate Zone Integration

**Purpose:** Display current training zone alongside performance metrics, with zone-appropriate color coding.

**Zone Calculation — Karvonen Formula:**
```
HR Reserve = Max HR − Resting HR
Zone boundaries:
  Zone 1: < 60% HR Reserve  (Recovery)
  Zone 2: 60–70% HR Reserve (Endurance)
  Zone 3: 70–80% HR Reserve (Tempo)
  Zone 4: 80–90% HR Reserve (Threshold)
  Zone 5: > 90% HR Reserve  (VO2 Max)
```

**Color Mapping (from design token system):**
| Zone | Token | Hex (Light) |
|---|---|---|
| Zone 1 | `brHRZone1` | `#90CAF9` |
| Zone 2 | `brHRZone2` | `#1976D2` |
| Zone 3 | `brHRZone3` | `#60BD10` |
| Zone 4 | `brHRZone4` | `#F57C00` |
| Zone 5 | `brHRZone5` | `#D32F2F` |

**HealthKit Data Sources (in priority order):**
1. Apple Watch real-time HR stream (highest accuracy, lowest latency)
2. HealthKit HKWorkoutSession HR samples
3. Manual BPM entry (fallback, not recommended during ride)

**Acceptance Criteria:**
- [ ] Zone calculated correctly for all 5 zones given arbitrary Max HR / Resting HR inputs
- [ ] Zone color updates on dashboard within 2 seconds of new HR reading
- [ ] HR zone history is recorded per-second during active ride for post-ride analysis
- [ ] App functions normally when HealthKit permission is denied (HR zone tile shows "No HR Source")
- [ ] Zone 5 display does not trigger radar-level alert patterns (separate visual channels)

---

### 8.5 GPS Track Recording

**Purpose:** Record the ride route for post-ride map display and distance calculation.

**Requirements:**
- Use `CoreLocation` with `CLLocationManager` at `kCLLocationAccuracyBest`
- Record at minimum 1Hz; pause recording when speed < 2 km/h for > 30 seconds (stationary detection)
- Persist track to local storage using `CoreData` or file-based persistence
- Distance calculation: cumulative Haversine formula across location samples
- Background location must remain active when app is backgrounded during a ride

**Acceptance Criteria:**
- [ ] GPS track begins recording within 5 seconds of ride start
- [ ] Distance accuracy within 2% of ground truth over a 10km test route
- [ ] Track persists across app backgrounding and foregrounding
- [ ] No GPS → ride still usable with manual distance tracking disabled

---

### 8.6 Ride Recording State Machine

**States:** `idle` → `active` → `paused` → `ended`

**Transitions:**
- `idle → active`: User taps "Start Ride"; GPS lock acquired
- `active → paused`: User taps pause button; all sensor recording suspended
- `paused → active`: User taps resume; recording resumes
- `paused → ended`: User taps "End Ride"; ride summary generated
- `active → ended`: Auto-end if speed = 0 for > 5 minutes (configurable)

**Acceptance Criteria:**
- [ ] All state transitions are explicit TCA Actions
- [ ] State persists across app kill/relaunch (active ride survives app crash)
- [ ] Ride data is committed to storage at `paused` and `ended` states

---

## 9. Hardware Integrations

### 9.1 Garmin Varia RVR820 — BLE Integration

**Protocol:** Bluetooth Low Energy (BLE)  
**Note:** ANT+ is not viable on modern iPhones (no hardware). All Varia integration is via BLE only.

**BLE Service UUIDs (Varia Radar):**
- Radar Alert Service: `6A4E3200-667B-11E3-949A-0800200C9A66`
- Radar Alert Characteristic: `6A4E3202-667B-11E3-949A-0800200C9A66`

**Data Packet Structure:**
- Byte 0: Alert level (0 = clear, 1 = advisory, 2 = caution, 3 = danger)
- Bytes 1–N: Vehicle records (count, distance, speed delta per vehicle)

**Connection State Machine:**
```
disconnected → scanning → connecting → connected → active
                                           ↓
                                      disconnected (on error / range loss)
```

**Reconnection Policy:**
- Auto-reconnect on signal loss with exponential backoff (1s, 2s, 4s, max 30s)
- User notified via status indicator on dashboard if radar is disconnected for > 10 seconds during an active ride

**Acceptance Criteria:**
- [ ] App discovers Varia within 10 seconds of BLE scan initiation
- [ ] Characteristic notifications arrive and parse correctly
- [ ] Disconnection during active ride triggers L1 advisory haptic + dashboard status indicator
- [ ] All BLE operations are testable with a mock `BluetoothClient` (TCA Environment)
- [ ] App does not crash when BLE permission is denied

---

### 9.2 Apple Watch / HealthKit

**HealthKit Entitlements Required:**
- `HKQuantityTypeIdentifierHeartRate` (read)
- `HKWorkoutType` (read/write for workout session)

**Integration Approach:**
- Request HealthKit authorization at onboarding (S03)
- Stream live HR during active ride via `HKAnchoredObjectQuery` or `HKWorkoutSession`
- Write completed ride as `HKWorkout` to HealthKit on ride end (Phase 2)

**Acceptance Criteria:**
- [ ] HR data flows from Apple Watch to dashboard within 2 seconds
- [ ] App functions with HealthKit denied (graceful degradation)
- [ ] HR zone history is stored locally for rides where HealthKit is unavailable

---

### 9.3 ENGO 2 / ActiveLook AR Glasses (Phase 3)

**SDK:** ActiveLook iOS SDK  
**Protocol:** BLE  
**Display Capability:** Monochrome HUD, ~300×256px effective area

**Planned HUD Layout:**
- Speed (large, center)
- Current HR zone indicator (zone number + color coded bar)
- Radar alert indicator (right edge — single icon, escalating brightness)

**Constraints:**
- Monochrome display requires icon-based encoding for alert severity (not color-dependent)
- HUD updates capped at 1Hz to preserve BLE bandwidth
- Full AR spec to be written as a separate Phase 3 document

---

## 10. Data Model

### Core Entities

```
Ride
├── id: UUID
├── startedAt: Date
├── endedAt: Date?
├── distance: Double (meters)
├── duration: TimeInterval
├── averageSpeed: Double (m/s)
├── maxSpeed: Double (m/s)
├── averageHeartRate: Int?
├── maxHeartRate: Int?
├── hrZoneDurations: [Int: TimeInterval]  // zone → seconds in zone
├── radarEventCount: Int
├── gpsTrack: [CLLocation]
└── radarEvents: [RadarEvent]

RadarEvent
├── id: UUID
├── timestamp: Date
├── vehicleCount: Int
├── alertLevel: AlertLevel  // .advisory | .caution | .danger
├── closingSpeed: Double (km/h)
└── distance: Double (meters)

RadarVehicle
├── id: Int  // 1–8 from Varia
├── distance: Double (meters)
├── closingSpeedDelta: Double (km/h)
└── alertLevel: AlertLevel

HRSample
├── id: UUID
├── rideId: UUID
├── timestamp: Date
├── bpm: Int
└── zone: Int  // 1–5

UserProfile
├── id: UUID
├── restingHeartRate: Int
├── maxHeartRate: Int
├── preferredUnit: UnitSystem  // .metric | .imperial
├── radarAlertThresholds: AlertThresholds
└── hapticIntensity: HapticIntensity  // .light | .medium | .heavy
```

### Persistence Strategy
- **Active ride data:** In-memory TCA State; checkpointed to disk every 30 seconds
- **Completed rides:** CoreData or SwiftData (to be decided in architecture phase)
- **User profile:** `UserDefaults` for simple key-value; migrate to SwiftData if profile grows
- **GPS track:** Stored as encoded `[CLLocation]` array in ride record

---

## 11. Architecture

### Pattern: The Composable Architecture (TCA)

**Rationale:** CyclometerAI has multiple concurrent real-time data streams (BLE radar, HealthKit HR, CoreLocation GPS), safety-critical alert logic that must be fully unit-testable without hardware, and planned multi-target expansion (Apple Watch, AR glasses). TCA's explicit state management, side-effect isolation via `Effect`, and `TestStore` make it the strongest fit.

**Feature Decomposition:**

```
AppFeature
├── OnboardingFeature
│   ├── WelcomeFeature
│   ├── HardwarePairingFeature
│   └── ProfileSetupFeature
├── HomeFeature
├── ActiveRideFeature              ← Primary feature
│   ├── RadarFeature               ← BLE stream, alert logic
│   ├── HeartRateFeature           ← HealthKit stream, zone calc
│   ├── SpeedFeature               ← GPS / CoreLocation
│   └── AlertOrchestratorFeature   ← Combines streams → haptic/audio
├── RideHistoryFeature
├── RideDetailFeature
└── SettingsFeature
    ├── DeviceSettingsFeature
    ├── HRZoneSettingsFeature
    └── AlertSettingsFeature
```

**Dependency Clients (TCA Environment equivalents):**
```swift
// All hardware dependencies are protocol-based for testability
BluetoothClient         // Varia BLE — real + mock implementations
HealthKitClient         // HR streaming — real + mock
LocationClient          // GPS — real + mock
HapticClient            // Haptic engine — real + no-op for tests
AudioAlertClient        // Audio engine — real + no-op for tests
PersistenceClient       // CoreData / SwiftData — real + in-memory test
```

### Project Structure
```
CyclometerAI/
├── App/
│   ├── CyclometerAIApp.swift
│   └── AppFeature.swift
├── Features/
│   ├── ActiveRide/
│   ├── Radar/
│   ├── HeartRate/
│   ├── Onboarding/
│   ├── RideHistory/
│   └── Settings/
├── Clients/
│   ├── BluetoothClient.swift
│   ├── HealthKitClient.swift
│   ├── LocationClient.swift
│   ├── HapticClient.swift
│   └── AudioAlertClient.swift
├── Models/
│   ├── Ride.swift
│   ├── RadarEvent.swift
│   ├── HRSample.swift
│   └── UserProfile.swift
├── DesignSystem/
│   ├── Color+CyclometerAI.swift
│   ├── Typography.swift
│   └── Components/
└── Tests/
    ├── RadarFeatureTests.swift
    ├── HeartRateFeatureTests.swift
    ├── AlertOrchestratorTests.swift
    └── RideRecordingTests.swift
```

---

## 12. Non-Functional Requirements

### Performance
- Active ride dashboard: 60fps render target; no dropped frames during BLE + GPS + HR simultaneous updates
- BLE characteristic processing: < 50ms from receipt to state update
- App cold launch to ready-to-ride: < 3 seconds
- Memory footprint: < 100MB during active ride on iPhone 13 or later

### Battery
- Active ride session: < 15% battery drain per hour (iPhone 14 baseline)
- GPS in background: use `CLLocationManager` `allowsBackgroundLocationUpdates = true` with `pausesLocationUpdatesAutomatically = false`
- BLE scanning: use connection-based notification (not continuous scan) to minimize radio duty cycle

### Reliability
- Active ride state must survive app backgrounding, phone calls, and iOS memory pressure events
- Ride data must not be lost if the app crashes during an active ride (checkpoint every 30 seconds)
- Radar alert L3 must not be skipped even if the UI thread is momentarily busy

### Accessibility
- VoiceOver: supported on all non-ride screens; explicitly suspended during active ride (cycling context)
- Dynamic Type: supported on all screens
- Minimum tap target: 44×44 pt on all active ride controls (per Apple HIG)

### Privacy
- HealthKit data is read-only; no data is sent to any server
- GPS data is stored locally only; no server upload without explicit user action (Phase 3 export)
- No analytics or crash reporting without explicit user consent (IDFA opt-in)
- BLE device identifiers are not transmitted externally

### Localization (MVP)
- English only at launch
- Unit system: metric / imperial toggle (stored in UserProfile)
- Date/time: respects device locale

---

## 13. Phased Milestones

### Phase 1 — MVP (Target: 3 months)
**Goal:** A fully functional, safe-to-ride app with radar and HR.

| Milestone | Deliverable |
|---|---|
| M1 | Xcode project scaffold; TCA dependency; CI/CD via GitHub Actions |
| M2 | BLE Varia client — connect, parse, mock |
| M3 | Active Ride Dashboard — speed, time, distance (no radar, no HR) |
| M4 | Radar visualization on dashboard; haptic alerts L1–L3 |
| M5 | HealthKit integration; HR zone display |
| M6 | GPS track recording; ride persistence |
| M7 | Ride summary screen |
| M8 | Settings screens (device, alerts, HR zones) |
| M9 | Onboarding flow |
| M10 | QA, TestFlight beta, bug fixes |
| M11 | App Store submission |

### Phase 2 — Companion & History (Target: +2 months post-launch)
Ride history, Apple Watch app, Dynamic Island, cadence sensor, custom dashboard tiles.

### Phase 3 — AR & Platform (Target: +4 months post-Phase 2)
ENGO 2 / ActiveLook integration, route planning, Strava/Garmin export.

---

## 14. Open Questions

| # | Question | Owner | Priority |
|---|---|---|---|
| OQ1 | SwiftData vs CoreData for ride persistence? SwiftData is simpler but iOS 17+ only — is that acceptable given iOS 17 minimum target? | Engineering | High |
| OQ2 | Does Garmin's mobile SDK provide a cleaner path to Varia BLE than raw CoreBluetooth? Needs spike. | Engineering | High |
| OQ3 | Should the app support iPad? No current requirement, but SwiftUI is iPad-compatible by default. | Product | Low |
| OQ4 | Audio alert delivery: AVAudioEngine vs AVSpeechSynthesizer for L3 alerts? Synthesized voice ("Car approaching") may be more useful than a tone. | Design + Engineering | Medium |
| OQ5 | Override Silent Mode for L3 radar alerts? Requires user opt-in. UX pattern needs validation. | Design | High |
| OQ6 | App name: "CyclometerAI" vs "BikeRider" for App Store submission? | Product | Medium |
| OQ7 | What is the minimum Varia firmware version required for BLE characteristic support? | Engineering | High |
| OQ8 | Should Phase 1 include a basic Apple Watch complication, or defer entirely to Phase 2? | Product | Medium |
| OQ9 | HR zone manual override: allow user to define custom zone percentages? Or Karvonen-only for MVP? | Design | Low |
| OQ10 | TestFlight beta audience: open beta or closed (known cyclists)? | Product | Low |

---

## 15. Out of Scope

The following are explicitly excluded from all current phases unless a separate decision is made:

- **ANT+ direct support** — iOS hardware does not support ANT+. Garmin SDK may be evaluated as a bridge (OQ2).
- **SRAM AXS / electronic shifting** — No public write API; read-only ANT+ Shifting Profile is low-value without write access.
- **Power meter support** — Requires ANT+ or BLE power meter integration; deferred to post-Phase 3.
- **Live ride sharing** — Requires server infrastructure; out of scope for local-first MVP.
- **Coaching / AI training plans** — Complex domain, separate product consideration.
- **Android** — iOS-only; no cross-platform framework consideration.
- **Web dashboard** — No server component planned.
- **Social / community features** — No social graph in MVP.

---

## 16. Appendix — Design Tokens

The CyclometerAI color system is a 30-token system organized into 7 categories. Full specification in `BikeRider-ColorSystem.md`. Summary of safety-critical tokens:

| Token | Light Mode | Dark Mode | Usage |
|---|---|---|---|
| `brRatingBad` | `#D32F2F` | `#EF5350` | L3 danger alert |
| `brRatingOkay` | `#ED8B00` | `#FFB020` | L2 caution alert |
| `brRatingGood` | `#2E8B08` | `#60BD10` | Clear / safe state |
| `brHRZone4` | `#F57C00` | `#FFA726` | Threshold zone indicator |
| `brHRZone5` | `#D32F2F` | `#EF5350` | VO2 Max zone indicator |
| `brPrimary` | `#60BD10` | `#6FD11E` | Brand, CTAs, active states |

Typography, spacing, and component-level design specs to be produced as a separate Design System Extension document.

---

*CyclometerAI PRD v0.1 · Draft for review · Not for distribution*
