# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**CyclometerAI** is a premium iOS cycling app (SwiftUI/Swift) designed as a modern bicycle computer. The repository is currently in the **design/specification phase** — no Swift source code exists yet. The primary content is design specs, assets, and documentation.

## Repository Contents

```
CyclometerAI/
├── CLAUDE.md                        ← This file
├── README.md                        ← Full product specification
├── LICENSE
├── .gitignore
└── assets/
    ├── PRD.md                       ← Product Requirements Document (v0.2)
    ├── UX.md                        ← Screen-level UX specification
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

> **Color token rule:** Always reference `assets/design/colors.md` for hex values and semantic token names before hardcoding any color in Swift. The Swift token file (`DesignSystem/Color+Cyclometer.swift`) will be generated from this source. All `br`-prefixed tokens (e.g., `brPrimary`, `brHRZone3`, `brRatingBad`) map to Xcode asset catalog entries.

## Planned Architecture (from PRD.md)

**Platform:** iOS 17+, iPhone only. No iPad, no Mac Catalyst.

**Architecture Pattern:** The Composable Architecture (TCA) — explicit state, side-effect isolation via `Effect`, hardware abstraction via `@DependencyClient`, and `TestStore` for all safety-critical logic.

**Core Apple Frameworks:**
- `CoreLocation` — GPS and location
- `CoreBluetooth` — BLE sensor connectivity (Garmin Varia RTL515/RCT715, HR strap, CSC sensor)
- `HealthKit` — Resting HR, max HR, date of birth (read-only)
- `MapKit` — Live map, route overlay
- `AVFoundation` — Audio tone alerts (L3 danger override)
- `CoreHaptics` / `UIFeedbackGenerator` — Haptic escalation (L1–L3)

**Persistence:** SwiftData (iOS 17+) for ride summaries and history. CoreData via `NSBatchInsertRequest` for high-frequency per-second `TrackPoint` time-series during active rides. GPX export via `gpxtpx:TrackPointExtension` v2 schema.

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

**Project Folder Structure (target):**
```
Cyclometer/
├── App/
├── Features/
├── Clients/                       ← Protocol-based hardware clients (BluetoothClient, etc.)
├── Models/                        ← SwiftData models (Ride, TrackPoint, RadarEvent, UserProfile)
├── Export/                        ← GPXExporter.swift
├── DesignSystem/
│   ├── Color+Cyclometer.swift     ← br-prefixed Color extensions; source of truth: assets/design/colors.md
│   ├── Typography.swift
│   └── Components/
└── Tests/
```

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

No Xcode project exists yet. When creating the iOS project:
- Target: iOS 17.0+
- iPhone only (`UIRequiredDeviceCapabilities` — no iPad)
- Bundle ID: TBD
- The `.gitignore` is already configured for Xcode/iOS development

**Open Questions (resolve before or during M2):**
- OQ2: Garmin mobile SDK vs. raw CoreBluetooth for Varia BLE integration
- OQ7: Minimum Varia RTL515/RCT715 firmware version for BLE characteristic support
- OQ11: Whether RTL515/RCT715 exposes radar return signal amplitude for vehicle size inference
- OQ12: MVP navigation — `MKDirections` routing or GPX import only

## Business Model

$10 one-time purchase, 30-day free trial, via native Apple In-App Purchases (StoreKit 2).
