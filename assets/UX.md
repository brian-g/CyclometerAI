# Cyclometer — UX Specification
**Version:** 0.6  
**Date:** 2026-03-31  
**Updated:** 2026-05-21 — Dashboard vision rewritten; S05.4 reframed as factory default; S05.5 removed  
**Status:** In Progress  
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

## Source Files

All design artifacts are in `assets/design/`. These files are the source of truth for visual design; this document provides annotation and interaction specification to accompany them.

| Asset | Path | Contents |
|---|---|---|
| Primary UI design | `assets/design/Design.sketch` | Screen layouts and component specs for S01–S20 |
| App icon | `assets/design/CyclometerIcon.sketch` | App icon artwork, all iOS size variants |
| Color tokens | `assets/design/colors.md` | 30 semantic tokens, light + dark mode hex values, WCAG AA notes |
| D-DIN fonts | `assets/design/d-din/` | D-DIN family (Regular, Bold, Italic, Condensed, Condensed Bold, Exp, Exp Bold, Exp Italic) — SIL Open Font License. Currently only need the Condensed for this project. |
| Icons | `assets/design/icons` | Set of SVG icons that should be added as SF Symbols extensions. |

> When implementing any screen, open `assets/design/Design.sketch` first. This UX.md provides interaction annotation and open questions that supplement the Sketch layouts — it is not a standalone specification.

---

## Screen Index

