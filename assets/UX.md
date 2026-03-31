# Cyclometer — UX Specification
**Version:** 0.1 Stub  
**Date:** 2026-03-31  
**Status:** Awaiting UX Direction  
**Author:** Brian (UX Design)  
**Companion Document:** `PRD.md` — defines *what* each screen must do; this document defines *how* it is structured.

---

## About This Document

This document provides screen-level UX detail for every screen in Cyclometer's screen inventory. Each screen section includes:

- **Purpose** — what the screen accomplishes for the rider
- **Layout** — component hierarchy and spatial organization
- **Components** — individual UI elements with states and annotations
- **Interactions** — gestures, transitions, and edge cases
- **Eyes-Free Considerations** — how the screen behaves when the rider cannot look at it
- **Design Tokens** — which color and typography tokens apply
- **Open UX Questions** — decisions needed before implementation

The screens in this document correspond 1:1 with the Screen Inventory in `PRD.md §7`.

---

## Screen Index

| ID | Screen | Phase | Status |
|---|---|---|---|
| [S01](#s01-onboarding--welcome) | Onboarding — Welcome | MVP | Stub |
| [S02](#s02-onboarding--sensor-pairing) | Onboarding — Sensor Pairing | MVP | Stub |
| [S03](#s03-onboarding--profile-setup) | Onboarding — Profile Setup | MVP | Stub |
| [S04](#s04-home) | Home | MVP | Stub |
| [S05](#s05-active-ride-dashboard) | Active Ride Dashboard | MVP | **Priority — Detailed UX Needed** |
| [S06](#s06-radar-alert--advisory-l1) | Radar Alert — Advisory (L1) | MVP | Stub |
| [S07](#s07-radar-alert--caution-l2) | Radar Alert — Caution (L2) | MVP | Stub |
| [S08](#s08-radar-alert--danger-l3) | Radar Alert — Danger (L3) | MVP | Stub |
| [S09](#s09-ride-paused) | Ride Paused | MVP | Stub |
| [S10](#s10-ride-summary) | Ride Summary | MVP | Stub |
| [S11](#s11-device-management) | Device Management | MVP | Stub |
| [S12](#s12-app-settings) | App Settings | MVP | Stub |
| [S13](#s13-hr-zone-configuration) | HR Zone Configuration | MVP | Stub |
| [S14](#s14-ride-history-list) | Ride History List | Phase 2 | Stub |
| [S15](#s15-ride-detail) | Ride Detail | Phase 2 | Stub |
| [S16](#s16-training-zones-graph) | Training Zones Graph | Phase 2 | Stub |
| [S17](#s17-apple-watch-face) | Apple Watch Face | Phase 2 | Stub |
| [S18](#s18-ar-hud-configuration) | AR HUD Configuration | Phase 3 | Stub |

---

## Global Design Notes

> *To be completed by Brian.*

### Typography Scale
- [ ] Define heading, subheading, metric (large numeral), label, caption scales
- [ ] Specify font: D-DIN (see `assets/d-din/`) for numerics; system font (-apple-system) for UI text

### Spacing System
- [ ] Define base unit and scale (e.g., 4pt base)

### Navigation Pattern
- [ ] Tab bar vs. sidebar vs. full-screen modal flow
- [ ] Ride dashboard: full-screen takeover or pushed view?

### Safe Area Handling
- [ ] Dynamic Island behavior on active ride dashboard
- [ ] Home indicator avoidance on metric tiles

---

## S01 — Onboarding — Welcome

**Phase:** MVP  
**Purpose:** Introduce Cyclometer, establish trust, and request system permissions (Bluetooth, Location, HealthKit, Files).

### Layout
> *To be defined by Brian.*

### Permissions Flow
- Bluetooth (required for BLE sensors)
- Location Always (required for GPS track + background recording)
- HealthKit read (HR, resting HR, max HR, date of birth)
- Files / Documents directory (for GPX export)

### Interactions
> *To be defined by Brian.*

### Open UX Questions
- [ ] Single permission-per-screen carousel, or batched permission request?
- [ ] What happens if the user denies Bluetooth? (Core functionality blocked — how to handle?)
- [ ] Skip / come back later affordance?

---

## S02 — Onboarding — Sensor Pairing

**Phase:** MVP  
**Purpose:** Guide the rider through pairing their BLE sensors: Varia radar, HR strap, and speed/cadence sensor.

### Sensors to Pair
1. Garmin Varia RTL515 or RCT715 (radar — optional but promoted)
2. BLE Heart Rate sensor (optional; Apple Watch used as fallback)
3. BLE Speed / Cadence sensor (optional; GPS used as speed fallback)

### Layout
> *To be defined by Brian.*

### Interactions
- BLE scan + discovered device list
- Tap to pair; confirm pairing
- Skip individual sensor types
- "I'll add sensors later" exit path

### Open UX Questions
- [ ] How are sensor types visually distinguished in the scan list? (icon + sensor type label?)
- [ ] What if multiple sensors of the same type are discovered? (e.g., two HR straps)
- [ ] Order of sensor pairing: radar first (safety), then HR, then speed/cadence?

---

## S03 — Onboarding — Profile Setup

**Phase:** MVP  
**Purpose:** Collect or confirm the rider's HR profile data (resting HR, max HR) for Karvonen zone calculation.

### Data Sources (in priority order)
1. Read from Apple Health (`HKQuantityTypeIdentifierRestingHeartRate`, historical max HR)
2. Age-based estimate (220 − age) when HealthKit max HR unavailable
3. Manual entry by rider

### Layout
> *To be defined by Brian.*

### Interactions
- Display pulled-from-Apple-Health values with edit affordance
- Manual entry form when HealthKit unavailable
- Karvonen zone preview (show zone 1–5 BPM ranges in real-time as values change)

### Open UX Questions
- [ ] Should the zone preview be shown inline on this screen, or is it deferred to S13?
- [ ] How to communicate to the rider that Apple Health is the source of truth and will auto-update?

---

## S04 — Home

**Phase:** MVP  
**Purpose:** Pre-ride hub. Displays last ride summary, active sensor status, and quick-start CTA.

### Layout
> *To be defined by Brian.*

### Key Components
- Sensor status row: radar badge, HR badge, speed/cadence badge (green = connected, amber = not paired, red = paired but not found)
- Last ride summary card: date, distance, duration, avg HR zone
- Start Ride CTA (primary, large, `brPrimary`)
- Navigation to History, Settings

### Open UX Questions
- [ ] Does the home screen show current weather or current time-of-day context?
- [ ] "Recently used routes" card for Phase 1 navigation — or deferred to Phase 2?
- [ ] Sensor status: should tapping a disconnected sensor badge deep-link to S11?

---

## S05 — Active Ride Dashboard

**Phase:** MVP  
**Priority:** HIGH — this is the most complex and safety-critical screen; detailed UX direction required from Brian before implementation begins.

**Purpose:** The primary screen during a ride. Simultaneously displays speed, HR with zone color, cadence, elapsed time, distance, radar arc, and live map. Must be readable in direct sunlight in under one second.

### Layout
> **Brian to define.** Considerations below are provided as structural prompts, not prescriptions.

**Structural Zones to Allocate:**
- Top zone: elapsed time and distance (secondary metrics)
- Primary metric zone: speed (dominant numeral) + cadence
- HR zone: heart rate BPM + zone color indicator + zone label
- Radar arc: semi-circular visualization, positioned for peripheral awareness
- Map zone: live position map — below radar arc, or side-by-side?
- Control zone: pause button (44×44 pt minimum); accessible without looking

**Key Layout Decisions Needed:**
- [ ] Does the live map occupy its own scrollable card, or is it always-visible embedded?
- [ ] Is the radar arc above or below the map? Or does it overlay the map edge?
- [ ] What is the spatial relationship between the radar arc and the HR zone indicator?
- [ ] Does cadence share a row with speed, or does it have its own tile?
- [ ] What does the metric layout look like in landscape orientation? (or is landscape locked out?)
- [ ] Where do sensor source badges appear without cluttering critical metrics?

### Component Details

#### Speed Tile
- Value: large numeral (minimum 64pt; D-DIN preferred)
- Unit: km/h or mph (from UserProfile.preferredUnit)
- Source badge: BLE wheel icon or GPS icon (small, corner of tile)

#### Heart Rate Tile
- Value: BPM numeral
- Zone color: background or left border tint in current zone color (`brHRZone1` – `brHRZone5`)
- Zone label: "Z1 Recovery", "Z2 Endurance", etc.
- Source badge: BLE HR icon or Apple Watch icon

#### Cadence Tile
- Value: RPM numeral
- Source badge: BLE cadence icon
- Empty state: "--" with "Pair Sensor" affordance when no cadence sensor connected

#### Elapsed Time
- HH:MM:SS format
- Running clock; pauses in `paused` state

#### Distance
- Value with unit (km or mi)
- Updates from active speed source (BLE wheel or GPS)

#### Radar Arc
> *Full visual specification to be defined by Brian.*
- Semi-circle representing road behind rider
- Vehicles as dots; position = relative distance; color = closing speed severity
- Empty state: arc present but no dots; border in `brRatingGood`
- Disconnected state: arc grayed; "Radar offline" label

#### Live Map
> *Visual integration with radar arc to be defined by Brian.*
- MapKit view embedded in dashboard
- Current position dot in `brPrimary`
- Heading indicator (direction of travel)
- Route polyline in `brPrimary` if route is loaded
- Heading-up default; toggle to north-up via tap

#### Pause Button
- Minimum 44×44 pt; recommend 60×60 pt for gloved operation
- Position: accessible without moving thumb from natural grip

### Alert State Overlays
Alert states (S06, S07, S08) are applied as overlays on top of this dashboard. See S06–S08.

### Open UX Questions
- [ ] Exact layout grid and component position — Brian to provide via UX.md annotation or Sketch
- [ ] Does the map ever animate to full-screen (e.g., upcoming turn)? Or is it always dashboard-embedded?
- [ ] Landscape mode: supported or locked to portrait?
- [ ] Night / low-light mode: auto-switch to dark mode at dusk, or always follow system?
- [ ] What is the interaction to navigate from active ride to any other screen? (Swipe? Dedicated nav icon?)

---

## S06 — Radar Alert — Advisory (L1)

**Phase:** MVP  
**Purpose:** Communicate the presence of a vehicle in the radar zone at low threat level without disrupting the rider's concentration.

### Visual Treatment
- Peripheral amber tint: thin `brRatingOkay` wash at screen edges (~10% opacity)
- No modal or overlay; dashboard remains fully readable
- Radar arc dot transitions to `brRatingOkay` for the approaching vehicle

### Haptic
- Single `UIImpactFeedbackGenerator` `.light` tap
- Minimum 3 seconds before re-trigger at same level

### Audio
- None

### Open UX Questions
- [ ] How wide is the peripheral amber tint? (Full edge gradient, or just top/bottom?)
- [ ] Should there be a subtle animation (pulse) on the peripheral tint, or is static opacity sufficient?

---

## S07 — Radar Alert — Caution (L2)

**Phase:** MVP  
**Purpose:** Escalate awareness for moderate threat — multiple vehicles or moderate closing speed.

### Visual Treatment
- Amber border pulse: `brRatingOkay` border around screen perimeter, animating in/out at ~1Hz
- Radar arc dot(s) in `brRatingOkay`
- Dashboard metrics remain fully visible

### Haptic
- Double tap, `.medium`, 0.5s interval between taps
- Minimum 3 seconds before re-trigger at same level

### Audio
- None

### Open UX Questions
- [ ] Border pulse: full perimeter, or just sides + bottom (road-awareness metaphor)?
- [ ] Does the L2 state persist until threat drops to L1, or does it decay after a fixed duration?

---

## S08 — Radar Alert — Danger (L3)

**Phase:** MVP  
**Purpose:** Maximum urgency alert for high-speed vehicle approach. Eyes-free must work completely; visual treatment is supplementary.

### Visual Treatment
- Full-screen `brRatingBad` color wash at ~70% opacity over dashboard
- Cannot be dismissed by rider — persists until threat recedes
- Radar arc at full red; vehicle dot(s) prominent

### Haptic
- Continuous rhythmic `.heavy` at 0.3s on / 0.3s off
- Persists until alert level drops below danger threshold

### Audio
- Tone alert (system audio channel)
- Overrides Silent Mode if `UserProfile.overrideSilentModeForL3 == true`
- Tone: distinct from system notification sounds; not jarring but clearly audible
- Tone pattern: [ ] to be defined — single sustained tone, repeating short tones, or escalating pitch?

### Open UX Questions
- [ ] Does any readable text appear on the L3 wash screen? ("Vehicle approaching"?) Or is it color + haptic only?
- [ ] If multiple L3 vehicles are present simultaneously, does the screen treatment change?
- [ ] Tone pattern: define specific tone frequency, duration, and repeat interval

---

## S09 — Ride Paused

**Phase:** MVP  
**Purpose:** Clearly indicate the ride is paused; provide resume and end ride options.

### Layout
> *To be defined by Brian.*

### Key Components
- "PAUSED" indicator (prominent)
- Elapsed time (frozen)
- Distance (frozen)
- Live map (static, showing current position)
- Resume button (primary CTA, `brPrimary`)
- End Ride button (secondary; leads to ride summary)
- Radar arc remains visible (safety persists during pause)

### Open UX Questions
- [ ] Does BLE radar alerting continue during pause? (Recommendation: yes — safety does not pause)
- [ ] Is there a minimum pause duration before "End Ride" appears, to prevent accidental ride termination?

---

## S10 — Ride Summary

**Phase:** MVP  
**Purpose:** Post-ride overview of completed ride with key metrics and GPX export action.

### Layout
> *To be defined by Brian.*

### Key Components
- Map thumbnail (full route trace in `brPrimary`)
- Primary metrics: total distance, total time, avg speed
- HR zone breakdown: time-in-zone bar chart (5 zones, zone colors)
- Average cadence (if cadence sensor was active)
- Radar events count
- GPX Export / Share action (Files app + Share Sheet)
- Save / Done navigation

### Open UX Questions
- [ ] Is the zone breakdown a horizontal bar chart, a stacked bar, or a pie chart?
- [ ] Should the ride summary show a "best" highlight (e.g., longest Z4 interval)?
- [ ] Can the rider rename the ride from this screen?

---

## S11 — Device Management

**Phase:** MVP  
**Purpose:** View and manage all paired BLE sensors; check signal strength; pair new sensors; set sensor priority.

### Layout
> *To be defined by Brian.*

### Sensor Sections
1. Radar (Garmin Varia RTL515 / RCT715)
2. Heart Rate sensor
3. Speed / Cadence sensor
4. Power meter (Phase 3 — shown as "Coming soon" or hidden in MVP)

### Per-Sensor Row
- Sensor name and model (if identifiable from BLE advertisement)
- Connection status dot (green / amber / red)
- Signal strength indicator (RSSI bars)
- Unpair action
- "Add Sensor" row below each category

### Open UX Questions
- [ ] If multiple sensors of the same type are paired, how is active source indicated?
- [ ] Should RSSI be shown numerically (dBm) or as icon bars only?

---

## S12 — App Settings

**Phase:** MVP  
**Purpose:** Configure units, alert behavior, haptic intensity, audio alerts, and Silent Mode override.

### Settings Sections

**Units**
- Distance / speed: Metric (km) | Imperial (miles)
- Wheel circumference (mm) — numeric entry with preset selector

**Navigation**
- Map orientation: Heading-up | North-up
- Turn alert distance: 100m | 200m | 300m

**Radar Alerts**
- Haptic intensity: Light | Medium | Heavy (applies scale to all levels)
- Audio alerts: On | Off
- Override Silent Mode for L3 danger alerts: On | Off (off by default; warning copy required)
- Danger threshold (closing speed): [configurable, default 30 km/h]
- Caution vehicle count threshold: [configurable, default 3]

**Ride Recording**
- Auto-end ride after stationary (minutes): Off | 5 | 10 | 15

### Open UX Questions
- [ ] What warning copy accompanies the Silent Mode override toggle? (Safety implication for other notifications)
- [ ] Should the danger threshold be a slider or a numeric stepper?

---

## S13 — HR Zone Configuration

**Phase:** MVP  
**Purpose:** Display the rider's calculated HR zones; allow manual override of profile values.

### Layout
> *To be defined by Brian.*

### Key Components
- Source indicator: "From Apple Health" or "Manually entered"
- Resting HR field (editable)
- Max HR field (editable; shows Apple Health value and age-based estimate for comparison)
- Calculated zone table: Zone 1–5, BPM range per zone, zone color swatch
- Karvonen formula explanation (brief, collapsible)
- "Refresh from Apple Health" action

### Open UX Questions
- [ ] If Apple Health values are present, are the fields read-only with an edit override, or always editable?
- [ ] Should zone boundaries animate when the rider adjusts resting / max HR values?

---

## S14 — Ride History List

**Phase:** Phase 2  
**Purpose:** Browsable list of all recorded rides.

### Layout
> *To be defined in Phase 2.*

### Per-Row Content (indicative)
- Date and time
- Distance and duration
- Map thumbnail (small)
- Average HR zone color indicator
- Radar event count badge

---

## S15 — Ride Detail

**Phase:** Phase 2  
**Purpose:** Deep view of a completed ride — map replay, HR over time, cadence over time, radar event markers on timeline.

### Layout
> *To be defined in Phase 2.*

### Key Components
- Full map with route trace and radar event markers
- HR zone graph over elapsed time
- Cadence graph over elapsed time
- Radar event timeline with alert level color coding
- GPX re-export action

---

## S16 — Training Zones Graph

**Phase:** Phase 2  
**Purpose:** Training load view — time spent in each HR zone across a configurable recent period (7d / 30d / 90d).

### Layout
> *To be defined in Phase 2.*

---

## S17 — Apple Watch Face

**Phase:** Phase 2  
**Purpose:** Glanceable watch complication and standalone mini-dashboard on Apple Watch.

### Complication Data
- Speed (large)
- HR zone color indicator
- Radar alert indicator (simplified: safe / caution / danger icon)

### Open UX Questions
- [ ] Which complication family sizes to target? (Graphic Circular, Graphic Corner, Graphic Rectangular)
- [ ] Does the watch app function independently (no iPhone required during ride)?

---

## S18 — AR HUD Configuration

**Phase:** Phase 3  
**Purpose:** Configure the heads-up display layout for ENGO 2 / ActiveLook AR glasses.

### Layout
> *To be defined in Phase 3 AR specification document.*

### Constraints
- Monochrome display (~300×256px)
- 1Hz update rate
- Icon-based alert encoding (no color dependency)

---

*Cyclometer UX Specification v0.1 · Stub · 2026-03-31 · Awaiting UX direction from Brian*
