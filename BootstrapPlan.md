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

- [ ] Create Xcode project + add scaffold files
- [ ] Add TCA package dependency
- [ ] Create xcassets Color Sets for all 30 `cy*` tokens
- [ ] Build `RideMetricsView` secondary metrics grid against mockup
- [ ] Implement `VariaRadarClient` live value (CoreBluetooth)
- [ ] Implement `HealthKitClient` live value
- [ ] Implement `AudioClient` live value (Audio.md spec)
- [ ] Implement `RadarColumnView` threat animation and range-mapped glyph positioning
- [ ] Wire up `TestStore` tests — all 5 RideMetrics + 6 HRZone cases should pass
- [ ] TestFlight open beta configuration
- [ ] Apply for Garmin Radar Data BLE Program
