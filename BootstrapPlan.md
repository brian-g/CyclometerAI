# Cyclometer — Xcode Bootstrap Plan

> **Status:** Bootstrap complete — ready for Xcode project creation  
> **Updated:** May 2026

---

## Project Identity

| Key | Value |
|-----|-------|
| App name | Cyclometer |
| Project folder | `CyclometerAI/` (organizational only — never in UI) |
| Bundle ID | `name.glaeske.cyclometer` |
| Platform | iOS 26+ (iPhone only) |
| Min device | iPhone 11 (A13 Bionic) |
| Architecture | TCA — The Composable Architecture |
| Dependency mgr | Swift Package Manager only |
| Testing | XCTest + Swift Testing framework (`@Test`, `@Suite`) |
| Theme | Dark-primary; `#60BD10` Cyclometer green |

---

## Folder Structure

```
CyclometerAI/
├── scaffold.sh                    ← Run this first
├── spm-packages.md
│
├── Cyclometer/                    ← Main app target
│   ├── App/
│   │   ├── CyclometerApp.swift    @main entry point
│   │   ├── AppFeature.swift       Root TCA reducer (3-page state)
│   │   └── AppView.swift          TabView paged navigation (radar column lives in RideMetricsView)
│   │
│   ├── Features/
│   │   ├── RideMetrics/           Page 1 — speed, HR, cadence, distance, time
│   │   ├── MapNavigation/         Page 2 — live map, GPX route, turn cues
│   │   ├── RadarDetail/           Page 3 — full-screen Varia visualisation
│   │   ├── Settings/              (stub — add feature file)
│   │   └── Onboarding/            (stub — add feature file)
│   │
│   ├── Clients/                   TCA dependency interfaces + live/test impls
│   │   ├── BLE/
│   │   │   ├── BLEClient.swift
│   │   │   └── VariaRadarClient.swift
│   │   ├── Location/
│   │   │   └── LocationClient.swift
│   │   ├── HealthKit/
│   │   │   └── HealthKitClient.swift
│   │   ├── Persistence/
│   │   │   ├── SwiftDataStack.swift   → ride summaries, metadata
│   │   │   └── CoreDataStack.swift    → high-freq time-series (NSBatchInsertRequest)
│   │   ├── Audio/
│   │   │   └── AudioClient.swift      → three-tone alert synthesis (Audio.md)
│   │   └── Haptics/
│   │       └── HapticsClient.swift    → CoreHaptics eyes-free alerts
│   │
│   ├── Models/
│   │   ├── RadarTarget.swift
│   │   ├── HeartRateZone.swift        Karvonen formula — computed at query time
│   │   └── Ride.swift
│   │
│   ├── UI/
│   │   ├── Components/
│   │   │   ├── RadarColumn/           24pt right column — Ride Metrics page only (S06)
│   │   │   ├── MetricTile/            Secondary metric grid tile
│   │   │   └── HRZoneBadge/           "Z4" zone pill with zone colour
│   │   └── DesignSystem/
│   │       ├── Color+Cyclometer.swift  30 cy* tokens (light + dark)
│   │       └── Typography.swift        D-DIN + SF Pro Display, cyHeroSpeed = 82pt
│   │
│   └── Resources/
│       ├── Assets.xcassets/
│       │   ├── AppIcon.appiconset/
│       │   └── AccentColor.colorset/   → #60BD10
│       ├── Fonts/                      D-DIN family (copy from assets/design/)
│       └── Sounds/                     Three-tone audio assets (Audio.md)
│
├── CyclometerTests/               XCTest + Swift Testing
│   ├── Features/
│   │   └── RideMetricsTests.swift     5 @Test cases covering state transitions
│   ├── Clients/
│   │   └── VariaRadarClientTests.swift
│   └── Models/
│       ├── HeartRateZoneTests.swift    6 Karvonen boundary cases
│       └── RadarTargetTests.swift
│
├── CyclometerUITests/             XCUITest
│   └── CyclometerUITests.swift
│
└── assets/                        Existing spec (read-only reference)
    ├── PRD.md (v0.3)
    ├── UX.md
    ├── Audio.md
    └── design/
        ├── Design.sketch
        ├── CyclometerIcon.sketch
        ├── colors.md
        └── [D-DIN font files]
```

