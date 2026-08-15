# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**CyclometerAI** is a premium iOS cycling app (SwiftUI/Swift) designed as a modern bicycle computer. Implementation is **underway**: a buildable Xcode project and TCA app source live under `Cyclometer/`, alongside the design specs, assets, and documentation. Work is milestone-driven (see GitHub issues/milestones); the codebase is the source of truth for what is actually built — treat the "Planned Architecture" below as the design intent, which the current tree may not yet fully match.

## Repository Contents

```
CyclometerAI/
├── CLAUDE.md                        ← This file
├── README.md                        ← Full product specification
├── LICENSE
├── .gitignore
├── Cyclometer/                      ← Xcode project + app source (implementation)
│   ├── Cyclometer.xcodeproj
│   ├── Cyclometer/                  ← App target (App, Features, Clients, Models, UI, PreviewContent)
│   ├── CyclometerTests/             ← Unit + snapshot tests
│   └── CyclometerUITests/
└── assets/
    ├── PRD.md                       ← Product Requirements Document (v0.2)
    ├── UX.md                        ← Screen-level UX specification
    ├── TCA.md                       ← TCA architecture spec (feature tree, file layout, test strategy)
    └── design/                      ← All manual design assets
        ├── colors.md                ← Canonical color token reference (light + dark)
        ├── Design.sketch            ← Primary UI/UX design file (all screens)
        ├── CyclometerIcon.sketch    ← App icon designs
        └── d-din/                   ← D-DIN font family (SIL Open Font License)
            ├── D-DIN.otf
            ├── D-DIN-Bold.otf
            ├── D-DIN-Italic.otf
            ├── D-DINCondensed.otf
            ├── D-DINCondensed-Bold.otf
            ├── D-DINExp.otf
            ├── D-DINExp-Bold.otf
            ├── D-DINExp-Italic.otf
            └── SIL Open Font License.txt
```

## Design Assets

All manual design assets live under `assets/design/`. When implementing UI, always check these sources before making visual decisions:

| Asset | Path | Purpose |
|---|---|---|
| Color tokens | `assets/design/colors.md` | **Canonical source** for all 30 semantic color tokens, light + dark mode hex values, and WCAG AA contrast notes |
| Primary design file | `assets/design/Design.sketch` | Screen layouts, component specs, interaction flows for all screens in the screen inventory |
| App icon | `assets/design/CyclometerIcon.sketch` | App icon artwork, all required sizes |
| D-DIN fonts | `assets/design/d-din/` | Dashboard numeric typeface; must be bundled in the Xcode target. OTF files are licensed under SIL Open Font License. |

> **Color token rule:** Always reference `assets/design/colors.md` for hex values and semantic token names before hardcoding any color in Swift. The Swift token file is `Cyclometer/Cyclometer/UI/DesignSystem/Color+Cyclometer.swift`, backed by asset-catalog color sets in `Cyclometer/Cyclometer/Assets.xcassets/colors/`. **In code the tokens are `cy`-prefixed** (e.g. `Color.cyPrimary`, `cyHRZone3`, `cyRatingBad`); the `br`-prefixed names used in the UX/design specs map 1:1 to these `cy` tokens (`brPrimary` → `cyPrimary`).

## Planned Architecture (from PRD.md)

**Platform:** iOS 26+, iPhone only. No iPad, no Mac Catalyst.

**Architecture Pattern:** The Composable Architecture (TCA) — explicit state, side-effect isolation via `Effect`, hardware abstraction via `@DependencyClient`, and `TestStore` for all safety-critical logic.

**Core Apple Frameworks:**
- `CoreLocation` — GPS and location
- `CoreBluetooth` — BLE sensor connectivity (Garmin Varia RTL515/RCT715, HR strap, CSC sensor)
- `HealthKit` — Resting HR, max HR, date of birth (read-only)
- `MapKit` — Live map, route overlay
- `WeatherKit` - Current weather, wind overlaw
- `AVFoundation` — Audio tone alerts (L3 danger override)
- `CoreHaptics` / `UIFeedbackGenerator` — Haptic escalation (L1–L3)

**Persistence:** SwiftData (iOS 26+) for ride summaries and history. CoreData via `NSBatchInsertRequest` for high-frequency per-second `TrackPoint` time-series during active rides. GPX export via `gpxtpx:TrackPointExtension` v2 schema.

**BLE Targets (Phase 1):**
- Garmin Varia RTL515 / RCT715 radar (Cycling Radar GATT profile)
- Generic BLE HR Profile (`0x180D`)
- Generic BLE Cycling Speed and Cadence (CSC) Profile (`0x1816`)

> **Not targeted:** Garmin Varia RVR820 (proprietary secured BLE protocol). ANT+ (no iOS hardware support).

**TCA Feature Tree:**
```
AppFeature
├── OnboardingFeature
├── HomeFeature
├── ActiveRideFeature              ← Primary; safety-critical
│   ├── RadarFeature
│   ├── HeartRateFeature
│   ├── SpeedCadenceFeature
│   ├── NavigationFeature
│   ├── TrackPointRecorderFeature
│   └── AlertOrchestratorFeature
├── RideHistoryFeature
├── RideDetailFeature
└── SettingsFeature
```

