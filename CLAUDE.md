# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**CyclometerAI** is a premium iOS cycling app (SwiftUI/Swift) designed as a modern bicycle computer. The repository is currently in the **design/specification phase** — no Swift source code exists yet. The primary content is design specs, assets, and documentation.

## Repository Contents

- `README.md` — Full product specification: features, architecture, widget system, settings pages, BLE sensor integrations, and service integrations
- `BikeRider-ColorSystem.md` — Complete color system for light/dark modes, WCAG AA+ contrast ratios optimized for outdoor sunlight readability
- `assets/Design.sketch` — Main UI/UX design file
- `assets/CyclometerIcon.sketch` — App icon designs
- `assets/d-din/` — D-DIN font family (SIL Open Font License), used for dashboard numerics

## Planned Architecture (from README.md)

**Platform:** iOS (SwiftUI), with a Watch app extension and Lock Screen Live Activities

**Core Apple Frameworks:**
- `CoreLocation` — GPS and location
- `CoreBluetooth` — BLE sensor connectivity
- `HealthKit` — Health metrics (weight, HR zones, calories)
- `MapKit` — Route mapping
- `GraphKit` — Charting

**BLE Sensor Types:** Heart rate, cadence, speed, power meters, bike radars (Garmin Vario, Wahoo TRAKR), pressure monitors

**Dashboard Widget System:** Customizable grid with 1×1, 2×1, 3×1 widget sizes. Widgets include Speed, Cadence, Power, Elevation, Grade, Pace, Distance, Map, Heart Rate, HRV, Calories, and more.

**App Sections (bottom nav):**
1. **Dashboard** — Primary riding interface
2. **Rides** — Historical ride data
3. **Settings** — Devices, services, wheel sizing, auto-pause, display

**Service Integrations:** Strava, Apple Health/Fitness, MapMyRide, Trailforks, GPX import/export

## Design System

**Brand color:** `#60BD10` (green, outdoor-visibility optimized)

**Typography ramp:**
| Role | Font | Size |
|------|------|------|
| Hero | D-Din Condensed | 138pt |
| Major | D-Din | 56pt |
| Values | D-Din | 34pt |
| Minor | D-Din | 14pt |
| Units | GillSans-Light | 17pt |
| Caption | GillSans-Light | 14pt |

Refer to `BikeRider-ColorSystem.md` for all semantic color tokens and contrast ratios before specifying any UI colors.

## Build & Development

No Xcode project exists yet. When creating the iOS project:
- Target: iOS 17+ (to support Lock Screen Live Activities and latest SwiftUI)
- Bundle ID convention: TBD
- The `.gitignore` is already configured for Xcode/iOS development

## Business Model

$10 one-time purchase, 30-day free trial, via native Apple In-App Purchases.