---

## Architecture: TCA at a Glance

```
AppFeature (root)
├── State:  selectedPage, radarTargets, isRadarPaired
│           + child states for each page
│
├── Scopes: RideMetricsFeature
│           MapNavigationFeature
│           RadarDetailFeature
│
└── Clients (DependencyKey):
        BLEClient           CoreBluetooth scanning
        VariaRadarClient    Varia RTL515/RCT715 BLE data stream
        LocationClient      CoreLocation GPS speed + position
        HealthKitClient     maxHR, restingHR, live BPM
        HapticsClient       L0/L2/L3 CoreHaptics patterns
        AudioClient         L0/L2/L3 tone synthesis (AVFoundation)
        SwiftDataStack      Ride summaries (SwiftData)
        CoreDataStack       Time-series samples (CoreData batch insert)
```

**Why TCA?** Cyclometer has multiple concurrent real-time data streams (BLE radar, HR, GPS, cadence, speed) that must compose predictably. TCA's `Effect`/`AsyncStream` model, dependency injection, and `TestStore` make this tractable and testable.

---

## SPM Dependencies

### Required at project creation
| Package | URL | Rule |
|---------|-----|------|
| TCA | `https://github.com/pointfreeco/swift-composable-architecture` | Up to Next Major: 1.0.0 |

### Add when feature work begins
| Package | URL | When |
|---------|-----|------|
| swift-snapshot-testing | `https://github.com/pointfreeco/swift-snapshot-testing` | Before first UI component test |
| swift-custom-dump | `https://github.com/pointfreeco/swift-custom-dump` | With TCA test work |

### System frameworks (no SPM entry)
CoreBluetooth · CoreLocation · HealthKit · CoreHaptics · AVFoundation · SwiftData · CoreData · MapKit

---

## Required Info.plist Keys

```xml
<!-- Bluetooth -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Cyclometer uses Bluetooth to connect to your Garmin Varia radar and heart rate sensors.</string>

<!-- Location -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>Cyclometer uses your location to track your route and calculate GPS speed.</string>

<!-- HealthKit -->
<key>NSHealthShareUsageDescription</key>
<string>Cyclometer reads your heart rate data to display accurate training zones.</string>

<!-- D-DIN font -->
<key>UIAppFonts</key>
<array>
    <string>D-DIN.otf</string>
    <string>D-DIN-Bold.otf</string>
    <string>D-DIN-Italic.otf</string>
</array>
```

---

## Xcode Project Setup Steps

1. **Run scaffold:**  `chmod +x scaffold.sh && ./scaffold.sh`

2. **Create Xcode project:**
   - New Project → iOS → App
   - Product Name: `Cyclometer`
   - Bundle Identifier: `name.glaeske.cyclometer`
   - Interface: SwiftUI · Language: Swift
   - Deployment target: iOS 26
   - Storage: None (managed by stack files)
   - Save to: `CyclometerAI/` (merge into scaffold)

3. **Add scaffold files to Xcode:**
   - Add Files to project (not copy) — or drag groups from Finder
   - Replicate the folder structure as Xcode groups (not folder references)

4. **Add TCA:**
   - File → Add Package Dependencies
   - `https://github.com/pointfreeco/swift-composable-architecture`
   - Up to Next Major: 1.0.0

5. **Add test targets:**
   - Target → CyclometerTests (Unit Testing Bundle, Swift Testing enabled)
   - Target → CyclometerUITests (UI Testing Bundle)

6. **Add D-DIN fonts:**
   - Copy font files from `assets/design/` → `Cyclometer/Resources/Fonts/`
   - Add to target membership
   - Add `UIAppFonts` to `Info.plist`

7. **Rename color tokens:**
   - The existing `BikeRider-ColorSystem.md` uses `br` prefix
   - All scaffold files use `cy` prefix (Cyclometer)
   - Create matching xcassets Color Sets for each `cy*` token

8. **Capabilities (Xcode → Target → Signing & Capabilities):**
   - HealthKit
   - Background Modes → Location updates, Audio

---

## Key Architectural Decisions (from spec)