**Project Folder Structure (actual — `Cyclometer/Cyclometer/`):**
```
Cyclometer/Cyclometer/
├── App/                           ← AppFeature, AppView, CyclometerApp; StartRideToolbar
├── Features/                      ← <Name>Feature.swift + <Name>View.swift pairs
│   ├── ActiveRide/                ← ActiveRide, Speed, Cadence, Map widgets, RideDashboard
│   ├── Rides/                     ← RidesFeature/View, StartSheetFeature/View (S05.1)
│   ├── Routes/  └── Settings/
├── Clients/                       ← TCA @Dependency clients (BLE/, Audio, Location, HealthKit, Persistence)
├── Models/                        ← Ride, RadarTarget, HeartRateZone, CadenceZone, UnitSystem, Item
├── UI/
│   ├── DesignSystem/              ← Color+Cyclometer (cy tokens), Typography, AppFonts, Spacing, Opacity
│   └── Components/                ← HeroNumber, HRZoneBadge, WidgetLabel, MetricTile, RadarColumn
├── PreviewContent/                ← Demo/stub data for SwiftUI previews
├── Assets.xcassets/  └── Resources/Fonts/
```
> Note: `assets/TCA.md` §8 describes a more nested target layout (e.g. `Features/Tab/RidesTab/`) that the repo does **not** follow — match the flat `Features/<Area>/` grouping above when adding files.

## Design System

**Brand color:** `#60BD10` (green, outdoor-visibility optimized)  
**Canonical token reference:** `assets/design/colors.md`

**Typography ramp:**
| Role | Font | Size | Notes |
|------|------|------|-------|
| Hero | D-DIN Condensed | 138pt | Letter spacing: −6.47 |
| Major | D-DIN | 56pt | |
| Values | D-DIN | 34pt | |
| Minor | D-DIN | 14pt | |
| Units | GillSans-Light | 17pt | Baseline-aligned with value |
| Caption | GillSans-Light | 14pt | |

D-DIN font files are in `assets/design/d-din/` and must be added to the Xcode project target's "Copy Bundle Resources" build phase.

Labels: **ALL CAPS** · Units: *lowercase* · Units: baseline-aligned to their corresponding value

## Build & Development

The Xcode project exists at `Cyclometer/Cyclometer.xcodeproj` (scheme: `Cyclometer`, target iOS 26.0+, iPhone only). Dependencies are resolved via SPM (The Composable Architecture, swift-snapshot-testing, etc.).

Build and test from `Cyclometer/`:
```
xcodebuild build -project Cyclometer.xcodeproj -scheme Cyclometer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test  -project Cyclometer.xcodeproj -scheme Cyclometer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CyclometerTests
```

**Testing conventions** (target `CyclometerTests`):
- Reducer logic — Swift Testing (`@Suite`/`@Test`/`#expect`) + TCA `TestStore` with `withDependencies` for mocks (e.g. `SpeedFeatureTests.swift`).
- UI — `pointfreeco/swift-snapshot-testing` via XCTest, fixed-size canvases, light + dark variants (e.g. `SpeedWidgetSnapshotTests.swift`).
- Snapshot references are recorded against a local simulator, so the four snapshot suites are skipped in CI (see `.github/workflows/tests.yml`). The full local suite passes.
- Don't snapshot against ambient environment values (`.accentColor`, `.primary` where the token matters) — pass an explicit `cy*` token, or the reference silently encodes whatever the host bundle resolved at record time.

**Open Questions (resolve before or during M2):**
- OQ2: Garmin mobile SDK vs. raw CoreBluetooth for Varia BLE integration
- OQ7: Minimum Varia RTL515/RCT715 firmware version for BLE characteristic support
- OQ11: Whether RTL515/RCT715 exposes radar return signal amplitude for vehicle size inference
- OQ12: MVP navigation — `MKDirections` routing or GPX import only

## Business Model

$10 one-time purchase, 30-day free trial, via native Apple In-App Purchases (StoreKit 2).

## General Claude Rules

- **Think before coding**. State Claude's assumptions out loud. If the request is ambiguous, ask. If a simpler approach exists, push back. Stop when Claude is confused, name what is unclear, do not just pick on interpretation and run.
- **Simplicity first.** Write the minimum code that solves the problem. No speculative abstractions. No flexibility nobody asked for. The test: would a senior engineer call this overcomplicated.
- **Surgical changes.** Touch only what the task requires. Do not improve neighboring code. Do not refactor what is not broken. Every changed line should trace back to the request.
- **Goal-driven execution.** Turn vague instructions into verifiable targets before writing a line. “Add validation” becomes “write tests for invalid inputs, then make them pass.”
- **Files added automatically.** PBXFileSystemSynchronizedRootGroup is in the project, so any .swift files are automatically added.
- **Advisor Rules**. Claude is an advisor, not an assistant. Never open with agreement. Challenge my thinking first or ask the question I'm avoiding. When I'm wrong, say it directly.
- **Confidence**. Rate your confidence: [Certain], [Likely], or [Guessing]. Never pretend to know.
- **Kill the filler**. Never say 'Great question' or 'You're absolutely right.' Lead with the most useful thing first.