| ID | Screen | Phase | Status |
|---|---|---|---|
| [S01](#s01-onboarding--welcome) | Onboarding — Welcome | MVP | Complete |
| [S02](#s02-onboarding--sensor-pairing) | Onboarding — Sensor Pairing | MVP | Complete |
| [S03](#s03-onboarding--profile-setup) | Onboarding — Profile Setup | Cut | Complete |
| [S04](#s04-home) | Home | Deferred | Deferred |
| [S05](#s05-active-ride-dashboard) | Active Ride Dashboard | MVP | **Priority — Detailed UX Needed** |
| [S05.1](#s051-start-sheet) | Start Sheet | MVP | Priority |
| S05.2 | Route Selector | Phase 2 | Stub |
| [S05.3](#s053-active-ride-accessory) | Active Ride Accessory | MVP | Complete — refer to prototype |
| S05.4 | Widget Layout — Factory Default | MVP | Grid resolved — see S05 |
| [S05.5](#s055) | Widget Layout 2 | Removed | — |
| [S06](#s06-radar-alert) | Radar Alert | MVP | Stub |
| [S07](#s07-dashboard-customization) | Dashboard Customization | Phase 2 | Stub |
| [S08](#s08-add-widget) | Add Widget | Phase 2 | Stub |
| [S09](#s09-ride-paused) | Ride Paused | MVP | Stub |
| [S10](#s10-ride-summary) | Ride Summary | MVP | Stub |
| [S11](#s11-device-management) | Device Management | MVP | Stub |
| [S12](#s12-app-settings) | App Settings | MVP | Stub |
| [S13](#s13-hr-zone-configuration) | HR Zone Configuration | Deprecated | Stub |
| [S14](#s14-ride-history-list) | Ride History List | Phase 2 | Stub |
| [S15](#s15-ride-detail) | Ride Detail | Phase 2 | Stub |
| [S16](#s16-training-zones-graph) | Training Zones Graph | Cut | Stub |
| [S17](#s17-apple-watch) | Apple Watch | Phase 2 | Stub |
| [S18](#s18-ar-hud-configuration) | AR HUD Configuration | Phase 3 | Stub |
| [S19](#s19-route-management) | Route Management | Phase 2 | Stub |
| [S20](#s20-route-detail) | Route Detail | Phase 2 | Stub |

---

## Global Design Notes

The design should be aligned with Apple HIG and use standard SwiftUI components and layout. All screens have a dark and light mode.

## Alignment

- Numbers arranged vertically and of the same unit must always be aligned to the right
- Horizontal text should always be baseline aligned unless otherwise noted

### Typography Scale

The type ramp is scalable on the dashboard depending on the device and scale using Apple Dynamic Type. Cyclometer should be able to run on any iPhone that supports iOS 26. Use the standard font style on iOS, SF Pro Rounded.

Units should always be set baseline aligned with their corresponding values.

- [ ] Define heading, subheading, metric (large numeral), label, caption scales
- [ ] Specify font: D-DIN Condensed (see `assets/design/d-din/`) for hero number

### Color Tokens
- All semantic color token names and hex values are defined in `assets/design/colors.md`
- Use `br`-prefixed token names (e.g., `brPrimary`, `brHRZone3`, `brRatingBad`) in all annotations
- Do not specify raw hex values in this document; reference token names only

### Spacing System
- [ ] Define base unit and scale (e.g., 4pt base)
- [ ] Do not override the padding on any page but the Dashboard. The dashboard should use the 4pt padding.

### Opacity Tokens
- Opacity values must be tokenized, not inline literals. Tokens live in `DesignSystem/Opacity.swift`.
- `watermark` (0.2) — background sparkline / watermark behind a dashboard hero number (e.g. W1 speed history).

### Navigation Pattern
The navigation in the app will follow standard iOS application guidelines patterns. In this case, the application to model is the Apple Music app. The bottom TabView should have the following 3 items:

- Rides
- Routes
- Settings

There will be a button in a toolbar at the top-right of the screen to start a ride. The toolbar button should have:

- Accessibility label: Start ride
- Icon: play-fill
- Hidden when a ride is active
- When pressed, will display the Start Ride sheet.

When a ride is active, the Start ride toolbar item will be hidden. The Routes tab is present in the tab bar during MVP but shows a "Coming Soon" placeholder view until Phase 2 content is ready.

### Widget Size Convention

Widget sizes are expressed as **WxH** (width × height) in grid units. The dashboard grid is 2 columns × 7 rows. Cell dimensions are approximately 201×96pt on iPhone 17 Pro.

| Size | Grid units | Approximate pt |
|---|---|---|
| 1x1 | 1 col × 1 row | 201 × 96 |
| 2x1 | 2 col × 1 row | 402 × 96 |
| 2x2 | 2 col × 2 rows | 402 × 195 |

This convention matches the frame naming in `Design.sketch`.

### Safe Area Handling
- [x] Dynamic Island behavior on active ride dashboard. If the map is at the top or at the bottom in a 2x2 configuration, the map will bleed into the safe area.
- [x] Home indicator avoidance on metric tiles

---

## S01 — Onboarding — Welcome

**Phase:** MVP  
**Purpose:** Introduce Cyclometer, establish trust, and request system permissions (Bluetooth, Location, HealthKit, Motion and Fitness, Files).

### Layout
> *Refer to `assets/design/Design.sketch` — S01.*

### Permissions Flow
- Bluetooth (required for BLE sensors)
- Location Always (required for GPS track + background recording)
- HealthKit read (HR, resting HR, max HR, date of birth)
- Motion and Fitness (required for activity detection)
- Files / Documents directory (for GPX export)

### Interactions
For each permission item, when the user taps it, the system permission prompt will be displayed. When permission has been successfully granted for an item, the circle to the left of the item will become a filled circular checkmark. If they deny a permission, it will be a red X.

If the user blocks Bluetooth, Location, or Motion and Fitness, they will not be able to proceed. Health and Files are optional; that functionality will not be available if denied. There is no skip affordance — users who have denied a required permission must go to iOS Settings to re-enable it.

### Open UX Questions
- [x] Single permission-per-screen carousel, or batched permission request? Single permission request per item, all shown on the same screen.
- [x] What happens if the user denies Bluetooth? Cannot proceed.
- [x] Skip / come back later affordance? No.

---

## S02 — Onboarding — Sensor Pairing

**Phase:** MVP  
**Purpose:** Guide the rider through pairing their BLE sensors: Varia radar, HR strap, and speed/cadence sensor. The list of sensors used in this onboarding page should also be reused in Settings.

### Sensors to Pair
1. Garmin Varia RTL515 or RCT715 (radar — optional but promoted)
2. BLE Heart Rate sensor (optional; Apple Watch used as fallback)
3. BLE Speed / Cadence sensor (optional; GPS used as speed fallback)
4. Power meters (future)

### Layout
> *Refer to `assets/design/Design.sketch` — S02.*

### Interactions
- BLE scan + discovered device list
- Tap "Pair" for each device; confirm pairing
- "Next" without pairing any sensor is a valid exit path

### Open UX Questions
- [x] How are sensor types visually distinguished in the scan list? Icon. SVG icons are in the repo under `assets/icons/`.
- [x] What if multiple sensors of the same type are discovered? Both shown; user chooses.
- [x] Order of sensor pairing? Any order; see the mockup.

---

## S03 — Onboarding — Profile Setup

**Phase:** Cut  
**Purpose:** Collect or confirm the rider's HR profile data (resting HR, max HR) for Karvonen zone calculation.

### Data Sources (in priority order)
1. Read from Apple Health (`HKQuantityTypeIdentifierRestingHeartRate`, historical max HR)
2. Age-based estimate (220 − age) when HealthKit max HR unavailable
3. Manual entry by rider

### Layout
> *Refer to `assets/design/Design.sketch` — S03.*

### Interactions
- Display pulled-from-Apple-Health values with edit affordance
- Manual entry form when HealthKit unavailable
- Karvonen zone preview (show zone 1–5 BPM ranges in real-time as values change)

### Open UX Questions
- [ ] Should the zone preview be shown inline on this screen, or is it deferred to S13?
- [ ] How to communicate to the rider that Apple Health is the source of truth and will auto-update?

---

## S04 — Home

**Phase:** Deferred  
**Purpose:** Pre-ride hub. Displays last ride summary, active sensor status, and quick-start CTA.

### Layout
> *Refer to `assets/design/Design.sketch` — S04.*

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

## S05.1 — Start Sheet

**Phase:** MVP  
**Purpose:** Allow user to quickly set up a ride and provide sensor status.

### Layout

> *Refer to `assets/design/Design.sketch` — S05.1.*

### Key Components

- Group: Ride Setup
  - Route picker (Phase 2)
  - Bike picker (Phase 2) — selecting a bike selects its sensors and its fitted wheelset, so the sensor list below and the wheel circumference used for the ride both follow this control. Where a bike has more than one wheelset, the fitted one is picked here too. See DataModel.md §3.9

- Group: Sensors
  - Sensor type (icon)
  - Sensor name
  - Status (Connected, Searching)
  - When Connected, the battery level if supported

### Open UX Questions

- [ ] TBD

---

## S05.2 — Route Picker

**Phase:** Phase 2  
**Purpose:** Allow user to select a route for the ride.

### Layout

> *Refer to `assets/design/Design.sketch` — S05.2.*

### Key Components

- Route picker
- Bike picker — drives which sensors and which wheelset the ride uses (see S05.1)
- List of sensors and status

### Open UX Questions

- [ ] TBD

---

## S05.3 — Active Ride Accessory

**Phase:** MVP  
**Purpose:** When the Active Ride Dashboard full-screen sheet is swiped down to a minimized state, the ride is represented by the Active Ride Accessory — a compact strip that appears just above the TabBar using `tabViewBottomAccessory`. The pattern is identical to the mini-player in Apple Music.

### Implementation Reference

> The canonical implementation is `ActiveRideAccessoryView` in the prototype at `Test-ToolbarAndAccessoryView/Test-ToolbarAndAccessoryView/ContentView.swift`. For visual layout, see `assets/design/Design.sketch` — S05.3.

The accessory is enabled via:

```swift
.tabViewBottomAccessory(isEnabled: currentRide != nil) {
    if let currentRide {
        ActiveRideAccessoryView(ride: currentRide) {
            dashboardRide = currentRide   // re-presents the full-screen dashboard
        }
        .padding(.horizontal, 4)
    }
}
```

### Layout

The accessory is a full-width horizontal strip. Internal layout (left to right):

- **Leading progress ring** — `OpenRingProgressView`: a donut-style Swift Charts `SectorMark` showing route completion percentage. The visible arc spans 84% of the circle with a gap at the bottom; the completed segment uses `brPrimary` tint, the remaining segment uses `.secondary` at 22% opacity. The percentage integer is displayed in `.caption2.weight(.semibold)` at the center. When no route is loaded, progress is `0.0` (ring shows empty). Frame: 42×42pt.
- **Live stats** — two `HeroNumber` views at `.small` size (34pt D-DIN Condensed), `.horizontal` layout, showing current distance and current speed with units from `UserProfile.preferredUnit`. Stats update at 1Hz matching the dashboard.
- **Spacer**
- **Open button** — `.borderedProminent` button style, label "Open". Taps re-present the full-screen `RideDashboardView`.

### Behavior

- Visible **only when a ride is active** (state = `.active` or `.paused`).
- When the ride is paused, stats display the last recorded values and do not update.
- When the rider taps "Open" (or taps anywhere on the strip in future iteration), the full-screen dashboard is re-presented via `fullScreenCover`.
- The TabBar remains visible and functional beneath the accessory — the rider can navigate to Routes or Settings without losing the active ride.
- The `tabViewBottomAccessory` API requires iOS 26.

### Eyes-Free Considerations

The accessory strip is a passive display. The rider uses it only when they have consciously minimized the dashboard. The primary safety-critical path (alerts, haptics, audio) continues uninterrupted regardless of whether the dashboard is full-screen or minimized.

### Open UX Questions

- [x] Should the accessory show a radar alert indicator (small colored dot) when a threat is active, so the rider can see alert state without reopening the dashboard? No.
- [x] Should the progress ring be replaced with a bicycle SF Symbol icon when no route is loaded, matching the Sketch design? Yes, that is correct.

---

## S05 — Active Ride Dashboard

**Phase:** MVP  
**Priority:** HIGH — this is the most complex and safety-critical screen; detailed UX direction required from Brian before implementation begins.

**Purpose:** The primary screen during a ride. Simultaneously displays speed, HR with zone color, cadence, elapsed time, distance, radar sidebar, and live map. Must be readable in direct sunlight in under one second.

### Dashboard Vision

The Cyclometer dashboard is not a static screen — it is a **rider-configured instrument panel**. The design philosophy is borrowed from professional cycling computers and adapted for the iPhone form factor: the rider decides which data matters to them, at what prominence, on how many pages. The app’s role is to make that configuration effortless and to make every widget instantly readable mid-ride, in sunlight, at a glance.

The `S05 - Active Ride Dashboard (don’t use)` frame in Design.sketch captures this vision in its fullest compositional form: a speed hero number dominating the top with a watermark area chart behind it, secondary metrics occupying the mid-section at equal visual weight, a HR zone donut coexisting with a live BPM readout, and a full-width map anchoring the bottom. A sensor status strip with small-icon indicators for each connected source (radar, HR, GPS, cadence, power, AR glasses) sits between the Dynamic Island and the top grid row. That composition is one valid arrangement of the underlying system — not the system itself. It is marked “don’t use” because it was created directly in Sketch as a composition rather than assembled from the widget grid — it’s a vision artefact, not an implementation target.

The real system is the **widget grid**: a 2-column × 7-row canvas the rider populates, rearranges, and pages through. S05.4 in Design.sketch is the **factory default** — the arrangement a new user sees before any customisation. It is a starting point chosen to serve the broadest range of riders, not a constraint on what the dashboard can become.

**Grid**

The grid always occupies the full screen height between the Dynamic Island and the bottom toolbar. It is never scrollable. Row height is calculated dynamically so that all 7 rows fill the available display height for the current device. Cell dimensions are approximately 201×96pt on iPhone 17 Pro.

**Widget sizing** Dimensions are expressed as *columns × rows* (e.g., `2×2` spans 2 columns and 2 rows). Supported sizes range from `1×1` (single cell) up to `2×2`. A widget may not exceed the grid boundaries (except for the map), and no two widgets may share a cell.

**Adaptive content** Each widget is size-aware. At `1×1` it surfaces the single most critical value — the number readable in under a second. At `2×1` it adds a secondary metric or sparkline. At `2×2` it exposes the full picture: hero number, trend watermark, supporting stats, and contextual detail. The content hierarchy within each widget is defined in the widget specifications below.

**Multiple pages** The dashboard supports multiple swipeable pages, each with its own independent widget layout. Pages are managed through the customisation flow (S07). The paging indicator is always visible at the bottom of the grid when there are multiple pages defined. The factory default shows two paging dots, signalling that multi-page use is a first-class pattern, not an edge case. The second page has a single map widget. 

**Customisation** The rider configures the dashboard by choosing which widgets to display, their sizes, and their positions. The layout must satisfy:
- All widgets fit within the 2-column × 7-row boundary
- No two widgets overlap
- The grid remains full-height and non-scrollable on all supported devices

**Map widget — safe area bleed** When the map is placed in row 1-2 (top) or rows 6–7 (bottom) of the grid, its rendering extends past the standard content area and bleeds into the iOS safe zones — beneath the Dynamic Island at the top, or beneath the home indicator at the bottom. All interactive controls and data labels within the map widget must remain inside safe area bounds.

**Empty cells** Any unoccupied cells render as empty space with no content and no interactive behaviour.

**Grabber** A minimal grabber-style strip sits between the Dynamic Island and the top grid row. This allows the user to minimize the ride and look at other aspects of the app while riding (typically while stopped).

### Factory Default — S05.4

> `S05.4 - Widget Layout` in Design.sketch is the factory default grid, verified by reading layer names directly via the Sketch MCP API. Widget visual design is defined per widget below and in the standalone widget frames (`W1 – Speed (2x2)`, `W1 – Speed (2x1)`, `W1 – Speed (1x1)`, `W2 – Avg Speed (1x1)`, etc.).

This is the arrangement every new user sees. It demonstrates the full range of widget sizes available and is immediately useful without any configuration.

| Row(s) | Left column | Right column | Widget |
|---|---|---|---|
| 1–2 | Speed | Speed (continued) | W1 — 2×2 |
| 3 | HR | HR Zones | W4, W12 — 1×1 |
| 4 | Radar | Pace | W7, W11 — 1×1 |
| 5 | Cadence | Weather | W5, W10 — 1×1 |
| 6–7 | Map | Map (continued) | W8 — 2×2 |

**Rationale for factory choices:**
- W1 Speed 2×2 leads — the metric every rider checks most. The 2×2 size surfaces the hero number plus distance, duration, max, and average speed without a glance away.
- W4 HR and W12 HR Zones share row 3 — physiology together, neither dominant.
- W7 Radar at row 4 left — in the thumb zone; adjacent to HR so safety and effort are perceived together peripherally.
- W8 Map 2×2 at the bottom bleeds into the home indicator safe area, maximising map real estate.

### Layout

**Structural Zones:**

- Widgets (full screen, no intrinsic padding — widgets extend to screen edges)
- Dashboard paging indicator
- Bottom Toolbar

**Widget Grid**

The dashboard divides the phone screen into 7 rows × 2 columns. Widget sizes follow the WxH convention (see Global Design Notes). Each widget scales horizontally and vertically to fill its allocated cells. Empty cells are left blank — no placeholder or background.

**Dashboard Paging**

Multiple dashboard pages are supported. Pages are added automatically (SpringBoard model). The paging indicator is always visible. See S07 for editing behavior.

**Bottom Toolbar**

Toolbar buttons shown based on ride state:

| Button | Shown when |
|---|---|
| Pause | Ride is active |
| Sensor | One or more paired sensors not found |
| Resume | Ride is paused |
| Finish | Ride is paused |
| Bell | Always |

All toolbar buttons use `.buttonStyle(.glass)` (iOS 26), `.labelStyle(.iconOnly)`, and a 52×52pt frame. The toolbar uses `.sharedBackgroundVisibility(.hidden)`.

**Key Layout Decisions:**
- [x] S05.4 factory default layout resolved — see table above; rider-customisable after first launch
- [x] S05.5 removed — pages beyond page 1 are rider-defined, not factory-specified
- [x] Landscape locked to portrait ✅
- [x] Sensor source badges: none ✅
- [x] Map widget: full-screen sheet on tap; no auto-expand ✅
- [x] Night mode: follow system ✅

### Widget Details

The basic building block of all widgets is the **hero number**. Defined as Sketch symbols: `large-hero`, `medium-hero`, `small-hero`. The SwiftUI implementation is the `HeroNumber` view in the prototype.

**Hero number sizes (D-DIN Condensed):**

Due to differences in phone sizes, some of the numbers will increase or decrease to fit. These sizes should be considered proportional to the widget size based on the cap-height of the character. For example, the cap-height for a 68pt medium-hero is 48pt. This leaves 24pt above and below the number or a scale of .5x for the font size of medium. GeometryReader() will need to be used to correctly scale. This is probably going to need some experimentation to understand if a linear scale would be used between the type cap-height to the size of widget.

| Symbol | Value pt | Unit pt | Notes |
|---|---|---|---|
| `large-hero` | 136 | 20 | Used as the primary value in 2x2 widgets |
| `medium-hero` | 68 | 20 | Secondary values |
| `small-hero` | 34 | 20 | Compact values; label shown below, right-aligned |

- Units are baseline-aligned with their value
- Optional label: `.caption`, uppercased, 16pt
- Each widget exposes a label modifier; the label is hidden on 2x2 widgets
- Tapping any widget opens a detail sheet for that metric category

---

#### W1 — Speed

**Sizes:** 2x2, 2x1, 1x1

- Primary value: `large-hero`; unit: km/h or mph (`UserProfile.preferredUnit`)
- Watermark speed history graph (area line behind the numbers)
- 2x1, 2x2: Max speed for ride (`small-hero`, labeled "MAX")
- 2x1, 2x2: Current average speed with directional arrow indicating above/below average (`small-hero`, labeled "AVG")
- 2x2 only: Ride duration (`medium-hero`)
- 2x2 only: Ride distance (`medium-hero`)
- Sheet: Ride metrics

---

#### W2 — Average Speed

**Sizes:** 1x1

- Primary value: rolling average speed, excluding stopped time
- Unit: km/h or mph
- Watermark speed history graph
- Sheet: Ride metrics

---

#### W3 — Duration

**Sizes:** 1x1

- Primary value: elapsed ride time, excluding stopped time; format HH:MM:SS
- No unit
- Sheet: Ride metrics

---

#### W4 — Heart Rate

**Sizes:** 2x1, 1x1

- Value: current BPM
- Zone color treatment: background or left-border tint in current zone color (`brHRZone1`–`brHRZone5`)
- Zone label: "Z1 Recovery", "Z2 Endurance", "Z3 Tempo", "Z4 Threshold", "Z5 VO₂ Max"
- Empty state: "--" with "Pair Sensor" affordance (navigates to S11)
- Sheet: Heart rate

---

#### W5 — Cadence

**Sizes:** 2x1, 1x1

- Value: current RPM
- Empty state: "--" with "Pair Sensor" affordance (navigates to S11)
- Sheet: Ride metrics

---

#### W6 — Distance

**Sizes:** 1x1

- Value with unit (km or mi); from active speed source (BLE wheel or GPS)
- Sheet: Ride metrics

---

#### W7 — Radar

**Sizes:** 2x2, 2x1, 1x1

- 24pt-wide vertical strip on the right edge representing the road behind the rider
- Vehicles as car icons; vertical position = relative distance (closer = lower); icon color = closing speed severity
- Background: `brRatingOkayBg` / `brRatingBadBg` by alert level; neutral/transparent at L0
- Layer naming in Design.sketch: background (strip bg), `critical` (L3 vehicle icon), `warning` (L2 vehicle icon), `car` (L1/neutral vehicle icon)
- Empty state (radar paired, no vehicles): strip present, no icons, `brRatingGood` neutral
- Disconnected state (was paired, lost signal): strip grayed, "Radar offline" label
- Hidden entirely when no radar device is paired
- Sheet: Radar detail

---

#### W8 — Map

**Sizes:** 2x2, 2x1, 1x1

- MapKit view embedded in the widget
- Current position dot in `brPrimary`; heading indicator
- Route polyline in `brPrimary` when a route is loaded
- Heading-up by default; tap toggles to north-up
- When positioned in the first or last row of the grid, the map extends into the safe area
- Sheet: Full-screen map

---

#### W9 — Directions

**Sizes:** 2x2, 2x1, 1x1

- Displays next turn maneuver icon and distance to turn
- Empty state when no route is loaded: hidden or shows "No Route"
- Sheet: Map

---

#### W10 — Weather

**Sizes:** 2x2, 2x1, 1x1

- Current temperature with unit
- Wind direction indicator (arrow rotated to bearing) and wind speed
- Sheet: Weather details

---

#### W11 — Pace

**Sizes:** 2x2, 2x1, 1x1

- Current pace in min/mi or min/km (`UserProfile.preferredUnit`)
- Sheet: Ride metrics

---

#### W12 — Zones

**Sizes:** 2x2, 2x1, 1x1

- HR zone distribution chart: time spent in each zone for the current ride
- Zone colors: `brHRZone1`–`brHRZone5`
- Empty state when no HR source active: "--"
- Sheet: Heart rate

---

### Open UX Questions
- [x] S05.4 factory default layout resolved — see table above.
- [x] S05.5 removed — pages beyond page 1 are rider-defined, not factory-specified.
- [x] Should the Sensor toolbar button use a specific SF Symbol to indicate which sensor is missing? Yes, it should just use sensor.tag.radiowaves.forward.fill with a badge.

---

## S06 — Radar Alert

**Phase:** MVP  
**Purpose:** Communicate the presence and severity of approaching vehicles via the radar sidebar visualization and escalating haptic/audio alerts.

> See `assets/design/Design.sketch` — S06 for the visual design. The sidebar is implemented as W7 within the dashboard widget grid.

### Visual Treatment

- A 24pt-wide strip on the right edge of the dashboard, present only when a radar device is paired
- Car icons represent vehicles; vertical position encodes relative distance (top = near, bottom = far)
- Background layer named `background` in Sketch; tinted `brRatingOkayBg` / `brRatingBadBg` by alert level; neutral at L0
- Vehicle icons named `car` (neutral/L1), `warning` (L2), `critical` (L3) in Sketch; colored `brRatingOkay` / `brRatingBad` accordingly

### Haptic

- Minimum 3 seconds before re-trigger at same level

- **L1 — Advisory:** Single `UIImpactFeedbackGenerator` `.light` tap

- **L2 — Warning:** Double `UIImpactFeedbackGenerator` `.medium` tap, 0.3s between taps

- **L3 — Danger:** Core Haptics pattern — three 0.14s `HapticContinuous` bursts at full intensity and sharpness:

  ```json
  {
      "Version": 1.0,
      "Pattern": [
          { "Event": { "Time": 0.0,  "Duration": 0.14, "EventType": "HapticContinuous", "EventParameters": [{ "ParameterID": "HapticIntensity", "Value": 1.0 }, { "ParameterID": "HapticSharpness", "Value": 0.9 }] } },
          { "Event": { "Time": 0.22, "Duration": 0.14, "EventType": "HapticContinuous", "EventParameters": [{ "ParameterID": "HapticIntensity", "Value": 1.0 }, { "ParameterID": "HapticSharpness", "Value": 0.9 }] } },
          { "Event": { "Time": 0.44, "Duration": 0.14, "EventType": "HapticContinuous", "EventParameters": [{ "ParameterID": "HapticIntensity", "Value": 1.0 }, { "ParameterID": "HapticSharpness", "Value": 0.9 }] } }
      ]
  }
  ```

### Audio

See `Audio.md` for the canonical specification of all three tones (All Clear, Warning, Danger). The sox generation commands, frequencies, waveforms, and jersey-pocket audibility test requirements are defined there and are the source of truth.

### Open UX Questions
- [ ] At what specific closure rates (km/h delta) should L1, L2, and L3 thresholds be set?
- [ ] Should there be a subtle pulse animation on the peripheral screen tint, or is static opacity sufficient? Static

---

## S07 — Dashboard Customization

**Phase:** Phase 2  
**Purpose:** Allow the rider to customize dashboard widget placement and add additional dashboard pages.

### Interaction

Modeled on SpringBoard widget editing:

1. Long press on the dashboard enters customization mode
2. Existing widgets wiggle and display a "minus" remove button at the upper-left corner
3. The navigation area shows an "Add" button (upper left) and "Done" (upper right)
4. A blank page is automatically appended; rider can swipe to it to place widgets. Empty pages are removed on exit.
5. "Add" opens the Add Widget sheet (S08)

### Open UX Questions

- [ ] TBD

---

## S08 — Add Widget

**Phase:** Phase 2  
**Purpose:** Display all available widgets and allow the rider to add one to the dashboard. Widgets shown with size previews.

### Interaction

TBD

### Open UX Questions

- [ ] TBD

---

## S09 — Ride Paused

**Phase:** MVP  
**Purpose:** Clearly indicate the ride is paused; provide Resume and Finish options.

### Interaction

When a ride is paused, elapsed time stops incrementing. All sensors continue recording (GPS, BLE radar, HR, cadence). The dashboard bottom toolbar replaces the Pause button with Resume and Finish buttons. The Bell button is always shown. Finish requires confirmation before ending the ride.

The visual dashboard is otherwise unchanged — all metric widgets continue displaying the last recorded values.

> Implementation reference: `RideDashboardView` in the prototype manages this state via `@State private var isPaused`. The toolbar uses `if isPaused { Resume + Finish } else { Pause }`. The Finish confirmation uses `.alert("Finish Ride", ...)`.

### Open UX Questions
- [x] Does BLE radar alerting continue during pause? Yes — all sensors continue.
- [x] Minimum pause duration before Finish appears? No — Finish is always shown when paused; confirmation dialog prevents accidental termination.

---

## S10 — Ride Summary

**Phase:** MVP  
**Purpose:** Post-ride overview of completed ride with key metrics.

### Layout
> *Refer to `assets/design/Design.sketch` — S10.*

### Key Components
- Map thumbnail (full route trace in `brPrimary`; placeholder in Design.sketch)
- Primary metrics: total distance, total time, avg speed
- Elevation profile
- HR zone breakdown (pie chart)
- Average cadence (if cadence sensor was active during the ride)
- Radar events count / vehicle pass count
- Rename field: tapping the ride title focuses the field and opens the keyboard; defaults to route name
- **Sync button** — taps present the Service Sync sheet (see below)
- Done navigation

> **Note:** The GPX file is written automatically at ride end and is available via the iOS Files app in the app's `Documents/Rides/` directory. No explicit export action is shown on this screen.

### Service Sync Sheet (Phase 2)

Presented as a `.sheet` when the rider taps Sync. Lists all enabled `ConnectedService` records from `AppPreferences` as toggleable rows. Rider selects which services to send the ride to and taps "Sync."

- Each service row shows: service icon, service name, account display name (e.g. "brian@strava.com"), toggle
- All connected services default to selected
- After tapping Sync, each row shows an in-progress indicator, then a checkmark (success) or warning icon (failure)
- Failed syncs show an error message and a "Retry" affordance per service
- Tapping Done dismisses the sheet regardless of sync status; incomplete syncs can be retried from Ride History (S14) via the Sync swipe action

### HKWorkout (automatic)

An `HKWorkout` is written to Apple Health automatically when the ride ends, before the summary screen is presented. No user action required. The ride appears in the iOS Fitness app and counts toward Activity rings.

### Open UX Questions
- [x] Zone breakdown chart type? Pie chart
- [x] Ride summary highlights? Enhanced after user feedback
- [x] Rider can rename ride from this screen? Yes — tapping the title field opens the keyboard
- [ ] Should the sync sheet show estimated upload size or time? TBD
- [ ] If HKWorkout write fails (HealthKit permission revoked), should the rider be notified? TBD

---

## S11 — Device Management

**Phase:** MVP  
**Purpose:** View and manage all paired BLE sensors; pair new sensors.

### Layout
> *Refer to `assets/design/Design.sketch` — S11.*

### Sensor Sections
1. Radar (Garmin Varia RTL515 / RCT715)
2. Heart Rate sensor
3. Speed sensor
4. Cadence sensor
5. Power meter (Phase 3 — hidden in MVP)

### Per-Sensor Row
- Sensor name and model (from BLE advertisement if identifiable)
- Connection status
- Pair / Unpair action
- Unpaired sensors sorted to the top
- When pairing a sensor with multiple profiles (e.g., combined speed+cadence), the rider is prompted to choose which type it represents

### Open UX Questions
- [x] Multiple sensors of same type: active source by connection order — first wins.
- [x] RSSI display: none.

---

## S12 — App Settings

**Phase:** MVP  
**Purpose:** Configure units, wheel size, alert behavior, haptic intensity, audio alerts, and accounts.

### Settings Sections

**General**
- Units: Metric (km) | Imperial (miles) [Defaults from iOS]
- Wheel circumference (mm) — numeric entry with preset selector. One app-wide value in MVP. Phase 2 moves this off the Settings screen: circumference belongs to a wheelset, a wheelset belongs to a bike, and the rider has several of each (DataModel.md §3.9). Expect this row to become a "Bikes" navigation link rather than gaining more controls in place
- Auto-pause
- Auto-dim
- Set Do Not Disturb
- Sensors (navigates to S11)

**HR Zones**
- Each zone listed with a Stepper control for adjustment
- Footer: "HR Zone data is derived from data collected by Apple Health."

**Accounts**
- List of connected accounts (Strava, Ride with GPS, etc.)
- Each row navigates to account detail (S12.1)
- Last row: "Add Account" with confirmation dialog for service selection

**About**
- Version (read from bundle, shown as `CFBundleShortVersionString (CFBundleVersion)`)
- Privacy Policy (navigates to inline policy view)

### Open UX Questions
- [x] Silent Mode override toggle: not a setting at this time.
- [x] Danger threshold: not a setting at this time.

---

## S13 — HR Zone Configuration

**Phase:** Deprecated — functionality moved to S12 App Settings (HR Zones section)

### Layout
> *Refer to `assets/design/Design.sketch` — S13 (deprecated).*

---

## S14 — Ride History List

**Phase:** Phase 2  
**Purpose:** Browsable list of all recorded rides.

### Layout
> *Refer to `assets/design/Design.sketch` — S14.*

### Per-Row Content
- Map thumbnail (56×56pt, rounded corners). The thumbnail will have to be captured at the completion of a ride. It will be a performance issue if a live map view is shown for each row. 
- Ride name and date/time (using relative dates for the previous week)
- Distance (`HeroNumber` small) and elapsed time (D-DIN Condensed 20pt)
- Swipe actions: leading — Sync (blue), Make Route (green); trailing — Delete (red, destructive)

### Empty State

When the ride list is empty, use `ContentUnavailableView`:

```swift
ContentUnavailableView {
    Label("No Rides Yet", systemImage: "figure.outdoor.cycle")
} description: {
    Text("Start a ride to see it appear here.")
} actions: {
    Button("Start New Ride") {
        isPresentingNewRide = true
    }
}
.frame(maxWidth: .infinity, minHeight: 220)
.listRowBackground(Color.clear)
```

---

## S15 — Ride Detail

**Phase:** Phase 2  
**Purpose:** Deep view of a completed ride — map, HR over time, cadence, elevation, Strava segments.

### Layout
> *Refer to `assets/design/Design.sketch` — S15 when available.*

### Key Components
- Full-width MapKit view (240pt height, rounded corners, inset to list edges)
- Elevation profile chart (Swift Charts, AreaMark + LineMark in `brPrimary`)
- Stats section: avg/max speed, avg/max cadence
- HR zone graph over elapsed time
- Strava segments list: name, distance, best time + date
- GPX re-export action
- Create route action

---

## S16 — Training Zones Graph

**Phase:** Cut  
**Purpose:** Time-in-zone breakdown across recent rides. Cut — does not align with the app's goals.

---

## S17 — Apple Watch

**Phase:** Phase 2  
**Purpose:** Standalone ride dashboard on Apple Watch (not a complication-only target).

### Open UX Questions
- [x] Which complication family sizes? This is a full watch dashboard, not a complication.
- [x] Functions independently without iPhone? No.

---

## S18 — AR HUD Configuration

**Phase:** Phase 3  
**Purpose:** Configure the HUD layout for ENGO 2 / ActiveLook AR glasses.

### Constraints
- Monochrome display (~300×256px)
- 1Hz update rate
- Icon-based alert encoding (no color dependency)

---

## S19 — Route Management

**Phase:** Phase 2  
**Purpose:** Browsable list of saved routes with list and map views.

### Layout
> *Refer to `assets/design/Design.sketch` — S19.*

### Key Components
- Toolbar toggle: list view / map view (`list.bullet` / `map` SF Symbol)
- List view: route rows with name, distance, terrain description
- Map view: all routes as polylines on a `Map` view; user location centered; `MapUserLocationButton`, `MapCompass`, `MapScaleView` controls
- Tap a route → navigates to S20
- Empty state: `ContentUnavailableView` with "No Routes" label and import action
- Route import action

### Open UX Questions
- [x] How does the user import a route here (vs. at ride start)? There will be a route import action. Routes can be imported from Files, from Strava, other from other connected services that have routes.
- [x] Should routes from tribos.studio be shown in a separate section or merged with local routes? Merged
- [ ] In the future, Phase 4, there will be a route suggestion tool.

---

## S20 — Route Detail

**Phase:** Phase 2  
**Purpose:** Full detail view of a route with map, elevation, weather, Strava segments, and previous rides.

### Layout
> *Refer to `assets/design/Design.sketch` — S20.*

### Key Components
- Full-width `Map` with route polyline (green, 5pt stroke); start marker (green flag) and finish marker (blue checkered flag)
- Distance and elevation gain/loss summary (`LabeledContent`)
- Elevation profile: Swift Charts `AreaMark` + `LineMark` in `brPrimary`, catmullRom interpolation
- Current weather section: temperature, wind direction (`WindDirectionView` — rotated arrow SF Symbol + compass label + degrees), wind speed
- Strava segments: name, distance, best time, best time date
- Previous rides: date, elapsed time, conditions
- "Use This Route" CTA — sets active route in Start Sheet and navigates to S05.1

### Open UX Questions
- [x] Should weather be fetched live or cached at route-save time? The weather should be fetched live since the user is trying to plan a route.
- [x] If the route has never been ridden, should Previous Rides be hidden or show an empty state? Hidden.

---

*Cyclometer UX Specification v0.6 · 2026-03-31 · Updated 2026-05-21*