| Decision | Resolved |
|----------|---------|
| Paged navigation vs scrolling | ✅ Paged (TabView + .page style) — split-attention, vibration/sweat tolerance |
| Radar column placement | ✅ Fixed 24pt right column inside `RideMetricsView` only; part of `HStack` layout — takes real space from widget grid; collapses to zero width (no reflow) when unpaired; per S06 design spec |
| Radar hidden when unpaired | ✅ isRadarPaired gate on AppFeature.State |
| HR zone computation | ✅ Karvonen formula, computed at query time, never persisted |
| Speed sensor priority | ✅ BLE sensor → GPS fallback |
| L3 audio + Silent Mode | ✅ AVAudioSession override — requires explicit user opt-in |
| Persistence architecture | ✅ SwiftData (summaries) + CoreData NSBatchInsertRequest (time-series) |
| Watch / Power meter | ✅ Deferred Phase 2 / Phase 3 |
| iPad | ✅ Excluded — iPhone only |

---

## Open Questions (carry forward from PRD v0.3)

- Does Garmin's mobile SDK simplify Varia BLE vs raw CoreBluetooth?
- Do RTL515/RCT715 expose signal amplitude for vehicle size inference?
- ActiveLook / ENGO 2 SPM availability — check vendor before Phase 2

---

## What's Next

- [x] Create Xcode project + add scaffold files
- [x] Add TCA package dependency
- [x] Create xcassets Color Sets for all 30 `cy*` tokens
- [x] Build `RideDashboardView` widget grid against S05.4 spec — see elaboration below
- [x] Refine the Speed widget to not overflow bounds
- [ ] Implement `
- [ ] Implement `VariaRadarClient` live value (CoreBluetooth)
- [ ] Implement `HealthKitClient` live value
- [ ] Implement `AudioClient` live value (Audio.md spec)
- [ ] Implement `RadarColumnView` threat animation and range-mapped glyph positioning
- [ ] Wire up `TestStore` tests — all 5 RideMetrics + 6 HRZone cases should pass
- [ ] TestFlight open beta configuration
- [ ] Apply for Garmin Radar Data BLE Program

---

## Widget Grid Spec — S05.4 Factory Default (Milestone M3)

> **Source:** `assets/design/Design.sketch` → S05.4 Widget Layout (layer tree measured directly).  
> **Milestone:** M3 — Active Ride Dashboard (speed, cadence, time, distance; no radar, no HR yet).  
> **Implementation file:** `Features/ActiveRide/RideDashboardView.swift`

---

### Grid Geometry

The widget grid (the `Blocking` group in Sketch) occupies the full screen width below the Dynamic Island / status bar and above the page indicator dots.

| Dimension | Value | Source |
|-----------|-------|--------|
| Grid width | 402pt | Full device width (iPhone frame) |
| Grid height | 676pt | `Blocking` group height in S05.4 |
| Grid top offset | 84pt | Below Dynamic Island + status bar |
| Grid bottom offset | 117pt | Above page indicator strip (`dashboard-pager` at y=753) |
| 1×1 cell width | 201pt | Half of grid width |
| 1×1 cell height | 95pt | Measured from Stack 4/5/6 layer heights |
| 2×2 cell width | 402pt | Full grid width |
| 2×2 cell height | 195pt | Measured from Speed 2×2 and Map 2×2 layer heights |

**Row layout — top to bottom:**

| Row | Height | Widget (left) | Widget (right) |
|-----|--------|---------------|----------------|
| 1–2 | 195pt | **W1 Speed** (full width — spans both columns) | — |
| 3 | 95pt | W4 Heart Rate | W12 HR Zones |
| 4 | 95pt | W7 Radar | W11 Pace |
| 5 | 95pt | W5 Cadence | W10 Weather |
| 6–7 | 195pt | **W8 Map** (full width — spans both columns) | — |

Total: 195 + 95 + 95 + 95 + 195 = 675pt + 1pt divider = 676pt ✓

**SwiftUI implementation:** Use `Grid` with `GridRow` and `gridCellColumns(2)` for the 2×2 widgets. No `spacing` on the `Grid`.

---

### W1 — Speed (2×2) · 402×195pt

> **Sketch frame:** `W1 - Speed (2x2)` · layer name in S05.4: `Speed 2x2`

The Speed widget is the hero element of the dashboard. It occupies the full width of the grid and the top two row units.

**Internal layout (from Sketch layer tree):**

```
Speed 2x2 (402×195)
├── Speed group (403×134 @1,7)
│   ├── average-chart bitmap (406×104 @-3,85)  ← background sparkline chart
│   └── Numbers group (394×131 @9,0)
│       ├── speed symbol — large-hero (180×120 @0,0)  ← hero speed number
│       └── stats group (77×131 @309,0)              ← right column avg/max
│           ├── Average — small-hero (77×72)
│           └── max — small-hero (77×59)
├── Distance group (123×70 @22,121)   ← bottom-left secondary metric
│   ├── Medium hero symbol (81×37)
│   └── "Distance" label (66×16)
└── Duration group (123×70 @166,121)  ← bottom-center secondary metric
    ├── Medium hero symbol (97×37)
    └── "Duration" label (68×16)
