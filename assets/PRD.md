# Cyclometer — Product Requirements Document
**Version:** 0.2 Draft  
**Date:** 2026-03-31  
**Status:** Second Review  
**Author:** Brian (UX Design) + Claude (Specification)  
**Platform:** iOS 17+ · iPhone-first · Apple Watch companion  
**App Name:** Cyclometer

---

## Revision History

| Version | Date | Author | Changes |
|---|---|---|---|
| 0.1 | 2026-03-30 | Brian / Claude | Initial draft |
| 0.2 | 2026-03-31 | Brian / Claude | Radar device corrected to RTL515/RCT715; BLE sensor priority for HR/speed/cadence; power meter to Phase 3; navigation to MVP; data model corrections; GPX export with gpxtpx:TrackPointExtension; resolved OQ1,3,4,5,6,8,9,10; app renamed Cyclometer |

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
16. [Appendix A — Design Tokens](#16-appendix-a--design-tokens)
17. [Appendix B — GPX TrackPoint Extension Schema](#17-appendix-b--gpx-trackpoint-extension-schema)

---

## 1. Product Vision

Cyclometer is a **safety-first cycling companion for iPhone and Apple Watch** that synthesizes real-time sensor data — rear radar, heart rate, speed, cadence, GPS, and optionally power — into an eyes-free, glanceable riding experience optimized for outdoor conditions. The app treats radar visualization and safety alerting as first-class architectural concerns: every design decision, interaction pattern, and data priority is evaluated through the lens of a rider who cannot safely look at a screen.

The central insight: **a cycling computer's most critical job is not to display data — it's to keep the rider alive when something dangerous is approaching from behind.**

Cyclometer records every ride as an industry-standard GPX file with full `gpxtpx:TrackPointExtension` data — heart rate, cadence, speed, and power correlated per track point — available directly in the iOS Files app and exportable to any compatible platform.

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
The Garmin Varia RTL515 and RCT715 expose real-time radar alert data over BLE. Cyclometer's opportunity is to make that data immediately useful **without requiring the rider to look at the phone** — through progressive haptic escalation, peripheral color cues, audio alerts, and future AR glasses integration. Combined with rich BLE sensor integration (HR, speed, cadence) and standards-based GPX export, Cyclometer replaces a dedicated cycling computer for the majority of cyclists.

---

## 3. Target Users

### Primary — Recreational Road Cyclist
- Rides 3–5× per week on public roads
- Already owns or is considering a Garmin Varia radar
- Uses iPhone; may have Apple Watch and BLE cycling sensors
- Safety-conscious; rides routes with vehicle traffic
- Wants performance data but prioritizes ride safety

### Secondary — Enthusiast / Gran Fondo Rider
- Rides 5+ hours per week
- Cares about heart rate zones, power, and training load
- Uses cycling-specific hardware (Varia, Apple Watch, BLE HR strap, BLE speed/cadence sensors)
- Wants a comprehensive dashboard with deep health data
- Comfortable pairing multiple Bluetooth devices

### Tertiary — Commuter Cyclist
- Rides in urban environments with frequent stops and navigation needs
- Cares about radar alerts and turn-by-turn navigation
- May use the app in lock-screen / always-on mode

### Non-Target
- Mountain bikers (off-road, no vehicle traffic context)
- Professional racers requiring race-legal head units
- Triathletes (multi-sport switching is complex; future consideration)

---

## 4. Competitive Landscape

| App | Radar Support | HR Zones | Eyes-Free | Navigation | GPX Export |
|---|---|---|---|---|---|
| **Cadence (Seven Bold)** | ✅ Best-in-class | Partial | ❌ | ❌ | Partial |
| **Wahoo ELEMNT** | ✅ (hardware only) | ✅ | Partial | ✅ | ✅ |
| **Strava** | ❌ | Basic | ❌ | Limited | ✅ |
| **Garmin Connect Mobile** | ✅ (own device) | ✅ | ❌ | ✅ | ✅ |
| **Cyclometer** | ✅ First-class | ✅ Zone-aware | ✅ Core | ✅ MVP | ✅ GPX+ext |

**Key differentiator:** Cyclometer is the only app designed from the ground up around eyes-free interaction patterns as a primary design constraint, combined with full-fidelity GPX export with per-point biometric correlation.

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

### P5 — Sensor Hierarchy with Graceful Degradation
For every metric, the highest-fidelity source is preferred. The app degrades gracefully when any sensor is unavailable, always using the best available source. The rider is never blocked by missing hardware.

### P6 — Standards-Based Data Portability
Ride data is the rider's data. Every ride exports as a standards-compliant GPX file with biometric extensions. No proprietary formats, no lock-in.

### P7 — Minimal Interaction During Ride
Controls must be large enough to tap without looking. The active ride screen must require zero navigation to reach the most critical information.

---

## 6. Feature Scope

### MVP (Phase 1)
- Active ride dashboard — speed, HR, cadence, elapsed time, distance, live map
- Garmin Varia RTL515 / RCT715 BLE radar integration with arc visualization
- BLE sensor priority system — HR strap, speed/cadence sensor, with Apple Watch and GPS as fallbacks
- Heart rate zone display (Zones 1–5) via BLE HR sensor or Apple Watch / HealthKit
- Haptic alert system (3 escalation levels) with Silent Mode override
- Audio tone alerts for high-severity radar events
- GPS track recording with live map view
- GPX export with `gpxtpx:TrackPointExtension` (HR, cadence, speed per track point)
- GPX files available in iOS Files app
- Basic ride summary (post-ride)
- BLE device pairing and management screen
- Settings screen
- Open TestFlight beta

### Phase 2
- Ride history with map replay
- Heart rate zone training graphs
- Customizable metric tiles on dashboard
- Lock screen / Dynamic Island integration
- Apple Watch standalone companion app and complication
- Cadence + HR data visualization on ride detail screen
- Strava / Garmin Connect export

### Phase 3
- Power meter BLE support (ANT+ bridge via Garmin SDK if viable; BLE power meters natively)
- ENGO 2 / ActiveLook AR glasses integration
- Route planning with turn-by-turn
- Segment detection

### Resolved Decisions (from v0.1 Open Questions)
- **Persistence:** SwiftData (iOS 17+ minimum target confirmed)
- **Platform:** iPhone only; no iPad support
- **Audio alerts:** Tones (not synthesized voice)
- **Silent Mode:** Override for L3 danger alerts (user-confirmed in settings)
- **App name:** Cyclometer
- **Apple Watch:** Deferred to Phase 2
- **HR zone formula:** Karvonen only in MVP
- **TestFlight:** Open beta

---

## 7. Screen Inventory

| ID | Screen | Phase | Description |
|---|---|---|---|
| S01 | Onboarding — Welcome | MVP | App intro, permission requests (BLE, HealthKit, Location, Files) |
| S02 | Onboarding — Sensor Pairing | MVP | BLE scan + pair radar, HR strap, speed/cadence sensor |
| S03 | Onboarding — Profile Setup | MVP | Age; pulls Max HR and Resting HR from Apple Health if available |
| S04 | Home | MVP | Pre-ride summary; last ride, sensor status badges, quick-start |
| S05 | Active Ride Dashboard | MVP | **Primary screen.** Speed, HR zone, radar arc, cadence, elapsed time, distance, live map |
| S06 | Radar Alert — Advisory (L1) | MVP | Peripheral amber wash; subtle haptic |
| S07 | Radar Alert — Caution (L2) | MVP | Amber border pulse; escalating haptic |
| S08 | Radar Alert — Danger (L3) | MVP | Full-screen red wash; continuous haptic + tone; overrides Silent Mode |
| S09 | Ride Paused | MVP | Pause state with live map frozen; resume / end ride options |
| S10 | Ride Summary | MVP | Distance, time, avg speed, HR zone breakdown, cadence avg, map thumbnail, GPX export action |
| S11 | Device Management | MVP | BLE device list; signal strength; pair / unpair; sensor source priority |
| S12 | App Settings | MVP | Units, alert thresholds, haptic intensity, audio alert toggle, Silent Mode override toggle |
| S13 | HR Zone Configuration | MVP | Pulled from Apple Health; manual override; Karvonen calculation display |
| S14 | Ride History List | Phase 2 | Scrollable list of past rides with summary stats |
| S15 | Ride Detail | Phase 2 | Full ride: map replay, HR graph, cadence graph, radar event timeline |
| S16 | Training Zones Graph | Phase 2 | Time-in-zone breakdown across recent rides |
| S17 | Apple Watch Face | Phase 2 | Glanceable watch complication and standalone mini-dashboard |
| S18 | AR HUD Configuration | Phase 3 | Configure ENGO 2 / ActiveLook display layout |

> **Note:** Screen-level UX detail — layout, component hierarchy, interaction patterns, and annotation — is specified in `UX.md`. The PRD defines *what* each screen must accomplish; UX.md defines *how* it is structured.

---

## 8. Core Features — Detailed Requirements

### 8.1 Active Ride Dashboard (S05)

The active ride dashboard is the primary screen during a ride. Full layout specification, component hierarchy, and interaction annotations are defined in `UX.md` (see S05 section). This section captures functional requirements and acceptance criteria only.

**Functional Requirements:**
- Must display simultaneously: current speed, HR with zone color, cadence, elapsed time, distance, radar arc, and live map
- All safety-critical elements (radar arc, alert states) must occupy positions that do not require the rider to search the screen
- Live map must show current position and heading; north-up or heading-up based on user setting
- All numeric metrics must remain legible in direct sunlight (WCAG AA minimum)

**Sensor Source Indicators:**
- Each metric tile must carry a small source badge indicating the active sensor (BLE icon, Apple Watch icon, or GPS icon) so the rider can confirm their hardware is active

**Acceptance Criteria:**
- [ ] Screen renders within 100ms of ride start
- [ ] Speed updates at minimum 1Hz from active source
- [ ] HR updates reflected within 2 seconds of sensor reading
- [ ] Cadence updates at minimum 1Hz from active source
- [ ] Radar arc updates within 500ms of BLE data arrival
- [ ] Live map updates position at minimum 1Hz
- [ ] All text meets WCAG AA in both light and dark mode
- [ ] Dashboard is operable with one gloved tap for pause

---

### 8.2 Radar Visualization

**Purpose:** Represent the approaching-vehicle threat state visually on the ride dashboard without requiring cognitive parsing.

**Design:** A semi-circular arc at the bottom of the dashboard representing the road behind the rider. Vehicles appear as dots on the arc positioned by relative distance. Dot color maps to closing speed severity. Full visual specification in UX.md (S05).

**Target Devices:** Garmin Varia RTL515 and RCT715.

> **Note on RVR820:** The Garmin Varia RVR820 uses a proprietary secure protocol over BLE that is not publicly documented and cannot be reliably targeted. Integration is not planned for any phase.

**Dot Color Mapping:**
| Closing Speed Differential | Color Token | Meaning |
|---|---|---|
| Stationary / receding | `brRatingGood` | Safe |
| < 30 km/h differential | `brRatingOkay` | Caution |
| ≥ 30 km/h differential | `brRatingBad` | Danger |

**Data Requirements from RTL515 / RCT715:**
- Alert level (0–3: clear, advisory, caution, danger)
- Vehicle count (0–8)
- Per-vehicle: relative distance (meters), closing speed delta (km/h)

**Acceptance Criteria:**
- [ ] Arc renders correctly with 0 vehicles (empty / safe state)
- [ ] Arc renders correctly with 1–8 vehicles
- [ ] Dot position animates smoothly as vehicle approaches (no jump cuts)
- [ ] Color transitions animate at 0.3s ease
- [ ] No radar hardware present → arc displays "Radar not connected" gracefully
- [ ] Disconnection during active ride triggers L1 advisory haptic + status badge on dashboard

---

### 8.3 Haptic Alert System

**Purpose:** Communicate radar threat severity without requiring the rider to look at the phone.

**Three Escalation Levels:**

| Level | Trigger | Haptic Pattern | Screen Effect | Audio |
|---|---|---|---|---|
| L1 — Advisory | 1–2 vehicles, low closing speed | Single tap — `UIImpactFeedbackGenerator` `.light` | Peripheral amber tint (10% opacity overlay) | None |
| L2 — Caution | Moderate closing speed OR 3+ vehicles | Double tap `.medium`, 0.5s interval | Amber border pulse animation | None |
| L3 — Danger | Any vehicle ≥ 30 km/h closing speed | Continuous rhythmic `.heavy` at 0.3s on/off | Full-screen `brRatingBad` wash | Tone alert — overrides Silent Mode |

**Alert Rules:**
- Minimum 3 seconds between same-level re-triggers to prevent alert fatigue
- L3 alert persists until threat recedes; it is not dismissible by the rider
- Silent Mode: L3 tone uses `AVAudioSession` category `.playback` with route override to force audio through speaker. **User must opt in to Silent Mode override in Settings (S12) before this behavior activates.** Default is silent-mode-respectful.
- Phase 2: Mirror haptic pattern on Apple Watch wrist

**Acceptance Criteria:**
- [ ] L1 haptic fires within 500ms of threshold crossing
- [ ] L2 fires within 500ms
- [ ] L3 fires within 200ms (safety-critical tight budget)
- [ ] L3 tone audible at 70dB ambient noise with phone in jersey pocket
- [ ] Silent Mode override only activates when user has explicitly enabled it in S12
- [ ] All three levels fully testable with mock BLE data (no hardware required)

---

### 8.4 BLE Sensor Priority System

**Purpose:** Use the highest-fidelity available sensor for each metric, degrading gracefully to the next best source when hardware is unavailable.

**Priority Chains:**

| Metric | Priority 1 | Priority 2 | Priority 3 | Priority 4 |
|---|---|---|---|---|
| Heart Rate | BLE HR strap | Apple Watch (HealthKit stream) | — | No data |
| Speed | BLE wheel speed sensor | GPS-derived speed | — | No data |
| Distance | BLE wheel speed sensor (wheel circumference × rev count) | GPS-derived cumulative | — | No data |
| Cadence | BLE cadence sensor | — | — | No data |
| Power | BLE power meter (Phase 3) | — | — | No data |

**Switching Behavior:**
- Source switching must happen automatically when a higher-priority source connects or disconnects
- The active source badge on each metric tile updates immediately on switch
- A brief non-intrusive banner ("Switched to GPS speed — BLE sensor disconnected") displays on source switch during an active ride
- The rider is never left staring at a stale value; all metrics display "—" when no source is active

**Cadence Notes:**
- Cadence has no fallback source; if no BLE cadence sensor is paired, the cadence tile displays "--" with a "Pair Sensor" affordance (tapping navigates to S11)
- Cadence is recorded as 0 in GPX export when no sensor is present for that track point

**Acceptance Criteria:**
- [ ] HR switches from BLE strap to Apple Watch within 5 seconds of strap disconnection
- [ ] Speed switches from BLE sensor to GPS within 5 seconds of sensor disconnection
- [ ] Source badge updates correctly on all transitions
- [ ] Banner notification appears on source switch during active ride
- [ ] GPX export correctly records the active source for each track point (see §10 and Appendix B)

---

### 8.5 Heart Rate Zone Integration

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

**HR Profile Data Source:**
- `maxHeartRate` and `restingHeartRate` are read from **Apple Health** at app launch and at the start of each ride
- If Apple Health does not have these values, the user is prompted to enter them manually in S03 / S13
- App-stored values are always considered overrides; Apple Health is the source of truth unless the user has manually overridden

**Color Mapping:**
| Zone | Token | Hex (Light) |
|---|---|---|
| Zone 1 | `brHRZone1` | `#90CAF9` |
| Zone 2 | `brHRZone2` | `#1976D2` |
| Zone 3 | `brHRZone3` | `#60BD10` |
| Zone 4 | `brHRZone4` | `#F57C00` |
| Zone 5 | `brHRZone5` | `#D32F2F` |

**Acceptance Criteria:**
- [ ] App reads `maxHeartRate` and `restingHeartRate` from HealthKit on ride start
- [ ] Falls back to manually entered profile values when HealthKit values are unavailable
- [ ] Zone calculated correctly for all 5 zones given arbitrary Max HR / Resting HR inputs (unit tested)
- [ ] Zone color updates on dashboard within 2 seconds of new HR reading
- [ ] App functions normally when HealthKit permission is denied (HR zone tile shows "No HR Source")

---

### 8.6 Navigation and Live Map (MVP)

**Purpose:** Provide a live map view on the active ride dashboard showing current position and heading. Provide basic turn-by-turn navigation for pre-planned routes.

**Live Map (MVP):**
- Embedded `MapKit` view within the dashboard (lower portion of screen; see UX.md S05)
- Updates position at minimum 1Hz using `CoreLocation`
- Heading-up orientation by default; user-toggleable to north-up
- No base-map download required; uses standard MapKit tile cache
- During L3 radar alert, map view may be obscured by full-screen alert wash — this is acceptable given the safety priority

**Turn-by-Turn Navigation (MVP):**
- Rider can load a route (GPX file from Files app, or draw a simple point-to-point)
- Route overlaid on live map as a polyline in `brPrimary` color
- Turn notifications: audio tone + banner at configurable distance (100m / 200m / 300m from turn)
- No recalculation in MVP; if the rider goes off-route, a "Off route" banner displays with no auto-reroute

**Acceptance Criteria:**
- [ ] Map renders current position within 5 seconds of ride start (GPS lock)
- [ ] Position updates smoothly at 1Hz minimum with no jumping
- [ ] Route overlay renders correctly from imported GPX file
- [ ] Turn notification fires within ±10m of configured distance from turn
- [ ] Map remains functional when radar BLE and HR BLE are simultaneously active (no resource contention)
- [ ] Map does not drain more than an additional 5% battery per hour beyond GPS-only baseline

---

### 8.7 GPX Export with Biometric Track Point Extensions

**Purpose:** Produce a standards-compliant GPX 1.1 file for every ride with full per-point biometric data: heart rate, cadence, speed, and power (when available). Files are stored in a location accessible via the iOS Files app.

**GPX Version:** 1.1  
**Extension Schema:** `gpxtpx:TrackPointExtension` v2  
**Namespace:** `http://www.garmin.com/xmlschemas/TrackPointExtension/v2`

**Per Track Point Data:**
| Field | Source | GPX Element |
|---|---|---|
| Latitude, Longitude | CoreLocation | `<trkpt lat="..." lon="...">` |
| Elevation | CoreLocation altitude | `<ele>` |
| Timestamp | System clock (UTC) | `<time>` |
| Heart Rate | Active HR source (BPM) | `<gpxtpx:hr>` |
| Cadence | BLE cadence sensor (RPM) | `<gpxtpx:cad>` |
| Speed | Active speed source (m/s) | `<gpxtpx:speed>` |
| Power | BLE power meter (Watts, Phase 3) | `<gpxtpx:power>` |

**Recording Rate:** Track points recorded at 1Hz. Fields that have no active source at a given second record as absent (element omitted, not zero) to distinguish "no sensor" from "zero value."

**File Naming Convention:** `Cyclometer_YYYY-MM-DD_HH-mm.gpx`

**Storage:** Files app integration via `UIFileSharingEnabled` (`Info.plist`) and `LSSupportsOpeningDocumentsInPlace`. Ride GPX files stored in the app's `Documents/Rides/` directory, which appears in Files app under "On My iPhone → Cyclometer."

**Export Trigger:** GPX file written at ride end and available immediately in Files app. Also accessible from Ride Summary screen (S10) via a Share Sheet action.

**Acceptance Criteria:**
- [ ] GPX file validates against GPX 1.1 schema
- [ ] `gpxtpx:TrackPointExtension` namespace declared correctly in file header
- [ ] HR, cadence, speed values present for each second where sensor data was active
- [ ] Fields correctly absent (not zero) for seconds with no active sensor
- [ ] File available in Files app within 5 seconds of ride end
- [ ] GPX imports correctly into Strava, Garmin Connect, and RideWithGPS (manual QA)
- [ ] File naming convention applied consistently

---

### 8.8 Ride Recording State Machine

**States:** `idle` → `active` → `paused` → `ended`

**Transitions:**
- `idle → active`: Rider taps "Start Ride"; GPS lock confirmed; all active BLE sensors confirmed
- `active → paused`: Rider taps pause; all sensor recording suspended; GPX track point emission paused
- `paused → active`: Rider taps resume; recording resumes; track point emission resumes
- `paused → ended`: Rider taps "End Ride"; ride summary generated; GPX file written
- `active → ended`: Auto-end if speed = 0 for > 5 minutes (configurable, default on)

**Acceptance Criteria:**
- [ ] All state transitions modeled as explicit TCA Actions
- [ ] Active ride state persists across app kill/relaunch (crash recovery)
- [ ] Ride data checkpointed to SwiftData every 30 seconds
- [ ] GPX file is written atomically at ride end (partial write does not produce corrupt file)

---

## 9. Hardware Integrations

### 9.1 Garmin Varia RTL515 / RCT715 — BLE Integration

**Target Devices:**
- **Garmin Varia RTL515** — Radar tail light (radar + light; no camera)
- **Garmin Varia RCT715** — Radar tail light with integrated dashcam

**Protocol:** Bluetooth Low Energy (BLE) using Garmin's cycling radar GATT profile.

> **Important:** The Garmin Varia RVR820 uses a proprietary secure BLE protocol that is not publicly documented. It is not targeted by Cyclometer in any phase.

**BLE Service and Characteristic UUIDs (RTL515 / RCT715):**
- Cycling Radar Service: `6A4E3200-667B-11E3-949A-0800200C9A66`
- Radar Alert Characteristic (notify): `6A4E3202-667B-11E3-949A-0800200C9A66`
- Radar Capability Characteristic (read): `6A4E3201-667B-11E3-949A-0800200C9A66`

> **Note:** UUIDs require validation against Garmin's BLE specification during the M2 engineering spike. Garmin's mobile SDK should also be evaluated as a potential abstraction layer over raw CoreBluetooth (see OQ2).

**Alert Payload Structure (per BLE characteristic notification):**
- Byte 0: Alert level (0 = clear, 1 = advisory, 2 = caution, 3 = danger)
- Byte 1: Vehicle count (0–8)
- Bytes 2–N: Vehicle records (see §10 RadarVehicle)

**Connection State Machine:**
```
disconnected → scanning → connecting → connected → active (notifications enabled)
                                           ↓
                                      reconnecting → connected
                                           ↓ (timeout)
                                      disconnected
```

**Reconnection Policy:**
- Auto-reconnect on signal loss with exponential backoff: 1s, 2s, 4s, 8s, 16s, max 30s
- Dashboard status badge shows disconnected state after 10 seconds without reconnect
- L1 advisory haptic fires once on unexpected disconnection during active ride

**Acceptance Criteria:**
- [ ] App discovers Varia within 10 seconds of BLE scan initiation
- [ ] Characteristic notifications parse correctly for 0–8 vehicle payloads
- [ ] Disconnection during active ride triggers status badge + advisory haptic
- [ ] All BLE operations testable with mock `BluetoothClient` (no hardware required)
- [ ] App does not crash when Bluetooth permission is denied

---

### 9.2 BLE HR Sensor (Generic)

**Protocol:** BLE Heart Rate Profile (Bluetooth SIG standard — `0x180D`)  
**Characteristic:** Heart Rate Measurement (`0x2A37`) — notify  
**Compatible devices:** Any standard BLE HR strap (Polar H10, Wahoo TICKR, Garmin HRM-Pro, etc.)

**Data:** BPM (uint8 or uint16 per flags byte), RR intervals (optional, not used in MVP)

**Acceptance Criteria:**
- [ ] Connects to any BLE HR Profile-compliant device
- [ ] BPM updates delivered to TCA state within 1 second of characteristic notification
- [ ] Graceful fallback to Apple Watch HR on disconnection (see §8.4)

---

### 9.3 BLE Speed / Cadence Sensor (Generic)

**Protocol:** BLE Cycling Speed and Cadence (CSC) Profile (Bluetooth SIG — `0x1816`)  
**Characteristic:** CSC Measurement (`0x2A5B`) — notify  
**Compatible devices:** Any BLE CSC sensor (Garmin GSC-10, Wahoo RPM, Polar speed/cadence sensors, etc.)

**Speed Calculation:**  
Speed is derived from cumulative wheel revolutions and event time stamps per the CSC specification. Requires wheel circumference configured in Settings (S12). Default: 2096mm (700c × 23mm tire).

**Cadence Calculation:**  
Derived from cumulative crank revolutions and event time stamps per CSC specification.

**Acceptance Criteria:**
- [ ] Connects to any BLE CSC Profile-compliant device
- [ ] Speed and cadence calculated correctly from cumulative revolution data
- [ ] Wheel circumference configurable in S12
- [ ] Cadence and speed independently functional when sensor provides only one (some sensors are speed-only or cadence-only)
- [ ] Graceful fallback to GPS speed on BLE speed sensor disconnection

---

### 9.4 Apple Watch / HealthKit

**HealthKit Entitlements Required:**
- `HKQuantityTypeIdentifierHeartRate` (read)
- `HKQuantityTypeIdentifierRestingHeartRate` (read)
- `HKCharacteristicTypeIdentifierDateOfBirth` (read — for max HR estimation if not available)
- `HKWorkoutType` (write — for workout session recording in Phase 2)

**Profile Data Read at Onboarding and Ride Start:**
- `restingHeartRate` → `HKQuantityTypeIdentifierRestingHeartRate`
- `maxHeartRate` → `HKQuantityTypeIdentifierHeartRate` (historical max, or age-based estimate: 220 − age)
- These values populate the Karvonen zone calculation and update if Apple Health values change

**HR Streaming During Ride:**
- Use `HKAnchoredObjectQuery` with live updates when Apple Watch is the active HR source
- Fallback: Apple Watch is secondary to BLE HR strap (see §8.4)

**Acceptance Criteria:**
- [ ] App correctly reads `restingHeartRate` and `maxHeartRate` from HealthKit on ride start
- [ ] Falls back to age-based max HR estimate (220 − age) if HealthKit max HR is unavailable
- [ ] App functions with HealthKit permission denied (HR zone tile shows "No HR Source")
- [ ] HR stream from Apple Watch feeds zone display within 2 seconds

---

### 9.5 ENGO 2 / ActiveLook AR Glasses (Phase 3)

**SDK:** ActiveLook iOS SDK  
**Protocol:** BLE  
**Display:** Monochrome HUD, ~300×256px effective area

**Planned HUD Layout:**
- Speed (large, center)
- HR zone indicator (zone number + brightness-coded bar)
- Radar alert icon (right edge — brightness escalates with alert level; color-independent for monochrome display)

**Constraints:**
- Monochrome display requires icon-based encoding for alert severity (not color-dependent)
- HUD updates capped at 1Hz to preserve BLE bandwidth
- Full AR spec to be written as a separate Phase 3 document

---

## 10. Data Model

### SwiftData Schema

> **Persistence:** SwiftData (iOS 17+). All ride data, sensor samples, and user profile data stored in SwiftData. GPX export produced from SwiftData records at ride end.

---

### Ride

```swift
@Model class Ride {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var distance: Double               // meters; from active speed source
    var duration: TimeInterval
    var averageSpeed: Double           // m/s
    var maxSpeed: Double               // m/s
    var averageHeartRate: Int?         // bpm; nil if no HR source
    var maxHeartRate: Int?             // bpm; nil if no HR source
    var averageCadence: Int?           // rpm; nil if no cadence sensor
    var hrZoneDurations: [Int: TimeInterval] // zone (1–5) → seconds in zone
                                             // calculated at ride end from HRSamples
    var radarEventCount: Int
    var gpxFileURL: URL?               // reference to exported GPX in Documents/Rides/
    var trackPoints: [TrackPoint]      // relationship
    var radarEvents: [RadarEvent]      // relationship
}
```

---

### TrackPoint

> Replaces the simple `CLLocation` array from v0.1. Each TrackPoint correlates location with all active biometric readings at that second. This is the source of truth for GPX export.

```swift
@Model class TrackPoint {
    var id: UUID
    var rideId: UUID
    var timestamp: Date
    
    // Location
    var latitude: Double
    var longitude: Double
    var altitude: Double               // meters
    var horizontalAccuracy: Double     // meters
    
    // Speed — from active source
    var speed: Double?                 // m/s; nil if no source active
    var speedSource: SensorSource      // .bleWheel | .gps
    
    // Heart Rate — from active source
    var heartRateBPM: Int?             // nil if no HR source active
    var heartRateSource: SensorSource  // .bleHR | .appleWatch | .none
    
    // Cadence — BLE only (no fallback)
    var cadenceRPM: Int?               // nil if no cadence sensor active
    
    // Power — Phase 3; nil until power meter support added
    var powerWatts: Int?
}

enum SensorSource: String, Codable {
    case bleHR
    case bleWheel
    case bleCadence
    case blePower
    case appleWatch
    case gps
    case none
}
```

> **Note on HR Zone in TrackPoint:** Zone is **not** stored on `TrackPoint`. Zone is a derived value: `zone = karvonen(bpm, profile.restingHR, profile.maxHR)`. It is computed at query time from the stored BPM and the current user profile. Storing zone would create data inconsistency if the user updates their HR profile post-ride. For GPX export, zone is not part of the `gpxtpx:TrackPointExtension` schema; only raw BPM is exported.

---

### RadarEvent

```swift
@Model class RadarEvent {
    var id: UUID
    var rideId: UUID
    var timestamp: Date
    var vehicleCount: Int
    var alertLevel: AlertLevel         // .clear | .advisory | .caution | .danger
    var vehicles: [RadarVehicle]
}

enum AlertLevel: Int, Codable, Comparable {
    case clear     = 0
    case advisory  = 1
    case caution   = 2
    case danger    = 3
}
```

---

### RadarVehicle

> Prepared for RTL515 / RCT715 data. Vehicle size classification is flagged below.

```swift
struct RadarVehicle: Codable {
    var vehicleIndex: Int              // 1–8 per Varia protocol
    var distanceMeters: Double         // relative distance behind rider
    var closingSpeedKph: Double        // positive = approaching; negative = receding
    var alertLevel: AlertLevel         // per-vehicle threat level
    
    // Vehicle size classification:
    // The RTL515 and RCT715 are Doppler-based radar units. They do not natively
    // classify vehicle size (car vs. truck vs. motorcycle). Size classification
    // would require inference from radar return signal strength, which is not
    // exposed in the current BLE characteristic payload.
    //
    // This field is reserved for a future firmware update or SDK capability.
    // Set to .unknown for all vehicles in MVP.
    var estimatedSize: VehicleSize
}

enum VehicleSize: String, Codable {
    case unknown       // default — radar does not classify in current protocol
    case small         // reserved (motorcycle / bicycle)
    case medium        // reserved (car / SUV)
    case large         // reserved (truck / bus)
}
```

> **Engineering Note (OQ-New):** Confirm with Garmin's BLE spec or SDK whether signal return amplitude is exposed in any characteristic that could be used to infer vehicle size. If not, `VehicleSize` remains `.unknown` indefinitely for RTL515/RCT715 unless Garmin adds classification to firmware. Document finding in OQ11.

---

### UserProfile

```swift
@Model class UserProfile {
    var id: UUID
    
    // HR Profile — sourced from Apple Health; manual override available in S13
    // Read from HealthKit at app launch and at each ride start.
    // Apple Health is the source of truth; manual values are fallback only.
    var restingHeartRate: Int          // bpm; from HKQuantityTypeIdentifierRestingHeartRate
    var maxHeartRate: Int              // bpm; from historical HK max HR or 220 − age estimate
    var heartRateSourceIsAppleHealth: Bool  // true = pulled from HK; false = manually entered
    var dateOfBirth: DateComponents?   // read from HK for age-based max HR estimate
    
    // Preferences
    var preferredUnit: UnitSystem      // .metric | .imperial
    var wheelCircumferenceMM: Int      // default 2096 (700c × 23mm)
    var mapOrientation: MapOrientation // .headingUp | .northUp
    var navigationTurnDistanceM: Int   // 100 | 200 | 300 — turn alert distance
    
    // Alert Settings
    var hapticIntensity: HapticIntensity    // .light | .medium | .heavy (scales all levels)
    var audioAlertsEnabled: Bool
    var overrideSilentModeForL3: Bool       // user must explicitly enable; default false
    var dangerThresholdKph: Double          // default 30; closing speed that triggers L3
    var cautionVehicleCountThreshold: Int   // default 3; vehicle count that triggers L2

    // BLE Sensor Configuration
    var pairedRadarIdentifier: UUID?
    var pairedHRSensorIdentifier: UUID?
    var pairedSpeedCadenceSensorIdentifier: UUID?
}

enum UnitSystem: String, Codable { case metric, imperial }
enum MapOrientation: String, Codable { case headingUp, northUp }
enum HapticIntensity: String, Codable { case light, medium, heavy }
```

---

## 11. Architecture

### Pattern: The Composable Architecture (TCA)

**Rationale:** Cyclometer has multiple concurrent real-time data streams (BLE radar, BLE HR, BLE speed/cadence, HealthKit, CoreLocation), safety-critical alert logic that must be fully unit-testable without hardware, and planned multi-target expansion (Apple Watch, AR glasses). TCA's explicit state management, side-effect isolation via `Effect`, dependency injection via `@Dependency`, and `TestStore` make it the strongest architectural fit.

**TCA Dependency Clients:**
```swift
// All hardware dependencies are protocol-based for full testability
@DependencyClient struct BluetoothClient      // Varia BLE, HR BLE, CSC BLE
@DependencyClient struct HealthKitClient      // HR streaming, profile reads
@DependencyClient struct LocationClient       // GPS, map position
@DependencyClient struct HapticClient         // Haptic engine
@DependencyClient struct AudioAlertClient     // Tone alerts
@DependencyClient struct PersistenceClient    // SwiftData operations
@DependencyClient struct NavigationClient     // Route loading, turn calculations
```

**Feature Decomposition:**
```
AppFeature
├── OnboardingFeature
│   ├── WelcomeFeature
│   ├── SensorPairingFeature
│   └── ProfileSetupFeature
├── HomeFeature
├── ActiveRideFeature                   ← Primary feature
│   ├── RadarFeature                    ← BLE stream, alert level logic
│   ├── HeartRateFeature                ← BLE HR + HealthKit fallback, zone calc
│   ├── SpeedCadenceFeature             ← BLE CSC + GPS fallback
│   ├── NavigationFeature               ← MapKit, route overlay, turn alerts
│   ├── TrackPointRecorderFeature       ← 1Hz track point assembly + GPX write
│   └── AlertOrchestratorFeature        ← Combines all streams → haptic/audio/screen
├── RideHistoryFeature
├── RideDetailFeature
└── SettingsFeature
    ├── DeviceSettingsFeature
    ├── HRZoneSettingsFeature
    └── AlertSettingsFeature
```

**Project Folder Structure:**
```
Cyclometer/
├── App/
│   ├── CyclometerApp.swift
│   └── AppFeature.swift
├── Features/
│   ├── ActiveRide/
│   ├── Radar/
│   ├── HeartRate/
│   ├── SpeedCadence/
│   ├── Navigation/
│   ├── TrackPointRecorder/
│   ├── AlertOrchestrator/
│   ├── Onboarding/
│   ├── RideHistory/
│   └── Settings/
├── Clients/
│   ├── BluetoothClient.swift
│   ├── HealthKitClient.swift
│   ├── LocationClient.swift
│   ├── HapticClient.swift
│   ├── AudioAlertClient.swift
│   ├── NavigationClient.swift
│   └── PersistenceClient.swift
├── Models/
│   ├── Ride.swift
│   ├── TrackPoint.swift
│   ├── RadarEvent.swift
│   ├── RadarVehicle.swift
│   └── UserProfile.swift
├── Export/
│   └── GPXExporter.swift              ← Assembles GPX from SwiftData records
├── DesignSystem/
│   ├── Color+Cyclometer.swift
│   ├── Typography.swift
│   └── Components/
└── Tests/
    ├── RadarFeatureTests.swift
    ├── HeartRateFeatureTests.swift
    ├── SpeedCadenceFeatureTests.swift
    ├── AlertOrchestratorTests.swift
    ├── TrackPointRecorderTests.swift
    ├── GPXExporterTests.swift
    └── RideRecordingTests.swift
```

---

## 12. Non-Functional Requirements

### Performance
- Active ride dashboard: 60fps render target; no dropped frames during simultaneous BLE + GPS + HealthKit updates
- BLE characteristic processing: < 50ms from receipt to state update
- App cold launch to ready-to-ride: < 3 seconds
- Memory footprint: < 120MB during active ride on iPhone 13 or later (increased from v0.1 due to MapKit addition)

### Battery
- Active ride session: < 15% battery drain per hour (iPhone 14 baseline, screen-on navigation included)
- GPS: `CLLocationManager` with `allowsBackgroundLocationUpdates = true`; `pausesLocationUpdatesAutomatically = false`
- BLE: connection-based characteristic notification (not continuous scan) after pairing

### Reliability
- Active ride state survives app backgrounding, phone calls, and iOS memory pressure events
- Ride data not lost on crash: SwiftData checkpoint every 30 seconds
- GPX file written atomically at ride end; partial writes do not produce corrupt files
- Radar alert L3 must not be skipped even if the UI thread is momentarily busy (dispatched on a high-priority queue)

### Accessibility
- VoiceOver: supported on all non-ride screens; suspended during active ride (cycling context)
- Dynamic Type: supported on all screens
- Minimum tap target: 44×44 pt on all active ride controls (Apple HIG)
- High contrast: tested with iOS Increase Contrast enabled

### Privacy
- HealthKit data: read-only; no data transmitted to any server
- GPS and ride data: stored locally only; no server upload without explicit user action
- BLE device identifiers: not transmitted externally
- No analytics or crash reporting without explicit user consent
- Files app access: read/write to `Documents/Rides/` only; no access to other apps' data

### Localization (MVP)
- English only at launch
- Unit system: metric / imperial toggle in UserProfile
- Date/time: respects device locale
- GPX timestamps: UTC per GPX 1.1 spec

### Platform
- iOS 17.0 minimum
- iPhone only (no iPad support)
- No Mac Catalyst

---

## 13. Phased Milestones

### Phase 1 — MVP (Target: 3 months)

| Milestone | Deliverable |
|---|---|
| M1 | Xcode project scaffold; TCA + SwiftData; CI/CD via GitHub Actions |
| M2 | BLE client — Varia RTL515/RCT715 connect + parse + mock; HR Profile; CSC Profile |
| M3 | Active Ride Dashboard — speed, cadence, time, distance (no radar, no HR) |
| M4 | Radar visualization; haptic alerts L1–L3; Silent Mode override |
| M5 | HealthKit integration; HR zone display; BLE HR fallback to Apple Watch |
| M6 | BLE CSC speed/cadence; GPS fallback for speed |
| M7 | TrackPoint recording; GPX export with `gpxtpx:TrackPointExtension`; Files app integration |
| M8 | Navigation: live map on dashboard; route overlay; turn alerts |
| M9 | Ride summary screen; ride data persistence in SwiftData |
| M10 | Settings, device management, onboarding flow |
| M11 | QA; TestFlight open beta; bug fixes |
| M12 | App Store submission |

### Phase 2 — Companion & History (Target: +2 months post-launch)
Ride history + detail view, Apple Watch app + complication, Dynamic Island, HR/cadence graphs, Strava/Garmin export.

### Phase 3 — AR, Power & Platform (Target: +4 months post-Phase 2)
Power meter BLE support, ENGO 2 / ActiveLook AR integration, route planning, segment detection.

---

## 14. Open Questions

| # | Question | Owner | Priority | Status |
|---|---|---|---|---|
| OQ1 | SwiftData vs CoreData? | Engineering | High | ✅ **Resolved: SwiftData** |
| OQ2 | Does Garmin's mobile SDK provide a cleaner Varia BLE path than raw CoreBluetooth? Evaluate in M2 spike. | Engineering | High | Open |
| OQ3 | iPad support? | Product | Low | ✅ **Resolved: No iPad** |
| OQ4 | Audio alert delivery: tones vs synthesized voice? | Design | Medium | ✅ **Resolved: Tones** |
| OQ5 | Override Silent Mode for L3 danger alerts? | Design | High | ✅ **Resolved: Yes, user opt-in in Settings** |
| OQ6 | App name for App Store? | Product | Medium | ✅ **Resolved: Cyclometer** |
| OQ7 | Minimum Varia RTL515 / RCT715 firmware version required for BLE characteristic support? Confirm in M2. | Engineering | High | Open |
| OQ8 | Include basic Apple Watch complication in Phase 1? | Product | Medium | ✅ **Resolved: Defer to Phase 2** |
| OQ9 | HR zone formula: Karvonen-only or allow custom percentages in MVP? | Design | Low | ✅ **Resolved: Karvonen-only** |
| OQ10 | TestFlight beta: open or closed? | Product | Low | ✅ **Resolved: Open beta** |
| OQ11 | Does Garmin Varia RTL515/RCT715 expose radar return signal amplitude over BLE for vehicle size inference? | Engineering | Medium | Open — confirm in M2 spike |
| OQ12 | Navigation: For MVP turn-by-turn, use `MKDirections` (Apple Maps routing) or require rider to import pre-planned GPX route only? | Design | Medium | Open |
| OQ13 | What wheel circumference presets should be included in Settings? (Common tire sizes: 700c × 23/25/28/32mm, 650b, 29er MTB) | Design | Low | Open |

---

## 15. Out of Scope

| Item | Rationale |
|---|---|
| **Garmin Varia RVR820** | Proprietary secure BLE protocol; not publicly documented |
| **ANT+ direct support** | iOS hardware does not support ANT+; Garmin SDK evaluated as bridge only (OQ2) |
| **SRAM AXS / electronic shifting** | No public write API; read-only ANT+ profile is low-value |
| **Power meter support** | Phase 3 (BLE power meters); pending ANT+ feasibility via SDK |
| **Live ride sharing** | Requires server infrastructure; out of scope for local-first MVP |
| **Coaching / AI training plans** | Separate product consideration |
| **Android** | iOS-only; no cross-platform framework |
| **Web dashboard** | No server component planned |
| **Social / community features** | No social graph in any current phase |
| **iPad** | iPhone-only by product decision |
| **Mac Catalyst** | Not planned |
| **Auto-reroute navigation** | MVP shows "Off route" banner only; full rerouting deferred |

---

## 16. Appendix A — Design Tokens

The Cyclometer color system is a 30-token system in 7 categories. Full specification in `BikeRider-ColorSystem.md`. Safety-critical and zone tokens:

| Token | Light Mode | Dark Mode | Usage |
|---|---|---|---|
| `brRatingBad` | `#D32F2F` | `#EF5350` | L3 danger alert, Zone 5 |
| `brRatingOkay` | `#ED8B00` | `#FFB020` | L2 caution alert |
| `brRatingGood` | `#2E8B08` | `#60BD10` | Clear / safe state |
| `brHRZone1` | `#90CAF9` | `#64B5F6` | Recovery |
| `brHRZone2` | `#1976D2` | `#42A5F5` | Endurance |
| `brHRZone3` | `#60BD10` | `#6FD11E` | Tempo (brand green) |
| `brHRZone4` | `#F57C00` | `#FFA726` | Threshold |
| `brHRZone5` | `#D32F2F` | `#EF5350` | VO2 Max |
| `brPrimary` | `#60BD10` | `#6FD11E` | Brand, CTAs, active states |

---

## 17. Appendix B — GPX TrackPoint Extension Schema

Every ride exports a GPX 1.1 file with the following structure. The `gpxtpx:TrackPointExtension` namespace is declared in the `<gpx>` root element.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1"
     creator="Cyclometer iOS"
     xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v2"
     xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
     xsi:schemaLocation="
       http://www.topografix.com/GPX/1/1
       http://www.topografix.com/GPX/1/1/gpx.xsd
       http://www.garmin.com/xmlschemas/TrackPointExtension/v2
       http://www.garmin.com/xmlschemas/TrackPointExtensionv2.xsd">

  <metadata>
    <name>Cyclometer_2026-03-31_08-15</name>
    <time>2026-03-31T08:15:00Z</time>
  </metadata>

  <trk>
    <name>Morning Ride</name>
    <trkseg>

      <trkpt lat="36.0726" lon="-79.7920">
        <ele>220.1</ele>
        <time>2026-03-31T08:15:01Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>142</gpxtpx:hr>       <!-- BPM; omitted if no HR source -->
            <gpxtpx:cad>85</gpxtpx:cad>      <!-- RPM; omitted if no cadence sensor -->
            <gpxtpx:speed>7.2</gpxtpx:speed> <!-- m/s; omitted if no speed source -->
            <!-- gpxtpx:power omitted in MVP; present in Phase 3 when power meter active -->
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>

      <!-- Track points continue at 1Hz for ride duration -->
      <!-- Elements are OMITTED (not zero) when their sensor source is inactive -->

    </trkseg>
  </trk>
</gpx>
```

**Schema Notes:**
- `gpxtpx:speed` is in **m/s** per the TrackPointExtension v2 schema
- `gpxtpx:cad` is **RPM** (crank revolutions per minute)
- `gpxtpx:hr` is integer **BPM**
- `gpxtpx:power` is integer **Watts** (Phase 3; element omitted in MVP)
- Elements are **omitted** (not zero-valued) when no sensor is active, preserving the distinction between "zero cadence" and "no cadence sensor"

---

*Cyclometer PRD v0.2 · Second Review Draft · 2026-03-31*
