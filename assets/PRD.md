# Cyclometer — Product Requirements Document
**Version:** 0.4.4 Draft  
**Date:** 2026-08-14  
**Status:** Fourth Review  
**Author:** Brian (UX Design) + Claude (Specification)  
**Platform:** iOS 26+ · iPhone-first · Apple Watch companion  
**App Name:** Cyclometer

---

## Revision History

| Version | Date | Author | Changes |
|---|---|---|---|
| 0.1 | 2026-03-30 | Brian / Claude | Initial draft |
| 0.2 | 2026-03-31 | Brian / Claude | Radar device corrected to RTL515/RCT715; BLE sensor priority for HR/speed/cadence; power meter to Phase 3; navigation to MVP; data model corrections; GPX export with gpxtpx:TrackPointExtension; resolved OQ1,3,4,5,6,8,9,10; app renamed Cyclometer |
| 0.2.1 | 2026-04-05 | Brian / Claude | Updated all design asset paths to reflect new `assets/design/` folder structure; corrected color token reference; added Appendix C — Design Assets |
| 0.3 | 2026-04-05 | Brian / Claude | Corrected Cadence competitive row (navigation ✅, ActiveLook AR ✅); three-tone audio system (All Clear, Warning, Danger) — spec in `Audio.md`; radar visualization brainstorming added; radar hidden when no device paired; haptic brainstorming added; route planning expanded to GPX import + tribos.studio; vehicle pass event recording added to GPX and data model; resolved OQ12 (GPX import only), OQ13 (presets + manual + auto-calibration); wheel auto-calibration spec added |
| 0.4 | 2026-05-20 | Brian / Claude | iOS minimum updated to 26.0; S05.4, S05.5, S19, S20 added to screen inventory; OQ14 resolved (Option F sidebar); L3 haptic updated to Core Haptics; Routes tab added and promoted to Phase 2; deferred alert-configuration fields removed from UserProfile |
| 0.4.1 | 2026-06-12 | Brian / Claude | OQBLE1 resolved (separate Speed/Cadence roles per `BLE.md`); M6 milestone wording clarified — CSC client is built in M2 (#20), M6 wires it into the metrics pipeline; wheel circumference presets + manual entry moved from M10 to M6 to align with GitHub milestone scoping |
| 0.4.2 | 2026-07-07 | Brian / Claude | Milestone execution order re-sequenced: M3 -> M6 -> M10 -> M4 -> M5 -> M7-M12; GitHub milestone due dates updated to match; minimal BLE pairing sheet + CSC role assignment pulled forward into M6 (full S11 device management remains in M10); M6 issue set created (#65-#72) |
| 0.4.4 | 2026-08-14 | Brian / Claude | M10 scope pass. S11 corrected to the flat device list in `Design.sketch` (no role sections); one sensor per role confirmed, with a replace-or-cancel prompt on collision; S12 loses Set Do Not Disturb (no public iOS API for enabling a Focus) and defers Accounts to Phase 2; wheel size becomes a navigation row to a detail screen; S01 drops the Files permission (there is no such prompt) and requests Location When In Use, escalating to Always at first ride start; HR zone entry moves to a manually entered `RiderProfile` in M10, HealthKit-sourced in M5; route service integrations follow Accounts to Phase 2, leaving GPX file import as the MVP source; M10 issue set created. Version 0.4.3 is the wheel auto-calibration revision on `feat/70-wheel-auto-calibration`, unmerged at the time of writing |
| 0.4.5 | 2026-08-17 | Brian / Claude | §8.5 corrected: **HealthKit has no max-heart-rate type**, so max HR comes from the 220 − age estimate or manual entry, never from a `.discreteMax` query over historical samples. §9.4 acceptance criteria updated to match. `RiderProfile` (#96) narrowed to storing HR *overrides* only — resting HR and date of birth stay HealthKit's, resolution is `override ?? healthKit ?? default` at read time — which makes §8.5's long-standing "app-stored values are always considered overrides" literally true rather than aspirational |

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
18. [Appendix C — Design Assets](#18-appendix-c--design-assets)

---

## 1. Product Vision

Cyclometer is a **safety-first cycling companion for iPhone and Apple Watch** that synthesizes real-time sensor data — rear radar, heart rate, speed, cadence, GPS, and optionally power — into an eyes-free, glanceable riding experience optimized for outdoor conditions. The app treats radar visualization and safety alerting as first-class architectural concerns: every design decision, interaction pattern, and data priority is evaluated through the lens of a rider who cannot safely look at a screen.

The central insight: **a cycling computer's most critical job is not to display data — it's to keep the rider alive when something dangerous is approaching from behind.**

Cyclometer records every ride as an industry-standard GPX file with full `gpxtpx:TrackPointExtension` data — heart rate, cadence, speed, and power correlated per track point — available directly in the iOS Files app and exportable to any compatible platform. Vehicle pass events are also recorded as GPX waypoints using a custom `cyc:` namespace, enabling post-ride traffic analysis.

The Cyclometer dashboard is not a static screen — it is a **rider-configured instrument panel**. The design philosophy is borrowed from professional cycling computers and adapted for the iPhone form factor: the rider decides which data matters to them, at what prominence, on how many pages. The app’s role is to make that configuration effortless and to make every widget instantly readable mid-ride, in sunlight, at a glance.

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
The Garmin Varia RTL515 and RCT715 expose real-time radar alert data over BLE. Cyclometer's opportunity is to make that data immediately useful **without requiring the rider to look at the phone** — through progressive haptic escalation, peripheral color cues, a three-tone audio alert system (All Clear, Warning, Danger), and future Apple Watch and AR glasses integration. Combined with rich BLE sensor integration (HR, speed, cadence) and standards-based GPX export with vehicle pass event recording, Cyclometer replaces a dedicated cycling computer for the majority of cyclists.

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

| App | Radar Support | AR Glasses | HR Zones | Eyes-Free | Navigation | GPX Export |
|---|---|---|---|---|---|---|
| **Cadence (Seven Bold)** | ✅ Best-in-class | ✅ ActiveLook | ✅ Full | ❌ | ✅ Mapbox turn-by-turn + GPX import | ❌ (TCX only) |
| **Wahoo ELEMNT** | ✅ (hardware only) | ❌ | ✅ | Partial | ✅ | ✅ |
| **Strava** | ❌ | ❌ | Basic | ❌ | Limited | ✅ |
| **Garmin Connect Mobile** | ✅ (own device) | ❌ | ✅ | ❌ | ✅ | ✅ |
| **Cyclometer** | ✅ First-class | ✅ Phase 3 | ✅ Zone-aware | ✅ Core design | ✅ GPX import MVP | ✅ GPX+ext+vehicle pass |

**Key differentiator:** Cyclometer is the only app designed from the ground up around eyes-free interaction patterns as a primary design constraint, with a complete three-tone audio alert system (including a deliberate All Clear tone that Cadence lacks), full-fidelity GPX export with per-point biometric correlation, and vehicle pass event recording.

**Cadence correction (v0.2 had this wrong):** Cadence does have routing and navigation (Mapbox-powered turn-by-turn, GPX import, route saving from activities) and does support ActiveLook AR glasses. These are feature-complete implementations and represent a meaningful competitive benchmark.

---

## 5. Design Principles

### P1 — Eyes-Free First
Every safety-critical interaction must work without the rider looking at the screen. Haptics, audio, and peripheral color cues are primary. The screen is secondary for safety events.

### P2 — Glanceability
When the rider does look, information must be parsed in under one second. Large numerics, high-contrast colors, and strict information hierarchy are non-negotiable.

### P3 — Sunlight Legibility
The app operates in direct sunlight. All color choices must meet WCAG AA contrast ratios under bright ambient conditions. Saturated hues (not pastel) for safety-critical states.

### P4 — Progressive Escalation
Radar alerts must escalate proportionally to threat severity. A distant vehicle warrants a gentle haptic pulse. A rapidly closing vehicle warrants an audio alert.

### P5 — Sensor Hierarchy with Graceful Degradation
For every metric, the highest-fidelity source is preferred. The app degrades gracefully when any sensor is unavailable, always using the best available source. The rider is never blocked by missing hardware.

### P6 — Standards-Based Data Portability
Ride data is the rider's data. Every ride exports as a standards-compliant GPX file with biometric extensions and vehicle pass events. No proprietary formats, no lock-in.

### P7 — Minimal Interaction During Ride
Controls must be large enough to tap without looking. The active ride screen must require zero navigation to reach the most critical information.

---

## 6. Feature Scope

### MVP (Phase 1)
- Active ride dashboard — speed, HR, cadence, elapsed time, distance, live map
- Garmin Varia RTL515 / RCT715 BLE radar integration with sidebar visualization (hidden when no radar device is paired)
- Three-tone audio alert system: All Clear, Warning, Danger (spec: `Audio.md`)
- BLE sensor priority system — HR strap, speed/cadence sensor, with Apple Watch and GPS as fallbacks
- Heart rate zone display (Zones 1–5) via BLE HR sensor or Apple Watch / HealthKit
- Watch haptic alert system (3 escalation levels) with Silent Mode override for Danger
- GPS track recording with live map view
- Route loading from GPX file import (Files app) or tribos.studio integration
- GPX export with `gpxtpx:TrackPointExtension` (HR, cadence, speed per track point) and `cyc:VehiclePassEvent` waypoints
- GPX files available in iOS Files app
- Basic ride summary (post-ride)
- BLE device pairing and management screen
- Wheel circumference with preset sizes, manual entry, and GPS auto-calibration
- Settings screen
- Open TestFlight beta

### Phase 2
- Routes tab (S19, S20): route list with list and map views, route detail with elevation profile, current weather, Strava segments, and previous ride history
- Ride history (S14) with map replay and vehicle pass event visualization
- Ride detail view (S15): HR graph, cadence graph, radar event + vehicle pass timeline
- Heart rate zone training graphs
- Customizable metric tiles on dashboard (S07, S08)
- **Multi-bike management:** a rider owns several bikes; each bike owns its speed/cadence/radar sensors and maps to a Strava gear id for export. Wheel circumference lives on the speed sensor (§8.9.1). Heart rate stays rider-scoped. Includes the bike picker in the Start Sheet (S05.1/S05.2) and ride history that names the bike ridden. Data model in DataModel.md §3.9
- Route picker in Start Sheet (S05.2)
- Lock screen / Dynamic Island integration
- Apple Watch standalone companion app and complication (S17)
- Cadence + HR data visualization on ride detail screen
- Strava / Garmin Connect export

### Phase 3
- Power meter BLE support (ANT+ bridge via Garmin SDK if viable; BLE power meters natively)
- ENGO 2 / ActiveLook AR glasses integration (S18)
- Segment detection

### Resolved Decisions (cumulative)
- **Persistence:** SwiftData (iOS 26+ minimum target confirmed)
- **Platform:** iPhone only; no iPad support
- **Audio alerts:** Three tones — All Clear, Warning, Danger. Full spec in `Audio.md`.
- **Silent Mode:** Danger tone overrides with user opt-in; Warning and All Clear always respect Silent Mode
- **App name:** Cyclometer
- **Apple Watch:** Deferred to Phase 2
- **HR zone formula:** Karvonen only in MVP
- **TestFlight:** Open beta
- **Navigation (OQ12):** GPX file import only for MVP; no `MKDirections` routing
- **Wheel sizing (OQ13):** Preset common sizes + manual entry + GPS auto-calibration (see §8.9). One app-wide value for MVP; Phase 2 moves it onto the speed sensor, which is bound to one wheel (see §8.9.1 and DataModel.md §3.9)
- **Radar visualization (OQ14):** Option F — right-side sidebar strip (see §8.2)

---

## 7. Screen Inventory

| ID | Screen | Phase | Description |
|---|---|---|---|
| S01 | Onboarding — Welcome | MVP | App intro, permission requests (BLE, HealthKit, Location, Files) |
| S02 | Onboarding — Sensor Pairing | MVP | BLE scan + pair radar, HR strap, speed/cadence sensor |
| S03 | Onboarding — Profile Setup | Cut | Age; pulls Max HR and Resting HR from Apple Health if available |
| S04 | Home | Deferred | Pre-ride summary; last ride, sensor status badges, quick-start |
| S05 | Active Ride Dashboard | MVP | **Primary screen.** Speed, HR zone, radar sidebar (if paired), cadence, elapsed time, distance, live map |
| S05.1 | Start Ride Sheet | MVP | Sheet to start a ride |
| S05.2 | Route Picker | Phase 2 | From the Start Sheet, the ability to pick a route for the ride |
| S05.3 | Active Ride Accessory | MVP | Compact strip above TabBar when the dashboard sheet is minimized; shows live ride stats and an Open button |
| S05.4 | Widget Layout | MVP | Default widget layout for the active ride dashboard |
| S05.5 | Widget Layout 2 | MVP | Second widget layout page for the active ride dashboard |
| S06 | Radar Alert | MVP | Sidebar visualization and alert-level state changes |
| S07 | Dashboard Customization | Phase 2 | SpringBoard-style long-press widget editing and page management |
| S08 | Add Widget | Phase 2 | Widget picker sheet; previews all available widgets in supported sizes |
| S09 | Ride Paused | MVP | Pause state with live map frozen; resume / end ride options |
| S10 | Ride Summary | MVP | Distance, time, avg speed, HR zone breakdown, cadence avg, map thumbnail, vehicle pass count, GPX export action |
| S11 | Device Management | MVP | Single flat BLE device list; pair / unpair; role assignment at pairing; one sensor per role with replace-or-cancel on collision |
| S12 | App Settings | MVP | Units, wheel size (navigation row), auto-pause, auto-dim, sensors, HR zones, about. Accounts deferred to Phase 2 |
| S13 | HR Zone Configuration | Deprecated | Pulled from Apple Health; manual override; Karvonen calculation display. See S12 - App Settings for details. |
| S14 | Ride History List | Phase 2 | Scrollable list of past rides with summary stats |
| S15 | Ride Detail | Phase 2 | Full ride: map replay, HR graph, cadence graph, radar event + vehicle pass timeline |
| S16 | Training Zones Graph | Cut | Time-in-zone breakdown across recent rides |
| S17 | Apple Watch | Phase 2 | Glanceable watch app. |
| S18 | AR HUD Configuration | Phase 3 | Configure ENGO 2 / ActiveLook display layout |
| S19 | Route Management | Phase 2 | Browsable list of saved routes with list and map views |
| S20 | Route Detail | Phase 2 | Route detail: MapView, elevation profile, distance, current weather, Strava segments, previous ride history |

> **Note:** Screen-level UX detail — layout, component hierarchy, interaction patterns, and annotation — is specified in `UX.md`. The PRD defines *what* each screen must accomplish; UX.md defines *how* it is structured.

---

## 8. Core Features — Detailed Requirements

### 8.1 Active Ride Dashboard (S05)

The active ride dashboard is the primary screen during a ride. Full layout specification, component hierarchy, and interaction annotations are defined in `UX.md` (see S05 section). This section captures functional requirements and acceptance criteria only.

**Functional Requirements:**
- Must display simultaneously: current speed, HR with zone color, cadence, elapsed time, distance, radar sidebar (only if a radar device is paired), and live map
- All safety-critical elements (radar sidebar, alert states) must occupy positions that do not require the rider to search the screen
- Live map must show current position and heading; north-up or heading-up based on user setting
- All numeric metrics must remain legible in direct sunlight (WCAG AA minimum)

**Acceptance Criteria:**
- [ ] Screen renders within 100ms of ride start
- [ ] Speed updates at minimum 1Hz from active source
- [ ] HR updates reflected within 2 seconds of sensor reading
- [ ] Cadence updates at minimum 1Hz from active source
- [ ] Radar sidebar updates within 500ms of BLE data arrival
- [ ] Live map updates position at minimum 1Hz
- [ ] All text meets WCAG AA in both light and dark mode
- [ ] Dashboard is operable with one gloved tap for pause
- [ ] Radar sidebar is not shown at all when no radar device is paired (space reclaimed by other elements)

---

### 8.2 Radar Visualization

**Purpose:** Represent the approaching-vehicle threat state visually on the ride dashboard without requiring cognitive parsing.

**Target Devices:** Garmin Varia RTL515 and RCT715.

> **Note on RVR820:** The Garmin Varia RVR820 uses a proprietary secure protocol over BLE that is not publicly documented and cannot be reliably targeted. Integration is not planned for any phase.

#### Visibility Rule

The radar visualization component is **only shown when a radar device is paired**. If no radar has been paired in S11:
- The radar component is hidden entirely; its screen space is reclaimed by other dashboard elements
- No "Radar not connected" placeholder is shown
- The rider is not reminded of a feature they do not have

If a radar **was paired** but has **lost connection during an active ride**:
- The sidebar displays a grayed "Radar offline" indicator (the component remains visible because the rider expects it)
- An L1 advisory haptic fires once on disconnection

#### Dot Color Mapping

| Closing Speed Differential | Color Token | Meaning |
|---|---|---|
| Stationary / receding | `brRatingGood` | Safe |
| < 30 km/h differential | `brRatingOkay` | Caution |
| ≥ 30 km/h differential | `brRatingBad` | Danger |

#### Data Requirements from RTL515 / RCT715
- Alert level (0–3: clear, advisory, caution, danger)
- Vehicle count (0–8)
- Per-vehicle: relative distance (meters), closing speed delta (km/h)

---

#### Visualization — Selected Approach: Option F (Sidebar)

**Resolved (OQ14):** Brian has selected Option F — a right-side sidebar strip. The full design is illustrated in `assets/design/Design.sketch` — S06 Radar Alert.

A 24pt-wide vertical strip on the right edge of the active ride dashboard represents the road behind the rider. Vehicles are shown as car icons stacked vertically; their vertical position within the strip reflects relative distance to the rider (closer vehicles appear lower, approaching the rider position at the bottom). Icon size may scale if the Varia exposes signal amplitude for size inference (see OQ11).

**Alert level color treatment:**
- The sidebar background uses `brRatingOkayBg` / `brRatingBadBg` depending on the current alert level
- The individual vehicle icon causing the alert is colored `brRatingOkay` / `brRatingBad`
- At L0 (clear), the sidebar background is transparent / neutral and vehicle icons are `brRatingGood`

**Prior options considered for reference:**

| Option | Summary | Disposition |
|---|---|---|
| A — Semicircular Arc | Dots on arc; position = distance; familiar to Varia users | Considered; not selected |
| B — Bottom Edge Strip | Thin strip; color bars by severity; no distance | Loses too much information |
| C — Threat Ring | Ring around speed value; alert level only | Lowest information density |
| D — Adaptive Disclosure | Compact badge normally; arc expands on L2/L3 | Animation conflicts; complexity |
| E — Map Overlay | Vehicle dots rendered on live map | Rendering conflicts; occlusion |
| **F — Sidebar** | **Right-edge strip; car icons; distance-encoded position** | **Selected** |

---

**Acceptance Criteria:**

- [ ] Renders correctly with 0 vehicles (empty / safe state)
- [ ] Renders correctly with 1–8 vehicles
- [ ] Icon position animates smoothly as vehicle approaches (no jump cuts)
- [ ] Color transitions animate at 0.3s ease
- [ ] Radar sidebar is entirely absent when no device is paired
- [ ] Sidebar degrades to "Radar offline" state (grayed) when device was paired but connection lost during ride
- [ ] Disconnection during active ride triggers L1 advisory haptic + grayed "Radar offline" sidebar

---

### 8.3 Haptic Alert System

**Purpose:** Communicate radar threat severity without requiring the rider to look at the phone, just feel what is going on using their Apple Watch.

#### Three Escalation Levels

| Level | Trigger | Haptic Pattern | Audio |
|---|---|---|---|
| L1 — Advisory | 1–2 vehicles, low closing speed | Single tap — `UIImpactFeedbackGenerator` `.light` | None |
| L2 — Caution | Moderate closing speed OR 3+ vehicles | Double tap `.medium`, 0.5s interval | Warning tone (see `Audio.md`) |
| L3 — Danger | Any vehicle ≥ 30 km/h closing speed | Core Haptics pattern: three 0.14s `HapticContinuous` bursts at full intensity and sharpness — pattern defined in `UX.md §S06` | Danger tone — overrides Silent Mode if user opt-in |
| L0 — Clear | Threat resolves after L2 or L3 | None | All Clear tone (see `Audio.md`) |

#### Alert Rules
- Minimum 3 seconds between same-level re-triggers to prevent alert fatigue
- L3 alert persists until threat recedes; it is not dismissible by the rider
- Danger tone: uses `AVAudioSession` category `.playback` with route override to force audio through speaker. **User must opt in to Silent Mode override in Settings (S12) before this behavior activates.** Default is silent-mode-respectful.
- Warning and All Clear tones always respect Silent Mode (never override)
- Phase 2: Mirror haptic pattern on Apple Watch wrist

---

#### Haptic Design Brainstorming

The current three-level haptic design is functionally sound but warrants discussion before implementation. The following considerations and alternatives are documented for UX review.

**Current Design Rationale**
- L1 single light tap: Low information load; does not interrupt flow
- L2 double medium tap: The double pattern is pre-attentive — riders will recognize "two taps = caution" after minimal conditioning
- L3 Core Haptics continuous pattern: Three burst pattern conveys urgency; harder to ignore than discrete pulses, which is the goal for L3

**Design Considerations**

*Pattern distinctiveness:*  
Each level must be instantly recognizable by feel alone, through cycling gloves, with hands on handlebars. The current single/double/continuous progression satisfies this — but double-tap at L2 has a ≈200ms window where L1 and L2 feel identical until the second tap arrives. Consider extending the inter-tap gap to 400ms to make the double pattern more deliberate.

*False positive fatigue:*  
On a busy road, L1 alerts may fire every 30–90 seconds. If L1 haptic is too prominent, riders will habituate and ignore it, defeating the escalation hierarchy. The `.light` single tap is intentionally subtle for this reason. Validate in field testing.

*Glove permeability:*  
Standard `UIImpactFeedbackGenerator` taptic patterns are perceptible through thin cycling gloves (gel padding ≤ 3mm). Winter gloves with >5mm padding may dampen `.light` impacts significantly. A user-configurable "Haptic Intensity" setting scales all levels up/down to account for this.

*Apple Watch (Phase 2):*  
Wrist haptics are significantly more noticeable than pocket haptics. The same pattern language should be preserved on the watch, but intensity levels should be re-calibrated for wrist delivery. The watch's `WKHapticType.retry` and `.failure` patterns may provide useful references.

**Acceptance Criteria:**
- [ ] L1 haptic fires within 500ms of threshold crossing
- [ ] L2 fires within 500ms
- [ ] L3 fires within 200ms (safety-critical tight budget)
- [ ] Warning tone fires within 500ms of L2 threshold crossing (see `Audio.md`)
- [ ] Danger tone fires within 200ms of L3 threshold crossing (see `Audio.md`)
- [ ] All Clear tone fires within 300ms of threat resolving (see `Audio.md`)
- [ ] Silent Mode override only activates when user has explicitly enabled it in S12
- [ ] All three haptic levels and all four audio states fully testable with mock BLE data (no hardware required)

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
- Cadence is recorded as absent (element omitted) in GPX export when no sensor is present for that track point

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
- `restingHeartRate` is read from **Apple Health** at app launch and at the start of each ride
- **`maxHeartRate` cannot be read from Apple Health — there is no max-heart-rate type.** Only `heartRate`, `restingHeartRate`, `walkingHeartRateAverage`, `heartRateVariabilitySDNN` and `heartRateRecoveryOneMinute` exist. A `.discreteMax` query over historical samples returns *highest ever observed*, which understates any rider who has not gone near their limit wearing a watch, so it is not used. Max HR comes from the 220 − age estimate (§9.4) or manual entry
- If Apple Health does not have these values, the user is prompted to enter them manually in the HR Zones section of S12 (S03 and S13 are both retired; see UX.md §S12)
- App-stored values are always considered overrides; Apple Health is the source of truth unless the user has manually overridden. **This is literal since #96**: `RiderProfile` (DataModel.md §3.5) stores *only* overrides, as two optionals, and resolves `override ?? healthKit ?? default` at read time. A rider who never disagrees with Health persists nothing at all. M10 ships the storage and the Karvonen derivation; M5 supplies the Apple Health term

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

**Purpose:** Provide a live map view on the active ride dashboard showing current position and heading. Support pre-planned route following via GPX import.

**Live Map (MVP):**
- Embedded `MapKit` view within the dashboard (as a widget — see UX.md S05)
- Updates position at minimum 1Hz using `CoreLocation`
- Heading-up orientation by default; user-toggleable to north-up
- No base-map download required; uses standard MapKit tile cache
- During L3 radar alert, map view may be obscured by full-screen alert wash — this is acceptable given the safety priority

**Route Loading (MVP):**

Routes are pre-planned by the rider before the ride. The following sources are supported:

| Source | Method | Notes |
|---|---|---|
| iOS Files app | Import GPX file | Rider selects a `.gpx` or `.fit` file from any location accessible via the Files app (iCloud Drive, local storage, imported from another app) |
| tribos.studio | Service integration — **Phase 2** | Rider connects their tribos.studio account in Settings → Accounts; routes are browsable and importable directly from the Cyclometer UI |
| Strava | Service integration — **Phase 2** | Rider connects their Strava account in Settings → Accounts; routes are browsable and importable directly from the Cyclometer UI |
| Ride with GPS | Service integration — **Phase 2** | Rider connects their Ride with GPS account in Settings → Accounts; routes are browsable and importable directly from the Cyclometer UI |

> **Revised 2026-08-14.** The three service integrations move to Phase 2 along with the Accounts section that
> authenticates them (UX.md §S12). MVP loads routes from the Files app only. This is a consequence of
> deferring Accounts rather than a separate decision — a route service cannot be browsed without a connected
> account, so the two ship together or not at all.

> **Resolved (OQ12):** MVP does not use `MKDirections` (Apple Maps routing). Route creation is not an in-app feature in MVP — riders plan routes externally using tools like tribos.studio, Komoot, Strava, or OnTheGoMap.com and import the resulting GPX file.

**Turn-by-Turn Navigation (MVP):**
- Route overlaid on live map as a polyline in `brPrimary` color
- Turn notifications: Warning audio tone + banner at configurable distance from turn
- No recalculation in MVP; if the rider goes off-route, an "Off route" banner displays with no auto-reroute

**Acceptance Criteria:**
- [ ] Map renders current position within 5 seconds of ride start (GPS lock)
- [ ] Position updates smoothly at 1Hz minimum with no jumping
- [ ] Route overlay renders correctly from imported GPX file
- [ ] tribos.studio route browsing and import functional (service integration — Phase 2)
- [ ] Turn notification fires within ±10m of configured distance from turn
- [ ] "Off route" banner displays within 5 seconds of deviation from route polyline
- [ ] Map remains functional when radar BLE and HR BLE are simultaneously active (no resource contention)
- [ ] Map does not drain more than an additional 5% battery per hour beyond GPS-only baseline

---

### 8.7 GPX Export with Biometric Track Point Extensions and Vehicle Pass Events

**Purpose:** Produce a standards-compliant GPX 1.1 file for every ride with full per-point biometric data (heart rate, cadence, speed, power) and vehicle pass events recorded as waypoints. Files are stored in a location accessible via the iOS Files app.

**GPX Version:** 1.1  
**Biometric Extension Schema:** `gpxtpx:TrackPointExtension` v2  
**Vehicle Pass Extension Schema:** Custom `cyc:VehiclePassEvent` (see Appendix B)

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

**Vehicle Pass Events:**

A vehicle pass event is recorded when a radar-tracked vehicle transitions from approaching to overtaking and clearing the rider. Detection criteria:
- Vehicle was present in radar data (distance decreasing) for ≥ 2 seconds
- Vehicle then disappears from radar tracking (distance reached minimum threshold or vehicle left radar range from the front)
- This distinguishes a genuine overtake from a vehicle that turned off or slowed before reaching the rider

Vehicle pass events are recorded as GPX `<wpt>` (waypoint) elements rather than track point extensions. This preserves compatibility with any app that reads GPX waypoints without requiring `cyc:` namespace support.

> **No existing standard:** There is no published standard or widely-adopted extension for vehicle pass events in GPX 1.1 or any common extension namespace (gpxtpx, Garmin Training Center, etc.). The `cyc:` namespace defined here is Cyclometer-specific. Future standardization with other radar-compatible apps (e.g., Cadence, MyBikeTraffic) would be a positive industry outcome.

| Field | GPX Element | Notes |
|---|---|---|
| Location at pass | `<wpt lat="..." lon="...">` | Rider position when vehicle cleared |
| Timestamp | `<time>` | UTC timestamp of pass |
| Event type | `<type>vehiclePass</type>` | Standard GPX type element for filtering |
| Alert level | `<cyc:alertLevel>` | danger / caution / advisory at time of pass |
| Rider speed | `<cyc:riderSpeedKph>` | Rider speed at moment of pass (km/h) |
| Estimated pass speed | `<cyc:estimatedPassSpeedKph>` | The **vehicle's ground speed** (km/h) — an absolute speed, not a closing speed. Always greater than `<cyc:riderSpeedKph>`. Omitted if the vehicle was never observed approaching |

**What `estimatedPassSpeedKph` carries.** The radar reports *closing* speed — how fast the vehicle is gaining on the rider, not how fast it is travelling — so a ground speed has to be derived:

```
estimatedPassSpeedKph = riderSpeedKph (at the pass) + peak closing speed (over the vehicle's track)
```

The **peak** rather than an average over the track. Radar measures only the radial component of the closing speed, which decays by cos(θ) as a vehicle draws alongside, so a whole-track mean is dragged down by the tail near the rider — by 13–27 km/h across the four overtakes captured on 2026-09-06. The peak occurs while the vehicle is still lined up behind the rider (87–135 m out in every one of those captures), where θ is near zero and the radial component is the true speed difference.

Because both speeds are exported, a consumer recovers the raw radar closing speed as `estimatedPassSpeedKph − riderSpeedKph`, to the one-decimal precision of the file.

> **This is the vehicle's speed on approach**, not necessarily its speed at the instant it drew level: the two terms are measured up to 22 seconds apart. A vehicle that slows behind the rider before committing to the pass is described by how fast it came up, not how fast it went by.

**Recording Rate:** Track points recorded at 1Hz. Vehicle pass events recorded discretely on occurrence.

**File Naming Convention:** `Cyclometer_YYYY-MM-DD_HH-mm.gpx`

**Storage:** Files app integration via `UIFileSharingEnabled` (`Info.plist`) and `LSSupportsOpeningDocumentsInPlace`. Ride GPX files stored in the app's `Documents/Rides/` directory.

**Acceptance Criteria:**
- [ ] GPX file validates against GPX 1.1 schema
- [ ] `gpxtpx:TrackPointExtension` namespace declared correctly in file header
- [ ] `cyc:` namespace declared correctly in file header
- [ ] HR, cadence, speed values present for each second where sensor data was active
- [ ] Fields correctly absent (not zero) for seconds with no active sensor
- [ ] Vehicle pass `<wpt>` elements present for each detected pass event
- [ ] Vehicle pass detection correctly distinguishes overtakes from vehicles that turn off before reaching rider
- [ ] File available in Files app within 5 seconds of ride end
- [ ] GPX imports correctly into Strava, Garmin Connect, and RideWithGPS (manual QA; `cyc:` waypoints should be ignored gracefully by apps that don't support them)
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

### 8.9 Wheel Circumference and GPS Auto-Calibration

**Purpose:** Provide accurate speed and distance measurements from the BLE speed sensor, with automatic calibration against GPS to correct for tire wear, inflation changes, and rider weight variations.

> **MVP scope — one bike.** The circumference below is a single app-wide value, and paired sensors are keyed by role alone. Riders own several bikes, so Phase 2 makes each bike own its speed/cadence/radar sensors, with the circumference living on the speed sensor and heart rate staying rider-scoped (§8.9.1 explains why circumference belongs to the sensor rather than to the bike or a wheelset). One MVP limitation follows and is accepted rather than filed as a bug: a rider who moves a single speed sensor between bikes carries the last bike's circumference and calibration to the next. The target shape is specified in DataModel.md §3.9; the S05.1 bike picker is already reserved in UX.md.

**Circumference Configuration:**

Riders can configure wheel circumference using one of three methods:

1. **Preset sizes** (selected from a list in S12):

| Tire | Circumference |
|---|---|
| 700c × 23mm | 2,096 mm |
| 700c × 25mm | 2,105 mm |
| 700c × 28mm | 2,136 mm |
| 700c × 32mm | 2,155 mm |
| 700c × 35mm | 2,168 mm |
| 650b × 47mm (27.5") | 2,144 mm |
| 29" × 2.1" (MTB) | 2,288 mm |
| 26" × 2.0" (MTB) | 2,051 mm |

2. **Manual entry:** Rider enters circumference in mm directly. Useful for non-standard tires or measured values.

3. **GPS auto-calibration** (automatic, no user action required): The system continuously compares BLE wheel distance against GPS-derived distance during an active ride and adjusts the stored circumference when a discrepancy exceeds the threshold.

**GPS Auto-Calibration Algorithm:**
- Runs continuously during active ride when both BLE speed sensor and GPS are active
- Measurement window: rolling 1,500-meter GPS distance minimum (revised from 500 m — see §8.9.2)
- Discrepancy threshold: if `|BLE distance − GPS distance| / GPS distance > 2%` over the measurement window, trigger calibration (revised from 5% — see §8.9.2)
- Confirmation: the discrepancy must exceed the threshold in the **same direction across two consecutive windows** before a correction is committed. A single anomalous window changes nothing. The correction is derived from the **mean of the confirming windows' measurements** — two windows agreeing is what licenses the change, so both inform its value
- Calibration adjustment: `new circumference = stored circumference × (GPS distance / BLE distance)`
- Maximum single adjustment: ±10% of stored value (guards against GPS spikes causing overcorrection)
- Results outside the 1,500–3,000 mm sanity range are **rejected, not clamped** — a value that implausible means the measurement was wrong, and pinning it to a boundary would commit garbage while looking deliberate
- Maximum 3 corrections per ride
- GPS distance is derived by integrating Doppler ground speed over time, **not** by summing the distance between successive position fixes. Position differencing measures `|true + noise|`, which is biased *upward* by roughly the size of the trigger threshold itself at realistic fix noise; speed error is zero-mean and averages out across the window
- After calibration: updated circumference is saved to `AppPreferences.wheelCircumferenceMM`; rider is notified via a brief non-intrusive banner: "Wheel size auto-adjusted to [N] mm"
- Calibration is suspended during L2/L3 radar alerts, map-following turn alerts, or when GPS horizontal accuracy is > 10 meters (unreliable GPS). Suspension *pauses* the window rather than discarding it — a rider in traffic would otherwise never complete one, which is exactly the rider who uses radar most
- The window is discarded outright when the BLE speed sensor leaves its connected state: a reconnect gap loses revolutions that GPS kept counting through, which would fabricate a large discrepancy

**Rationale:** GPS is not precise enough for per-second speed measurement (hence BLE priority) but is accurate enough over a window of this length for circumference calibration, because its error is zero-mean and averages down as `√N`. The threshold prevents constant micro-adjustments while staying low enough to catch the drift the feature exists for; §8.9.2 records why the original 5% did not.

**Acceptance Criteria:**
- [x] All preset sizes available in S12, labelled as printed on the tire sidewall ("700 x 25c", "650b x 47", "29 x 2.1"). Circumference in mm is *not* shown against each preset — riders choose by tire size, and surfacing both made the row wrap; the mm value appears only when Custom is selected, where it is the thing being edited
- [x] Manual entry accepts values in range 1,500–3,000 mm (reasonable sanity bounds); out-of-range entries are rejected and the field reverts to the stored value
- [x] Auto-calibration triggers correctly when 2% discrepancy sustained over two consecutive 1,500 m GPS windows; a single qualifying window does not commit
- [x] Auto-calibration does not trigger when GPS horizontal accuracy > 10m
- [x] Calibration adjustment capped at ±10% per event, and a result outside 1,500–3,000 mm is rejected rather than clamped
- [x] Updated circumference persisted to AppPreferences immediately (#70; UserProfile was split into RiderProfile + AppPreferences — see DataModel.md §3.6)
- [x] Banner notification displayed when auto-calibration fires
- [x] Calibration disabled when GPS-only speed mode is active (no BLE sensor connected)
- [x] Unit tested: calibration math correct for a range of known discrepancy scenarios
- [x] Verified on hardware (2026-08-15): a ride started at 2288 mm (29 × 2.1) corrected to 2069 mm after two confirming windows, persisted, showed the banner, and Settings then read Custom 2069 mm. Six windows across two rides on the same bike measured 2057/2069/2069/2055/2051/2069 mm — mean 2061.8, sd 8.4 mm (0.41%), against the ~0.49% predicted floor

---

### 8.9.1 Where Wheel Circumference Belongs — Research Note

**Question (raised in PR #83 review):** a draft data model gave each bike a collection of wheelsets,
each with its own circumference. Is multiple-wheelsets-per-bike a real need for this app's target
audience, or invented complexity?

**Finding: it is invented complexity, and the entity is not needed — but for a more interesting
reason than "riders only own one wheelset."**

**1. Circumference is a property of the sensor, not of the bike.** Every BLE CSC speed sensor this
app targets is hub-mounted, so the sensor is physically bound to exactly one wheel. It already *is*
the wheel's identity. Garmin — the incumbent this app is measured against — models it exactly this
way: wheel size is configured per speed sensor, not per bike or activity profile.

> "Wheel size does not matter unless you have a speed sensor, and if you have one (or more), then
> wheel size setting is per sensor and not per profile."
> — [Garmin Forums, Edge Explore 2](https://forums.garmin.com/sports-fitness/cycling/f/edge-explore-2/352281/bicycle-profiles-question)

> "Each speed sensor can have its own manual wheel circumference entered in the settings, so that
> the speed readings will be correct for each bike." … "profiles and sensors don't work in
> conjunction with each other, they are completely separate."
> — [mtbr forums, Edge 520/820](https://www.mtbr.com/gps-hrm-bike-computer/garmin-520-820-multiple-wheel-bike-profiles-1019414.html)

**2. That makes the two-wheelset rider fall out for free.** A rider with a race wheelset and a
training wheelset, each carrying its own sensor, gets two circumferences and two calibration
histories without any wheelset concept existing. The remaining case — two wheelsets, one sensor —
means moving the sensor and re-entering the value, which is the behaviour a Garmin Edge has today
and which the same forums treat as normal ("most people only have one and will swap it between
wheels/bikes"; the advice for multi-bike setups is simply to buy a sensor per wheel).

**3. Target audience.** Cyclometer is a $10 one-time-purchase app for riders who want a legible
outdoor dashboard with radar integration — not a team/fleet management tool. A rider affluent
enough to own two wheelsets is, on this evidence, also the rider who owns two speed sensors, since
the sensors cost a fraction of a wheelset. Designing a `Wheelset` entity to serve the narrow
intersection of "owns two wheelsets" and "refuses to buy a second sensor" is not a good trade.

**Decision:**
- **MVP:** one global `AppPreferences.wheelCircumferenceMM`. Unchanged.
- **Phase 2:** circumference moves onto the speed-role `PairedSensor`, and bikes own their sensors.
  No `Wheelset` entity. See DataModel.md §3.9.
- **Third major release at the earliest, if ever:** named wheelsets with swap-without-re-entry.
  Revisit only if riders actually ask for it.

**Evidence quality — stated plainly.** The Garmin behaviour is sourced from two independent user
forums, corroborating each other, *not* from official Garmin documentation (the relevant support
page would not render for retrieval). No user research was conducted with Cyclometer's own
audience — point 3 is reasoning from the product's price point and positioning, not measured data.
The decision is biased toward the option that stays cheap to reverse: adding a `Wheelset` entity
later is additive, whereas removing one that riders have populated is not.

---

### 8.9.2 Why the Trigger Threshold Moved from 5% to 2% — Research Note

**Question (raised by the first field test, 2026-08-14):** a rider deliberately set the wrong preset,
rode a mile, and saw no correction — only a wrong distance. Was 5% too coarse to be useful?

**Finding: yes. 5% excluded every cause this feature was written to correct.**

**1. The spec's own rationale sat an order of magnitude below its own threshold.** §8.9 justifies
auto-calibration as correcting "tire wear, inflation changes, and rider weight variations". Measured
magnitudes: tread wear over a tyre's life 0.3–0.8%, inflation low-vs-high 0.3–1.0%, rider weight
150 lb vs 200 lb about 0.5%. None of it is visible at 5%.

**2. The population that most needs it is at ~2%.** Sheldon Brown, the standard reference on
cyclecomputer calibration:

> "Many if not most cyclists set cyclecomputers to a default value for wheel size, which can easily
> be off by 2% or more."
> — [Sheldon Brown, cyclecomputer accuracy](https://sheldonbrown.com/cyclecomputer-accuracy.html)

Chart- and ETRTO-derived values are quoted as accurate "to within one or two percent". A field report
on a Garmin Edge 830 put one rider's discrepancy at 60 mm — about 2.85%. All of it invisible at 5%.

**3. The preset table proves it independently.** Take every way a rider could store one preset while
actually rolling another — 56 ordered (stored, actual) combinations from §8.9's own list, since the
discrepancy is measured against the true wheel and so is not symmetric. Only 17 exceed 5%, **and
every one of them involves 29 × 2.1 or 26 × 2.0**. Not a single road-only combination is catchable:
the entire 700c range spans 3.44%, so a rider who picked the wrong 700c preset — the most likely
configuration mistake there is — could never be corrected. At 2% it is 36 of 56, 10 of them
road-only.

**4. The headroom was never needed.** GPS distance is integrated from Doppler ground speed, whose
error is zero-mean and averages down as `√N`. Over a 1,500 m window the measurement floor is about
0.49% (1σ): ~0.41% from GPS, ~0.27% from where the window boundaries fall relative to the ~1 Hz BLE
notifications. A 2% threshold sits 4.1σ above that, and must additionally hold across two consecutive
windows in the same direction. 5% was roughly 10σ — margin bought by giving up the use case.

**5. For contrast, Garmin uses no threshold at all** — wheel size is "adjusted using GPS data that is
run through a slow moving average", recomputed continuously throughout the activity
([Garmin forums](https://forums.garmin.com/sports-fitness/cycling/f/accessories-sensors/157669/re-calibration-of-the-speed-sensor)).
A step correction behind a threshold is the more conservative design; it just has to be reachable.

**Decision:**
- Threshold **5% → 2%**; window **500 m → 1,500 m**. The window grew because the boundary term is a
  fixed *duration*, so it shrinks only with distance — at 500 m its spread is ~0.8%, too close to a
  2% threshold. Cost: a correction now needs ~3 km of clean riding rather than ~1 km.
- Two-window confirmation and a 3-per-ride cap added, since a lower threshold fires more readily and
  a commit silently rewrites a setting the rider chose.

**A rejected change, recorded so it is not re-proposed.** It was argued that the revolution delta
straddling a window start should be discarded, since it covers ground partly ridden before the window
opened. It does — but the riding after the *last* delta before the window closes is symmetrically
uncounted, and the two truncations cancel. Monte Carlo over both boundaries: counting the straddling
delta gives a mean error of −0.001 s (sd 0.41 s); discarding it gives **−1.000 s**, a systematic
−0.67% at 1,500 m that would bias every correction toward a larger wheel. The straddling delta is
counted.

**Evidence quality — stated plainly.** The Sheldon Brown figures and the Garmin mechanism are from
authoritative or primary sources. The per-factor magnitudes in point 1 come from corroborating
cycling-calculator sites, **not** instrumented measurement — treat them as order-of-magnitude. The
noise-floor and boundary figures are calculated from the implementation and simulated, not measured
on hardware; no ride has yet exercised a commit at any threshold.

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
- Radar sidebar shows the grayed "Radar offline" indicator after 10 seconds without reconnect
- L1 advisory haptic fires once on unexpected disconnection during active ride

**Acceptance Criteria:**
- [ ] App discovers Varia within 10 seconds of BLE scan initiation
- [ ] Characteristic notifications parse correctly for 0–8 vehicle payloads
- [ ] Disconnection during active ride triggers grayed "Radar offline" sidebar + advisory haptic
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
Speed is derived from cumulative wheel revolutions and event time stamps per the CSC specification. Requires wheel circumference configured in Settings (S12) or auto-calibrated (see §8.9). Default: 2096mm (700c × 23mm tire).

**Cadence Calculation:**  
Derived from cumulative crank revolutions and event time stamps per CSC specification.

**Acceptance Criteria:**
- [ ] Connects to any BLE CSC Profile-compliant device
- [ ] Speed and cadence calculated correctly from cumulative revolution data
- [ ] Wheel circumference configurable in S12 (presets + manual + GPS auto-calibration)
- [ ] Cadence and speed independently functional when sensor provides only one (some sensors are speed-only or cadence-only)
- [ ] Graceful fallback to GPS speed on BLE speed sensor disconnection

**Open Questions**:

- [x] OQBLE1: ✅ **Resolved (see `BLE.md`):** Speed and Cadence are separate roles, not a single combined sensor type. All device variants — speed-only, cadence-only, and combo — use the same CSC service (`0x1816`) and CSC Measurement characteristic (`0x2A5B`); the payload flags byte (`hasWheelData` / `hasCrankData`) determines which fields are present per notification. Device capabilities are read from the CSC Feature characteristic (`0x2A5C`) at pairing, and the rider assigns roles per device in S11 — supporting the mixed case of a dedicated speed sensor alongside a combo device used for cadence only. A single `BLECSCClient` (#20) handles all variants.

---

### 9.4 Apple Watch / HealthKit

**HealthKit Entitlements Required:**
- `HKQuantityTypeIdentifierHeartRate` (read)
- `HKQuantityTypeIdentifierRestingHeartRate` (read)
- `HKCharacteristicTypeIdentifierDateOfBirth` (read — for max HR estimation if not available)
- `HKWorkoutType` (write — MVP; the ride is written back at ride end per UX.md §S10, and the share
  authorization is requested alongside the reads at S01 so the rider answers one sheet, not two)

**Profile Data Read at Onboarding and Ride Start:**
- `restingHeartRate` → `HKQuantityTypeIdentifierRestingHeartRate`
- `maxHeartRate` → `HKQuantityTypeIdentifierHeartRate` (historical max, or age-based estimate: 220 − age)
- These values populate the Karvonen zone calculation and update if Apple Health values change

**HR Streaming During Ride:**
- Use `HKAnchoredObjectQuery` with live updates when Apple Watch is the active HR source
- Fallback: Apple Watch is secondary to BLE HR strap (see §8.4)

**Acceptance Criteria:**
- [ ] App correctly reads `restingHeartRate` from HealthKit on ride start
- [ ] Max HR uses the age-based estimate (220 − age) from the HealthKit `dateOfBirth` characteristic — there is no HealthKit max-HR type to read (§8.5)
- [ ] A manual override in S12 wins over both, and clearing it returns to the Health-sourced value (`RiderProfile`, DataModel.md §3.5)
- [ ] App functions with HealthKit permission denied (HR zone tile shows "No HR Source")
- [ ] HR stream from Apple Watch feeds zone display within 2 seconds

---

### 9.5 ENGO 2 / ActiveLook AR Glasses (Phase 3)

**SDK:** ActiveLook iOS SDK  
**Protocol:** BLE  
**Display:** Monochrome HUD, ~300×256px effective area  
**Competitive benchmark:** Cadence already ships ActiveLook support — review their implementation for feature parity baseline.

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

### Persistence Strategy

> **Hybrid persistence:** In-memory ring buffer (`RideDataBuffer`) during active rides, flushed to CoreData via `NSBatchInsertRequest` at ride end for raw `TrackPoint` time-series. SwiftData with `@Query` for `Ride` summaries, `UserProfile`, and history screens.

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
    var radarEventCount: Int
    var vehiclePassCount: Int          // total vehicle pass events recorded
    var gpxFileURL: URL?
    var trackPoints: [TrackPoint]
    var radarEvents: [RadarEvent]
    var vehiclePassEvents: [VehiclePassEvent]  // discrete pass events for GPX export
}
```

---

### TrackPoint

```swift
@Model class TrackPoint {
    var id: UUID
    var rideId: UUID
    var timestamp: Date
    
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var horizontalAccuracy: Double
    
    var speed: Double?                 // m/s; nil if no source active
    var speedSource: SensorSource
    
    var heartRateBPM: Int?
    var heartRateSource: SensorSource
    
    var cadenceRPM: Int?
    
    var powerWatts: Int?               // Phase 3
}

enum SensorSource: String, Codable {
    case bleHR, bleWheel, bleCadence, blePower, appleWatch, gps, none
}
```

---

### RadarEvent

```swift
@Model class RadarEvent {
    var id: UUID
    var rideId: UUID
    var timestamp: Date
    var vehicleCount: Int
    var alertLevel: AlertLevel
    var vehicles: [RadarVehicle]
}

enum AlertLevel: Int, Codable, Comparable {
    case clear = 0, advisory = 1, caution = 2, danger = 3
}
```

---

### RadarVehicle

```swift
struct RadarVehicle: Codable {
    var vehicleIndex: Int
    var distanceMeters: Double
    var closingSpeedKph: Double        // positive = approaching; negative = receding
    var alertLevel: AlertLevel
    var estimatedSize: VehicleSize     // .unknown for MVP (see OQ11)
}

enum VehicleSize: String, Codable {
    case unknown, small, medium, large
}
```

---

### VehiclePassEvent

> New in v0.3. Recorded as a GPX `<wpt>` element with `cyc:VehiclePassEvent` extension (see Appendix B). Stored separately from `RadarEvent` because a pass event is a discrete occurrence, not a state snapshot.

```swift
@Model class VehiclePassEvent {
    var id: UUID
    var rideId: UUID
    var timestamp: Date
    
    var latitude: Double               // rider position at time of pass
    var longitude: Double
    
    var alertLevelAtPass: AlertLevel   // threat level when vehicle cleared the rider
    var riderSpeedKph: Double          // rider speed at moment of pass
    var estimatedPassSpeedKph: Double? // vehicle ground speed = riderSpeedKph + peak closing speed; nil if never observed approaching
}
```

**Pass detection logic:**
```swift
// A pass is detected when a vehicle that was being tracked:
// 1. Was present in radar data for >= 2 continuous seconds
// 2. AND then disappears from radar tracking
// 3. AND closing speed was positive (approaching) for majority of tracking duration
// This guards against vehicles that turn off or slow before reaching the rider.
```

---

### UserProfile

```swift
@Model class UserProfile {
    var id: UUID
    
    var restingHeartRate: Int
    var maxHeartRate: Int
    var heartRateSourceIsAppleHealth: Bool
    var dateOfBirth: DateComponents?
    
    var preferredUnit: UnitSystem
    var wheelCircumferenceMM: Int      // default 2096; updated by auto-calibration
    var mapOrientation: MapOrientation
    
    var pairedRadarIdentifier: UUID?
    var pairedHRSensorIdentifier: UUID?
    var pairedSpeedCadenceSensorIdentifier: UUID?
}

enum UnitSystem: String, Codable { case metric, imperial }
enum MapOrientation: String, Codable { case headingUp, northUp }
```

---

## 11. Architecture

### Pattern: The Composable Architecture (TCA)

**Rationale:** Cyclometer has multiple concurrent real-time data streams (BLE radar, BLE HR, BLE speed/cadence, HealthKit, CoreLocation), safety-critical alert logic that must be fully unit-testable without hardware, and planned multi-target expansion (Apple Watch, AR glasses). TCA's explicit state management, side-effect isolation via `Effect`, dependency injection via `@Dependency`, and `TestStore` make it the strongest architectural fit.

**TCA Dependency Clients:**
```swift
@DependencyClient struct BluetoothClient
@DependencyClient struct HealthKitClient
@DependencyClient struct LocationClient
@DependencyClient struct HapticClient
@DependencyClient struct AudioAlertClient     // Three tones: allClear, warning, danger
@DependencyClient struct PersistenceClient
@DependencyClient struct NavigationClient     // GPX import, tribos.studio routes, turn calc
@DependencyClient struct WheelCalibrationClient  // GPS vs BLE distance comparison
```

**Feature Decomposition:**
```
AppFeature
├── OnboardingFeature
│   ├── WelcomeFeature
│   ├── SensorPairingFeature
│   └── ProfileSetupFeature
├── ActiveRideFeature
│   ├── RadarFeature                    ← BLE stream, alert level, vehicle pass detection
│   ├── HeartRateFeature
│   ├── SpeedCadenceFeature
│   ├── NavigationFeature               ← GPX import, tribos.studio, turn alerts
│   ├── TrackPointRecorderFeature       ← 1Hz track points + vehicle pass event recording
│   ├── WheelCalibrationFeature         ← GPS vs BLE auto-calibration
│   └── AlertOrchestratorFeature        ← Combines all streams → haptic/audio/screen
├── RideHistoryFeature                  ← Phase 2
├── RideDetailFeature                   ← Phase 2
├── RouteFeature                        ← Phase 2; Routes tab (list, map, detail)
└── SettingsFeature
    ├── DeviceSettingsFeature
    ├── HRZoneSettingsFeature
    └── AlertSettingsFeature
```

**Navigation Structure:**
The app uses a `TabView` with three tabs:

| Tab | Icon | Phase |
|---|---|---|
| Rides | `figure.outdoor.cycle` | MVP |
| Routes | `point.topleft.down.curvedto.point.bottomright.up` | Phase 2 |
| Settings | `gearshape` | MVP |

The Routes tab is hidden or shows a "Coming in a future update" placeholder in MVP and becomes fully functional in Phase 2.

**Project Folder Structure:**
```
Cyclometer/
├── App/
├── Features/
│   ├── ActiveRide/
│   ├── Radar/
│   ├── HeartRate/
│   ├── SpeedCadence/
│   ├── Navigation/
│   ├── TrackPointRecorder/
│   ├── WheelCalibration/
│   ├── AlertOrchestrator/
│   ├── Onboarding/
│   ├── RideHistory/
│   ├── Routes/
│   └── Settings/
├── Clients/
│   ├── BluetoothClient.swift
│   ├── HealthKitClient.swift
│   ├── LocationClient.swift
│   ├── HapticClient.swift
│   ├── AudioAlertClient.swift
│   ├── NavigationClient.swift
│   ├── WheelCalibrationClient.swift
│   └── PersistenceClient.swift
├── Models/
│   ├── Ride.swift
│   ├── TrackPoint.swift
│   ├── RadarEvent.swift
│   ├── RadarVehicle.swift
│   ├── VehiclePassEvent.swift
│   └── UserProfile.swift
├── Export/
│   └── GPXExporter.swift
├── DesignSystem/
│   ├── Color+Cyclometer.swift
│   ├── Typography.swift
│   └── Components/
└── Tests/
    ├── RadarFeatureTests.swift
    ├── VehiclePassDetectionTests.swift
    ├── HeartRateFeatureTests.swift
    ├── SpeedCadenceFeatureTests.swift
    ├── WheelCalibrationTests.swift
    ├── AlertOrchestratorTests.swift
    ├── AudioAlertTests.swift
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
- Memory footprint: < 120MB during active ride on iPhone 16 or later

### Battery
- Active ride session: < 15% battery drain per hour (iPhone 16 baseline, screen-on navigation included)
- GPS: `CLLocationManager` with `allowsBackgroundLocationUpdates = true`; `pausesLocationUpdatesAutomatically = false`
- BLE: connection-based characteristic notification (not continuous scan) after pairing

### Reliability
- Active ride state survives app backgrounding, phone calls, and iOS memory pressure events
- Ride data not lost on crash: CoreData checkpoint every 30 seconds
- GPX file written atomically at ride end
- Radar alert L3 must not be skipped even if the UI thread is momentarily busy (dispatched on a high-priority queue)
- Audio Danger tone dispatched from high-priority queue to guarantee < 200ms latency

### Accessibility
- VoiceOver: supported on all non-ride screens; suspended during active ride
- Dynamic Type: supported on all screens
- Minimum tap target: 44×44 pt on all active ride controls
- High contrast: tested with iOS Increase Contrast enabled

### Privacy
- HealthKit data: read-only, apart from the `HKWorkout` the app writes back at ride end (UX.md §S10); no data transmitted to any server
- GPS and ride data: stored locally only
- BLE device identifiers: not transmitted externally
- No analytics or crash reporting without explicit user consent

### Localization (MVP)
- English only at launch
- Unit system: metric / imperial toggle in UserProfile
- Date/time: respects device locale
- GPX timestamps: UTC per GPX 1.1 spec

### Platform
- **iOS 26.0 minimum**
- iPhone only (no iPad support)
- No Mac Catalyst

---

## 13. Phased Milestones

### Phase 1 — MVP (Target: 3 months)

> **Execution order (v0.4.2):** M1 -> M2 -> M3 -> **M6 -> M10** -> M4 -> M5 -> M7 -> M8 -> M9 -> M11 -> M12. Milestone numbering is retained for tracking continuity; GitHub milestone due dates encode the execution sequence.

| Milestone | Deliverable |
|---|---|
| M1 | Xcode project scaffold; TCA + CoreData + SwiftData; CI/CD via GitHub Actions |
| M2 | BLE client — Varia RTL515/RCT715 connect + parse + mock; HR Profile; CSC Profile |
| M3 | Active Ride Dashboard — speed, cadence, time, distance (no radar, no HR) |
| M4 | Radar sidebar visualization; haptic alerts L1–L3; three-tone audio system (All Clear, Warning, Danger) |
| M5 | HealthKit integration; HR zone display; BLE HR fallback to Apple Watch |
| M6 | Wire CSC client (built in M2, #20) into the metrics pipeline; GPS fallback for speed; wheel circumference presets + manual entry + GPS auto-calibration; minimal BLE pairing UI + CSC role assignment (precursor to full S11 in M10) |
| M7 | TrackPoint recording; vehicle pass event detection; GPX export with `gpxtpx` + `cyc:` extensions |
| M8 | Navigation: live map; GPX route import; turn alerts (tribos.studio integration moves to Phase 2 with Accounts) |
| M9 | Ride summary; ride history persistence; vehicle pass event count in summary |
| M10 | Settings (S12, less Accounts); full device management (S11 flat list, extending the M6 pairing sheet); replace-or-cancel on role collision; radar and HR pairing brought under the paired-record gate; `RiderProfile` + HR zones; onboarding (S01, S02) |
| M11 | QA; TestFlight open beta; bug fixes |
| M12 | App Store submission |

### Phase 2 — Companion, History & Routes (Target: +2 months post-launch)
Routes tab (S19, S20): route list with list and map views, route detail with elevation profile, current weather, Strava segments, and previous ride history. Ride history (S14) + detail view (S15) with vehicle pass timeline. Apple Watch app + complication (S17). Dynamic Island. HR/cadence graphs. Strava/Garmin export. Dashboard customization (S07, S08). Route picker in Start Sheet (S05.2). Multi-bike management — bikes own their sensors, circumference lives on the speed sensor (DataModel.md §3.9) — plus the S05.1 bike picker.

### Phase 3 — AR, Power & Platform (Target: +4 months post-Phase 2)
Power meter BLE support, ENGO 2 / ActiveLook AR integration (S18), segment detection.

---

## 14. Open Questions

| # | Question | Owner | Priority | Status |
|---|---|---|---|---|
| OQ1 | SwiftData vs CoreData? | Engineering | High | ✅ **Resolved: Hybrid — CoreData for TrackPoint time-series, SwiftData for summaries** |
| OQ2 | Does Garmin's mobile SDK provide a cleaner Varia BLE path than raw CoreBluetooth? Evaluate in M2 spike. | Engineering | High | ✅ **Resolved: Combined approach. Use CoreBluetooth and apply for Garmin developer program** |
| OQ3 | iPad support? | Product | Low | ✅ **Resolved: No iPad** |
| OQ4 | Audio alert delivery: tones vs synthesized voice? | Design | Medium | ✅ **Resolved: Tones — three-tone system (All Clear, Warning, Danger). Spec in `Audio.md`.** |
| OQ5 | Override Silent Mode for L3 danger alerts? | Design | High | ✅ **Resolved: Yes, user opt-in. Warning and All Clear respect Silent Mode always.** |
| OQ6 | App name for App Store? | Product | Medium | ✅ **Resolved: Cyclometer** |
| OQ7 | Minimum Varia RTL515 / RCT715 firmware version required for BLE characteristic support? | Engineering | High | ✅ **Resolved: v2.00 or v3.00 depending on the production run** |
| OQ8 | Include basic Apple Watch complication in Phase 1? | Product | Medium | ✅ **Resolved: Defer to Phase 2** |
| OQ9 | HR zone formula: Karvonen-only or allow custom percentages in MVP? | Design | Low | ✅ **Resolved: Karvonen-only** |
| OQ10 | TestFlight beta: open or closed? | Product | Low | ✅ **Resolved: Open beta** |
| OQ11 | Does Garmin Varia RTL515/RCT715 expose radar return signal amplitude over BLE for vehicle size inference? | Engineering | Medium | ✅ **Resolved: No it does not** |
| OQ12 | Navigation: `MKDirections` routing or GPX import only? | Design | Medium | ✅ **Resolved: GPX import only. No in-app route creation in MVP.** |
| OQ13 | Wheel circumference presets and calibration? | Design | Low | ✅ **Resolved: Common presets (700c, 650b, 29", 26") + manual entry + GPS auto-calibration at 2% discrepancy threshold over two consecutive 1,500 m windows (revised from 5% / 500 m — see §8.9.2). See §8.9.** |
| OQ14 | Radar visualization approach: arc, strip, ring, adaptive, or map overlay? | Design | High | ✅ **Resolved: Option F — right-side sidebar strip with car icons; vehicle position encodes relative distance. See §8.2 and `assets/design/Design.sketch` — S06.** |
| OQ15 | Vehicle pass detection: minimum approach distance threshold before qualifying as a pass vs. turn-off? | Engineering | Medium | Open — requires field testing with RTL515/RCT715 to determine realistic detection parameters |
| OQ16 | Audio tone fine-tuning: exact frequencies, durations, and waveforms validated on real ride (phone in jersey pocket at speed)? | Design | Medium | Open — `Audio.md §Acceptance Criteria` defines test requirements; field test required before M4 freeze |

---

## 15. Out of Scope

| Item | Rationale |
|---|---|
| **Garmin Varia RVR820** | Proprietary secure BLE protocol; not publicly documented |
| **ANT+ direct support** | iOS hardware does not support ANT+; Garmin SDK evaluated as bridge only (OQ2) |
| **SRAM AXS / electronic shifting** | No public write API |
| **Power meter support** | Phase 3 |
| **Live ride sharing** | Requires server infrastructure; local-first MVP |
| **Coaching / AI training plans** | Separate product consideration |
| **Android** | iOS-only |
| **Web dashboard** | No server component planned |
| **Social / community features** | No social graph planned |
| **iPad** | iPhone-only by product decision |
| **Mac Catalyst** | Not planned |
| **Auto-reroute navigation** | MVP shows "Off route" banner only |
| **In-app route creation** | Riders plan routes externally (tribos.studio, Komoot, Strava) and import GPX |
| **`MKDirections` routing** | Resolved out of scope for MVP (OQ12) |

---

## 16. Appendix A — Design Tokens

The Cyclometer color system is a 30-token system in 7 categories. The **canonical source** for all token definitions, hex values, and contrast annotations is `assets/design/colors.md`. Safety-critical and zone tokens summary:

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

Every ride exports a GPX 1.1 file with biometric track point extensions and vehicle pass event waypoints.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1"
     creator="Cyclometer iOS"
     xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v2"
     xmlns:cyc="http://cyclometerapp.com/xmlschemas/VehicleEvent/v1"
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

  <!-- Vehicle pass events recorded as waypoints at rider position when vehicle cleared -->
  <!-- Apps that don't support cyc: namespace will read these as generic waypoints -->
  <wpt lat="36.0726" lon="-79.7920">
    <time>2026-03-31T08:15:23Z</time>
    <name>Vehicle Pass</name>
    <type>vehiclePass</type>
    <extensions>
      <cyc:VehiclePassEvent>
        <cyc:alertLevel>caution</cyc:alertLevel>
        <cyc:riderSpeedKph>28.4</cyc:riderSpeedKph>
        <cyc:estimatedPassSpeedKph>62.1</cyc:estimatedPassSpeedKph>
        <!-- vehicle ground speed, not closing speed; omitted if the vehicle was never observed approaching -->
      </cyc:VehiclePassEvent>
    </extensions>
  </wpt>

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

    </trkseg>
  </trk>
</gpx>
```

**Schema Notes:**
- `gpxtpx:speed` is in **m/s**; `gpxtpx:cad` is **RPM**; `gpxtpx:hr` is integer **BPM**
- Elements are **omitted** (not zero-valued) when no sensor is active
- `cyc:VehiclePassEvent` is a Cyclometer-defined extension. No industry standard exists for vehicle pass events as of v0.4.
- The `cyc:` namespace URI (`http://cyclometerapp.com/xmlschemas/VehicleEvent/v1`) does not need to resolve to a live schema document; it serves as a unique identifier
- Third-party apps that cannot parse `cyc:` elements will still read the `<wpt>` as a generic waypoint with name "Vehicle Pass", preserving basic compatibility

---

## 18. Appendix C — Design Assets

All manual design assets are located in `assets/design/`. The audio specification is in `assets/Audio.md`.

| Asset | Path | Format | Notes |
|---|---|---|---|
| Color tokens | `assets/design/colors.md` | Markdown | 30 semantic tokens, light + dark mode, WCAG AA notes. Source of truth for `Color+Cyclometer.swift`. |
| Audio alert spec | `assets/Audio.md` | Markdown | Three-tone system: All Clear, Warning, Danger. Frequency specs, waveforms, timing, open questions. |
| Primary UI design | `assets/design/Design.sketch` | Sketch | All screens S01–S20. Component specs, radar sidebar visualization. |
| App icon | `assets/design/CyclometerIcon.sketch` | Sketch | App icon artwork and all required iOS size variants. |
| D-DIN Regular | `assets/design/d-din/D-DIN.otf` | OTF | Dashboard body numerics |
| D-DIN Bold | `assets/design/d-din/D-DIN-Bold.otf` | OTF | |
| D-DIN Italic | `assets/design/d-din/D-DIN-Italic.otf` | OTF | |
| D-DIN Condensed | `assets/design/d-din/D-DINCondensed.otf` | OTF | Hero numerics (138pt) |
| D-DIN Condensed Bold | `assets/design/d-din/D-DINCondensed-Bold.otf` | OTF | |
| D-DIN Expanded | `assets/design/d-din/D-DINExp.otf` | OTF | |
| D-DIN Expanded Bold | `assets/design/d-din/D-DINExp-Bold.otf` | OTF | |
| D-DIN Expanded Italic | `assets/design/d-din/D-DINExp-Italic.otf` | OTF | |
| Font license | `assets/design/d-din/SIL Open Font License.txt` | Text | SIL OFL — free to bundle in commercial iOS app |

---

*Cyclometer PRD v0.4.2 · Fourth Review Draft · 2026-07-07*