```

**Hero number sizes (from Symbols page measurements):**

| Symbol name | Width | Height | Usage |
|-------------|-------|--------|-------|
| `large-hero` | 180pt | 120pt | Current speed (the primary value) |
| `medium-hero` | 112pt | 54pt | Distance, Duration (bottom row) |
| `small-hero` | 86pt | 56pt | Avg speed, Max speed (right column) |
| `small-hero-h` | 73pt | 37pt | Horizontal variant |

**SwiftUI implementation recipe:**

```swift
// W1 Speed widget internal layout
HStack(alignment: .top, spacing: 0) {

    // Left: hero speed + distance/time bottom row
    VStack(alignment: .leading, spacing: 0) {

        // Hero speed — D-DIN Condensed, large-hero size (180×120pt frame)
        HeroNumber(speedString, unit: "mph")   // .heroNumberSize(.large)
            .frame(width: 180, height: 120)

        Spacer()

        // Bottom row: distance + elapsed time
        HStack(spacing: 0) {
            HeroNumber(distanceString, unit: "mi") { Text("DISTANCE").cyCaption() }
                .heroNumberSize(.medium)          // 112×54pt
                .frame(width: 123, height: 70)
            HeroNumber(elapsedString, unit: "") { Text("DURATION").cyCaption() }
                .heroNumberSize(.medium)
                .frame(width: 123, height: 70)
        }
    }

    Spacer()

    // Right column: avg + max speed stacked
    // Background: average-chart sparkline (future — placeholder `Rectangle` in M3)
    VStack(alignment: .trailing, spacing: 12) {
        HeroNumber(avgSpeedString, unit: "") { Text("AVG").cyCaption() }
            .heroNumberSize(.small)           // 77×72pt
            .layout(.vertical)
        HeroNumber(maxSpeedString, unit: "") { Text("MAX").cyCaption() }
            .heroNumberSize(.small)           // 77×59pt
            .layout(.vertical)
    }
    .frame(width: 77)
}
.padding(8)
.frame(width: 402, height: 195)
.background(Color.cyBgSecondary)
// Background sparkline chart rendered behind Numbers group via ZStack in final impl
```

**M3 scope:** Render the layout with live speed, distance, and elapsed time. Avg/max values are computed from ride state. The `average-chart` background sparkline is a `Rectangle(.cyBgTertiary)` placeholder in M3 — real chart implementation deferred to M9 (Ride Summary milestone).

---

### W4 — Heart Rate · 201×95pt (left, row 3)

**Sketch layer name in S05.4:** `HR` (inside Stack 4)

**Layout:**
- Label: `HEART RATE` — `cyCaption` font, uppercase, tracking 1.5, `cyTextSecondary`
- Value: current BPM — `HeroNumber`, `.heroNumberSize(.medium)` (112×54pt), `cyTextPrimary`
- Left border: 3pt solid bar in `Color.hrZone(store.hrZone)` — zone color treatment
- Background tint: `Color.hrZone(store.hrZone).opacity(0.12)`

**M3 scope:** Render static `--` value (no HR source in M3). Left border renders in `cyBorderSubtle`. Live HR + zone color wired in M5.

---

### W12 — HR Zones · 201×95pt (right, row 3)

**Sketch layer name in S05.4:** `HR Zones` (inside Stack 4)

**Layout:**
- Label: `ZONE` — `cyCaption`, uppercase
- Value: `Z4` or `Z–` when no source — `HeroNumber`, `.heroNumberSize(.medium)`
- Value color: `Color.hrZone(store.hrZone)`
- Background tint: `Color.hrZone(store.hrZone).opacity(0.12)`

**M3 scope:** Renders `Z–` in `cyTextTertiary`. Zone color wired in M5.

---

### W7 — Radar · 201×95pt (left, row 4)

**Sketch layer name in S05.4:** `Radar` (inside Stack 5)

**Layout:**
```
HStack(spacing: 0) {
    // Left: label + state text
    VStack(alignment: .leading) {
        Text("RADAR").cyCaption()
        // Paired + targets: nothing (column shows vehicles)
        // Paired + clear:   Text("Clear").foregroundStyle(.cyRatingGood)
        // Not paired:       Text("–").dDINCondensed(size: 68)
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)

    // Right: 24pt radar column (S06) — only when radar is paired
    if isRadarPaired {
        RadarColumnView(targets: targets)
            .frame(width: 24)
    }
}
.frame(width: 201, height: 95)
.background(Color.cyBgSecondary)
```

**M3 scope:** Renders `–` (not paired state). `RadarColumnView` wired in M4.

---

### W11 — Pace · 201×95pt (right, row 4)

**Layout:**
- Label: `PACE` — `cyCaption`, uppercase
- Value: min/mile string e.g. `4:52` — `HeroNumber`, `.heroNumberSize(.medium)`
- Unit: `/mi` — `cyCaption`
- Computed: `pace = 3600 / (speedMPH * 5280 / 5280)` → `60 / speedMPH` minutes/mile

**M3 scope:** Live — computed from speed state. Shows `--:--` when speed is 0.

---

### W5 — Cadence · 201×95pt (left, row 5)

**Sketch layer name in S05.4:** `Cadence` (inside Stack 6)

**Layout:**
- Label: `CADENCE` — `cyCaption`, uppercase
- Value: RPM integer — `HeroNumber`, `.heroNumberSize(.medium)`
- Unit: `rpm`

**M3 scope:** Renders `--` (no cadence sensor in M3). Live value wired in M6.

---

### W10 — Weather · 201×95pt (right, row 5)

**Sketch layer name in S05.4:** `Weather` (inside Stack 6)

**M3 scope:** Static placeholder — temperature string `72°` in `cyTextTertiary`. Real WeatherKit integration is post-MVP.

---

### W8 — Map · 402×195pt (full width, rows 6–7)

**Sketch layer name in S05.4:** `Map 2x2`

**M3 scope:** `Rectangle().fill(Color.cyBgTertiary)` placeholder with a centered `Image(systemName: "map")` in `cyTextTertiary`. Live MapKit implementation in M8.

---

### Implementation Checklist — M3 Widget Grid

- [ ] `Grid` with `gridCellColumns(2)` for W1 and W8
- [ ] `HeroNumber` renders correctly at all three sizes (large/medium/small) in D-DIN Condensed
- [ ] W1 hero speed updates live from `ActiveRideFeature.State.speedKPH`
- [ ] W1 distance updates live from `ActiveRideFeature.State.distanceKM`
- [ ] W1 elapsed time updates live from `ActiveRideFeature.State.elapsedSeconds` (timer fires every second)
- [ ] W1 avg speed computed from ride start; max speed tracked as high-water mark in TCA state
- [ ] W11 pace correctly shows `--:--` at speed = 0; correct min/mile at speed > 0
- [ ] W4 and W12 render `--` / `Z–` placeholders in `cyTextTertiary` (HR not yet wired)
- [ ] W7 renders `–` (not paired state); `RadarColumnView` absent
- [ ] W5 renders `--` (no cadence sensor yet)
- [ ] W10 renders static temperature placeholder
- [ ] W8 renders map placeholder `Rectangle`
- [ ] All cells meet 44×44pt minimum tap target for future widget-press interaction (Phase 2)
- [ ] Grid renders correctly on iPhone 15 Pro (393pt) and iPhone 16 Pro Max (430pt) — no clipping
- [ ] Light mode only
- [ ] No scroll — entire grid fits on screen without overflow (confirmed: 676pt < safe area height on all supported devices)
