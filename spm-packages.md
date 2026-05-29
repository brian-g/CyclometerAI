# Cyclometer — SPM Package Dependencies

Add via **Xcode → File → Add Package Dependencies…**

---

## Required at project creation

| Package | Repository URL | Version rule |
|---------|---------------|-------------|
| The Composable Architecture | `https://github.com/pointfreeco/swift-composable-architecture` | Up to Next Major: **1.0.0** |

---

## Add when feature work begins

| Package | Repository URL | When |
|---------|---------------|------|
| swift-snapshot-testing | `https://github.com/pointfreeco/swift-snapshot-testing` | Before first UI component test |
| swift-custom-dump | `https://github.com/pointfreeco/swift-custom-dump` | With TCA test work (better diffs) |

---

## System frameworks — no SPM entry needed

| Framework | Used for |
|-----------|---------|
| CoreBluetooth | Varia RTL515 / RCT715 BLE radar data |
| CoreLocation | GPS speed + route tracking |
| HealthKit | maxHR / restingHR for Karvonen zones; live HR stream |
| CoreHaptics | Eyes-free haptic alerts (L0 / L2 / L3) |
| AVFoundation | Three-tone audio alert synthesis (Audio.md spec) |
| SwiftData | Ride summaries, user profile, settings |
| CoreData | High-frequency time-series ride data (NSBatchInsertRequest) |
| MapKit | Page 2 map rendering with GPX polyline overlay |

---

## Possible future additions (Phase 2+)

| Package | Notes |
|---------|-------|
| ActiveLook SDK | AR glasses integration (ENGO 2); not yet on SPM — check vendor |
| Garmin Radar Data BLE SDK | Evaluate vs raw CoreBluetooth; apply to program first |
