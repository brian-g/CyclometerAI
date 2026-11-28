# Cyclometer — Product Requirements Document
**Version:** 0.5.0 Draft  
**Date:** 2026-09-11  
**Status:** Fourth Review  
**Author:** Brian (UX Design) + Claude (Specification)  
**Platform:** iOS 27+ · iPhone-first · Apple Watch companion  
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
| 0.5.0 | 2026-09-11 | Brian | Moved the Route picker from Phase 2 to MVP. The work on Routes is done and the Route picker seems to be an easy win. |
| 0.5.1 | 2026-09-17 | Brian / Claude | M8 spec reconciliation (#202). The Routes tab, S19 and S20 move from Phase 2 to MVP everywhere — §6, the §7 screen inventory, §12's feature tree and tab table, and §13 — following UX.md v0.8; the "Coming in a future update" placeholder is gone, because the tab is built. §6's MVP bullet no longer offers tribos.studio as a route source, which §8.6's 2026-08-14 revision had already moved to Phase 2 with Accounts. `.fit` import removed from §8.6's Files row and recorded in §15 as out of scope — it appeared in no other spec and nothing parses it. §12's `NavigationClient` and `NavigationFeature` comments drop tribos.studio; `RouteFeature` becomes the built `RoutesFeature` |
| 0.6.0 | 2026-09-17 | Brian | Review and update before the M9 milestone. |
| 0.6.1 | 2026-09-22 | Brian / Claude | Route analysis (#252). §8.6 adds a derived terrain analysis (categorized climbs, max grade, FIETS, route character) and an OpenStreetMap surface lookup at import; §12 Privacy records Overpass as the app's first network call, sending a planned route's line and nothing else. `.fit` import stays out of scope (§15), and #252's estimated-power projection is deferred with power (Phase 3). |
| 0.6.2 | 2026-09-22 | Brian / Claude | HKWorkout write (#250). §9.4 adds `distanceCycling` (write) for the workout's distance and `HKWorkoutType` (read) for skipping a ride another source already recorded. Energy is not written yet (#274). |
| 0.6.3 | 2026-09-25 | Brian / Claude | Ride place name (#283). §12 Privacy records the reverse geocode of a free ride's start coordinate, sent to Apple for S10's default ride name, with an S12 toggle to turn it off. |
| 0.6.4 | 2026-09-26 | Brian / Claude | Ride Live Activity. New §8.10: Lock Screen and Dynamic Island Live Activity moves from Phase 2 to MVP under M10.5; visual only, with radar sound left to the audio client; CarPlay, Mac and Watch presentations excluded; next-turn cue included when a route is active. §6, §13 and Resolved Decisions updated. Resolved Decisions now gives the iOS 27 minimum's reason: HealthKit's cycling-specific HR, cadence and power zone tracking. |
| 0.6.5 | 2026-09-25 | Brian / Claude | Workout active energy (#276, supersedes #274). §9.4 adds `bodyMass` (read) and `activeEnergyBurned` (write): `biologicalSex` (read) too. The ride's energy comes from heart rate (Keytel 2005) when a strap covered half the ride and Health has weight, date of birth and a Male or Female sex; otherwise from the track (physics, with dropouts and implausible grades costed flat; Compendium MET only for a ride with no usable track). None is written when Health has no weight. Bike weight is a 10 kg constant, not a setting. |
| 0.6.6 | 2026-09-26 | Brian / Claude | Health's preferred HR zones (#238, supersedes #167). §8.5 and §9.4: zone boundaries resolve `S12 override ?? Health's preferred zones ?? Karvonen`, read with iOS 27's `preferredWorkoutZoneConfiguration` (no extra permission). A resting or max override sets Health's zones aside. When the rider has an S12 override, the ride's `HKWorkout` carries the app's zones. Otherwise it keeps Health's preferred ones. OQ9's Karvonen becomes the fallback. Live `HKLiveWorkoutZoneUpdate` needs an iPhone workout session and is split to its own issue. |
| 0.6.7 | 2026-09-26 | Brian / Claude | iPhone workout session declined (#318). §9.4 adds a decision note. No `HKWorkoutSession` / `HKLiveWorkoutBuilder` runs during a ride, so there is no live `HKLiveWorkoutZoneUpdate`, and a paired Watch still prompts to start its own workout. The post-ride `HKWorkoutBuilder` write (#250, #277), its overlap skip and SwiftData crash recovery (#175, #188) stay. The dashboard's zone and any W12 time in zone stay local to the strap's readings. #318 moves to Phase 2 with the S17 Watch companion. |
| 0.6.7 | 2026-10-10 | Brian | Removed scope from the Live Activity. |
| 0.6.8 | 2026-10-12 | Brian / Claude | Live Activity Lock Screen (#309). §8.10 Presentations follows the S22 Sketch frame: speed is the large number, time and distance small. The card is `brBgPrimary` at 85%, not Sketch's 67% black, so its text passes WCAG AA over any wallpaper. Reduced luminance keeps the card, dark, rather than dropping it. |
| 0.6.9 | 2026-10-13 | Brian / Claude | Live Activity Dynamic Island (#310). §8.10 Presentations follows the "S22 - Dynamic Island" and "S22 - Expanded Dynamic Island" Sketch frames over the issue: compact leading is the status mark, not elapsed time, and compact speed is white with no unit. The no-route glyph is the app's `cyclometer.rider` across the Live Activity. Expanded puts distance's unit beside it while the row fits, and under it when a metric or long ride doesn't. The design-frames line now names the frames Sketch holds. |
| 0.6.10 | 2026-10-13 | Brian / Claude | Live Activity S12 setting (#313). §8.10: Show Live Activity sits in S12's General section and takes effect mid-ride: off ends the showing activity, on starts one. With the system setting off, the toggle is disabled, keeping the rider's choice, and the toggle's own row explains and links to iOS Settings. |
| 0.6.11 | 2026-10-20 | Brian / Claude | Live Activity ended outside the app (#412). §8.10 gets an "Ended outside the app" row: the system's 8-hour end is requested again on the next foreground, a swipe-away stops the activity for the ride, and "Don't Allow" stops it until Live Activities are switched back on. On the iOS 27 simulator, both of those go straight from `active` to `dismissed`. `LiveActivityClient` gains `ended`. |
| 0.6.12 | 2026-10-26 | Brian / Claude | On-device route narrative (#203). §8.6 adds a short paragraph that Apple's on-device model (`FoundationModels`) writes from the route's computed terrain, shown in S20's Summary. It contains no figures or units. It's written after import and stored on the route, and it's skipped where Apple Intelligence is unavailable. §12 Privacy records that it never leaves the device. |
| 0.6.13 | 2026-11-03 | Brian / Claude | App Intents (draft). New §8.11: ride controls (pause, resume, toggle, end) from Siri, the Action Button and Control Center; Start Ride opens the Start Sheet; spoken current-ride stats, last ride and period totals; GPX export of a ride to Shortcuts; GPX import from Shortcuts; rides and routes as Spotlight-indexed entities. The Live Activity stays display only (§8.10). Proposed milestone M10.8 in §13; OQ17 and OQ18 added; §12 Privacy records the on-device Spotlight index. |
| 0.6.14 | 2026-11-09 | Brian / Claude | WeatherKit client (#148). §12 Privacy records WeatherKit: a coordinate sent to Apple for current conditions or the hourly forecast, nothing else. The client has no caller yet. M10.6's surfaces (#149–#152, #204) each choose which coordinate they send. |
| 0.6.15 | 2026-11-09 | Brian / Claude | Start sheet weather (#149). §12 Privacy: S05.1 sends the rider's current location to WeatherKit when the sheet opens, only with location already granted. The in-app privacy policy lists it as a second exception after Place Names. |
| 0.6.16 | 2026-11-11 | Brian / Claude | Live ride weather (#150). §12 Privacy: during a ride the app sends the rider's current location to WeatherKit when a location fix arrives and the forecast is 10 minutes old, for W10. The in-app privacy policy now says "on the New Ride sheet and during a ride". |
| 0.6.17 | 2026-11-11 | Brian / Claude | Ride weather on S15 (#151). §12 Privacy: the current conditions of each forecast fetched during a ride are stored with the ride on the device for S15's Weather section. No new coordinate is sent: S15 asks WeatherKit only for its attribution, and only for a ride with weather to credit. |
| 0.6.18 | 2026-11-13 | Brian / Claude | Start sheet weather follows the route (#559). §12 Privacy: with a route chosen, S05.1 sends the route's start to WeatherKit rather than the rider's location, and reads no location for it; a free ride still sends the rider's current location. The in-app privacy policy names a chosen route's start alongside the current location. |
| 0.6.19 | 2026-11-14 | Brian / Claude | Rain along the route (#152). With a route loaded, each forecast W10 fetches during a ride also checks the stretch the rider reaches within two hours: a 50% or higher chance of precipitation at any point, in the hour the rider gets there, shows a silent four-second banner. It shows again on every check while it stays wet. It never goes through the radar alert path. It checks only while the dashboard is on screen and the rider is on the route. §12 Privacy: those checks send up to seven points ahead on the route, at least a kilometre past the rider, about every 10 minutes. W10's wind map (#561) is recorded there too. The in-app privacy policy names points along a route. |
| 0.6.20 | 2026-11-19 | Brian / Claude | Spec reconciliation (#588). §10's `Ride`, `TrackPoint`, `RadarEvent`, `RadarVehicle` and `VehiclePassEvent` blocks, which predated `DataModel.md`, are replaced by pointers to it. §11's client list, feature tree, folder structure and test list, which named features, folders and tests that don't exist, are replaced by pointers to `TCA.md` §3 and §8. Appendix B's GPX example and §8.7's file naming use the exporter's `creator`, `cyc:` namespace URI and `AcmeRide_` filename prefix. No requirement changes. |
| 0.6.21 | 2026-11-19 | Brian / Claude | Onboarding permissions and privacy policy (#596, #597, #598). Bluetooth and Motion and Fitness are optional at S01; Location is the only gate. The Motion purpose string names the barometer (elevation), its only use. S12's Privacy Policy opens https://acmeapps.xyz/ride/privacy/; the bundled copy is removed, so §12's mentions of the privacy policy now mean that page. |
| 0.6.25 | 2026-11-22 | Brian / Claude | S20 mirrors S15 (#570). §7's S20 row: the weather has been built since M10.6 (#204), and the screen is laid out as S15, with a map header and map sheet. Only Strava segments remain Phase 2. UX.md §S20. |
| 0.6.24 | 2026-11-22 | Brian / Claude | HKWorkout no longer automatic. The workout is written when S10 closes with Sync To's Apple Health row on, like any service, so a ride also sent to Strava doesn't duplicate in Fitness or on Strava (Strava's app imports Health workouts). §9.4 and §12 Privacy follow; UX.md §S10. |
| 0.6.23 | 2026-11-21 | Brian / Claude | Strava (Phase 2). New §8.12: connecting through a stateless token service that holds the client secret, Keychain tokens, uploads chosen per ride in S10's Sync To section, segment efforts on S15, and segments on S20 from a Strava route itself or, for any route, from its previous rides synced to Strava (Explore Segments is closed to Standard-tier apps since 2026-09-01), Strava route import on S19 and S05.2, and gear with Multi-bike later. §6 and §8.6 point to it. |
| 0.6.22 | 2026-11-19 | Brian / Claude | Orphan workouts (#584). §9.4's #318 decision note: an orphan closed out at relaunch that the rider had already ended keeps its real end time and gets its `HKWorkout` (UX.md §S10). One with no ride-end marker still gets none, since its end is the relaunch. |
| 0.6.26 | 2026-11-23 | Brian / Claude | Strava token service (#625). §12 Privacy records what the service sees: the code and tokens in transit to Strava, stored and logged nowhere. §8.12 corrects what the webhook does: the stateless service only acknowledges a deauthorization, and the app learns of it from a refused refresh. The service runs as Cloudflare Pages Functions in the acmeapps.xyz repo. |
| 0.6.27 | 2026-11-24 | Brian / Claude | Strava client (#627). §8.12 Limits and terms: a 429 waits until midnight UTC when a daily limit is spent, not just for the next quarter hour, since retrying every 15 minutes all day would only add refused requests that still count. §8.12 segments: Strava's activity and route answers carry no best time, even for a subscriber (checked against Strava), so S15's best time is #633's decision and S20's is the rider's fastest effort among the route's rides. |
| 0.6.28 | 2026-11-25 | Brian / Claude | Strava API terms (Agreement and Policy, effective 2026-06-01). Strava data may only be cached, for at most seven days, so Strava routes are browsed, not imported. §8.12 gains Strava data on the device: refetched when shown after a day, deleted seven days after its fetch, and deleted at once on disconnect or a refused refresh; never indexed, sent to a third party or given to a model. S19 lists Strava routes apart from the library; S05.2 lists both. A rider keeps a Strava route by exporting its GPX from Strava. S15's efforts follow the same cache. OQ-S2 (no) and OQ-S3 (yes) resolved; OQ-S4 (WeatherKit), OQ-S5 (combining data) and OQ-S6 (a Strava route's name on a ride) added. §8.6's service rows, §8.11 (no Strava routes in Spotlight) and §12 Privacy (Overpass, WeatherKit, Spotlight) follow. |
| 0.6.29 | 2026-11-25 | Brian / Claude | §8.12 Routes states requirements only: Strava routes on S19 and S05.2, distinguishable from the rider's own, chosen at ride start like any route. How the screens present them is UX.md's, not this document's (Design.sketch draws them in tabs by source, #637). This replaces 0.6.28's S19 section and single S05.2 list. S15's segment fields and its branding line become requirements too, and the layout goes to UX.md (§S15, new §S15.1). S20's Strava segments are dropped from Phase 2 (#637, #635 closed): §6, §7's S20 row, §13, and §8.12's priorities, S20 section, route fetch (`export_gpx` only), OQ-S5 and acceptance follow. The athlete's name and photo are fetched when S12.1 appears, never stored. A refused refresh no longer names S12.1's presentation. |
| 0.6.30 | 2026-11-25 | Brian / Claude | Live segments during a ride: Strava's partner devices and apps have them (Strava Live Segments, licensed, for subscribers); Cyclometer doesn't and can't, since building them from Strava's segment data would replicate Strava functionality (API Agreement; Policy §5.2). Recorded in §8.12 and §15. "Segment detection" leaves Phase 3 (§6, §13): with no Strava segments to detect, nothing is left of it. |

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
| **BikeIQ** | ✅ First-class | ❌ | ❌ | ❌ | ✅ | ✅ |

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
- ~~Watch haptic alert system (3 escalation levels) with Silent Mode override for Danger~~
- GPS track recording with live map view
- Route loading from GPX file import (Files app). Route service integrations are Phase 2 (§8.6)
- Routes tab (S19, S20): route list with list and map views, map-as-filter, and route detail with elevation profile
- Route picker in the Start Sheet (S05.2)
- GPX export with `gpxtpx:TrackPointExtension` (HR, cadence, speed per track point) and `cyc:VehiclePassEvent` waypoints
- GPX files available in iOS Files app
- Basic ride summary (post-ride)
- BLE device pairing and management screen
- Wheel circumference with preset sizes, manual entry, and GPS auto-calibration
- Settings screen
- Ride Live Activity on the Lock Screen and Dynamic Island, with next-turn cue (§8.10, M10.5)
- Open TestFlight beta

### Phase 2
- Route service integrations (tribos.studio, Strava, Ride with GPS) — ship with the Settings → Accounts section that authenticates them (§8.6). Strava comes first (§8.12)
- Ride history (S14) with map replay and vehicle pass event visualization
- Ride detail view (S15): HR graph, cadence graph, radar event + vehicle pass timeline
- Heart rate zone training graphs
- Customizable metric tiles on dashboard (S07, S08)
- **Multi-bike management:** a rider owns several bikes; each bike owns its speed/cadence/radar sensors and maps to a Strava gear id for export. Wheel circumference lives on the speed sensor (§8.9.1). Heart rate stays rider-scoped. Includes the bike picker in the Start Sheet (S05.1) and ride history that names the bike ridden. Data model in DataModel.md §3.9
- Apple Watch standalone companion app and complication (S17)
- Cadence + HR data visualization on ride detail screen
- Strava upload, segments, routes and gear (§8.12); Garmin Connect export

### Phase 3
- Power meter BLE support (ANT+ bridge via Garmin SDK if viable; BLE power meters natively)
- ENGO 2 / ActiveLook AR glasses integration (S18)

### Resolved Decisions (cumulative)
- **Persistence:** SwiftData (iOS 27+ minimum target; raised from iOS 26 on 2026-09-15 for HealthKit's cycling-specific HR, cadence and power zone tracking)
- **Platform:** iPhone only; no iPad support
- **Audio alerts:** Three tones — All Clear, Warning, Danger. Full spec in `Audio.md`.
- **Silent Mode:** ~~Danger tone overrides with user opt-in; Warning and All Clear always respect Silent Mode~~ Every tone rings through Silent Mode and with the screen locked (2026-11-03, `Audio.md §AVAudioSession Configuration`)
- **App name:** Cyclometer
- **Apple Watch:** Deferred to Phase 2
- **HR zone formula:** Karvonen only in MVP
- **TestFlight:** Open beta
- **Navigation (OQ12):** GPX file import only for MVP; no `MKDirections` routing
- **Wheel sizing (OQ13):** Preset common sizes + manual entry + GPS auto-calibration (see §8.9). One app-wide value for MVP; Phase 2 moves it onto the speed sensor, which is bound to one wheel (see §8.9.1 and DataModel.md §3.9)
- **Radar visualization (OQ14):** Option F — right-side sidebar strip (see §8.2)
- **Live Activity (§8.10):** MVP in M10.5; visual only (sound stays with the audio client); phone only (no CarPlay, Mac or Watch); includes the next-turn cue

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
| S05.2 | Route Picker | MVP | From the Start Sheet, the ability to pick a route for the ride |
| S05.3 | Active Ride Accessory | MVP | Compact strip above TabBar when the dashboard is minimized; shows live ride stats, and a tap anywhere on it reopens the dashboard |
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
| S14 | Ride History List | MVP | Scrollable list of past rides with summary stats |
| S15 | Ride Detail | MVP | Full ride: map replay, HR graph, cadence graph, radar event + vehicle pass timeline |
| S16 | Training Zones Graph | Cut | Time-in-zone breakdown across recent rides |
| S17 | Apple Watch | Phase 2 | Glanceable watch app. |
| S18 | AR HUD Configuration | Phase 3 | Configure ENGO 2 / ActiveLook display layout |
| S19 | Route Management | MVP | Browsable list of saved routes with list and map views |
| S20 | Route Detail | MVP | Route detail laid out as S15 (#570): map header and full-screen map sheet, elevation profile, distance, current weather at the route's start, previous ride history |

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
| L3 — Danger | Any vehicle ≥ 30 km/h closing speed | Core Haptics pattern: three 0.14s `HapticContinuous` bursts at full intensity and sharpness — pattern defined in `UX.md §S06` | Danger tone — ~~overrides Silent Mode if user opt-in~~ rings through Silent Mode, like every tone |
| L0 — Clear | Threat resolves after L2 or L3 | None | All Clear tone (see `Audio.md`) |

#### Alert Rules
- Minimum 3 seconds between same-level re-triggers to prevent alert fatigue
- L3 alert persists until threat recedes; it is not dismissible by the rider
- Every tone uses `AVAudioSession` category `.playback` with `.mixWithOthers`, so it plays with the screen locked and rings through Silent Mode (2026-11-03). `.ambient` would obey the switch but is silenced by the lock, and iOS can't read the switch to choose. ~~Danger tone: uses `.playback` with route override to force audio through speaker. User must opt in to Silent Mode override in Settings (S12) before this behavior activates. Default is silent-mode-respectful.~~
- ~~Warning and All Clear tones always respect Silent Mode (never override)~~
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
- [ ] Every tone plays with the screen locked and the phone on silent
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
- A brief non-intrusive banner displays on source switch during an active ride: "Switched to GPS for speed — <sensor> not responding" when readings stop, or "Switched to GPS for speed — <sensor> disconnected" when the sensor disconnects. A flapping sensor is announced at most once per 5 minutes; a disconnect always is (BLE.md §6.2, #390)
- The rider is never left staring at a stale value; all metrics display "—" when no source is active

**Ride max speed (#540):** the ride's max is the highest displayed speed while recording and moving, from whichever source is displayed. Because it only ever rises, a reading has to be plausible to become it (`MaxSpeedGate`). The displayed speed itself is never gated.
- **GPS:** a valid `speedAccuracy` wider than **2.5 m/s** (`maxGPSSpeedAccuracyMPS`) refuses the reading. That ceiling is a judgement not yet calibrated on device data: the rides on record don't store `speedAccuracy`. A reading with no valid accuracy (CoreLocation's negative "invalid") is *unknown*, not poor: it is held to the acceleration bound below like any other reading, by the owner's decision. The simulator's simulated location reports exactly that, a valid speed with `speedAccuracy` −1, so a GPS-only ride run in the simulator shows a real max.
- **Both sources:** there must be at least one reading displayed in the **5 s** before it (`window`; never the reading's own sample), and the reading must be reachable from every one of them: no more than **4 m/s²** (`maxAccelerationMPS2`) times the seconds since that reading, plus **2.5 m/s** (`readingSlackMPS`), above it. 4 m/s² (0.4 g) is about where a road bike's front wheel lifts, and what a 1,500 W sprint gives at 5 m/s. The 2.5 m/s margin covers what the time between two displays doesn't: each reading measures speed over an earlier interval (a wheel sensor's is the exact average over whole revolutions between two notifications' last-event times; GPS's is CoreLocation's filtered estimate), delivery can bunch two readings closer than the intervals they measured, GPS is off by up to its accuracy, and at a fallback GPS differs from the wheel by its noise plus the wheel's calibration. A wheel sensor gets only this check, since CSC has no accuracy field.
- The gate keeps no state: each reading is judged against the readings before it, so a refused reading can't hold the max down past 5 s, and a resumed ride needs nothing restored.
- **Costs and residual.** The first reading after any 5 s with no displayed reading (the ride's first, the first after a resume from a relaunch, a dropout or a sensor reconnect) is shown and judged against by the next, but never becomes the max itself. A stale-sensor fallback's promoted GPS fix never counts: the fallback fires once 5 s have passed since the last wheel reading, so that reading is already out of the window. The fallback records no reading, so the first GPS reading after it waits too, and the max resumes on the second, about 2 s after the fallback. A disconnect fallback is different: its promoted fix is judged against a wheel reading from at most a few seconds earlier, and counts. What the gate can't catch is a spike that is the first two readings after such a gap, since its second is judged only against its first. Requiring more readings would only lengthen the spike it misses, by one second per reading, and cost one more uncounted reading after every gap.
- Replayed (before the gate's final wiring, against the rule it now implements: each reading judged against the readings before it) over the 8 rides of 2026-10-07 to 2026-11-03 (about 30,000 per-second readings, mostly wheel sensor), the gate refused 7 readings that would have raised the max, all first readings after a gap, and every ride's max was unchanged. The largest real rise in one second was 3.9 m/s, under the 6.5 m/s the gate allows. GPS `speedAccuracy` is not recorded in the ride store or the GPX export, so its ceiling has not been replayed.

**Cadence Notes:**
- Cadence has no fallback source; if no BLE cadence sensor is paired, the cadence tile displays "--" with a "Pair Sensor" affordance (tapping navigates to S11)
- Cadence is recorded as absent (element omitted) in GPX export when no sensor is present for that track point

**Acceptance Criteria:**
- [ ] HR switches from BLE strap to Apple Watch within 5 seconds of strap disconnection
- [ ] Speed switches from BLE sensor to GPS within 5 seconds of sensor disconnection
- [ ] A single 1 s speed spike well beyond the rider's speed, or a GPS reading with a valid `speedAccuracy` wider than 2.5 m/s, doesn't become the ride's max; a GPS reading with an invalid accuracy is treated as unknown and bounded by acceleration; a real sprint or descent still does (#540)
- [ ] Source badge updates correctly on all transitions
- [ ] Banner notification appears on source switch during active ride
- [ ] GPX export correctly records the active source for each track point (see `DataModel.md` §4.3 and Appendix B)

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
- **Zone boundaries come from Apple Health first (#238).** iOS 27's `HKHealthStore.preferredWorkoutZoneConfiguration(for: .heartRate)` returns the rider's zones: ones they set in Health, or Apple's own from their health data. Each boundary resolves `S12 override ?? Health ?? Karvonen`. A resting or max HR override means the rider disagrees with Health, so Karvonen from their values applies instead. Health's zones are used only in a shape the table can hold: five zones, rising, above resting. Otherwise Karvonen applies whole. They are not capped at the app's max, which is an estimate; zone 5's top rises to meet them instead
- App-stored values are always considered overrides; Apple Health is the source of truth unless the user has manually overridden. **This is literal since #96**: `RiderProfile` (DataModel.md §3.5) stores *only* overrides, as six optionals (resting, max and the four zone boundaries), and resolves `override ?? healthKit ?? default` at read time. A rider who never disagrees with Health persists nothing at all. M10 ships the storage and the Karvonen derivation; M5 supplies the Apple Health term

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
- [x] Zones follow the rider's preferred zones in Apple Health when no S12 override is set (#238)
- [ ] Zone calculated correctly for all 5 zones given arbitrary Max HR / Resting HR inputs (unit tested)
- [ ] Zone color updates on dashboard within 2 seconds of new HR reading
- [ ] App functions normally when HealthKit permission is denied (HR zone tile shows "No HR Source")

---

### 8.6 Navigation and Live Map (MVP)

**Purpose:** Provide a live map view on the active ride dashboard showing current position and heading. Support pre-planned route following via GPX import.

**Live Map (MVP):**
- Embedded `MapKit` view within the dashboard (as a widget — see UX.md S05)
- Updates position at minimum 1Hz using `CoreLocation`
- Heading-up orientation by default. The dashboard widget always stays heading-up; the full-screen map sheet is
  user-toggleable to north-up and remembers the choice (#199)
- No base-map download required; uses standard MapKit tile cache
- During L3 radar alert, map view may be obscured by full-screen alert wash — this is acceptable given the safety priority

**Route Loading (MVP):**

Routes are pre-planned by the rider before the ride. The following sources are supported:

| Source | Method | Notes |
|---|---|---|
| iOS Files app | Import GPX file | Rider selects a `.gpx` file from any location accessible via the Files app (iCloud Drive, local storage, imported from another app). `.fit` is not read — see §15 |
| tribos.studio | Service integration — **Phase 2** | Rider connects their tribos.studio account in Settings → Accounts; routes are browsable and importable directly from the Cyclometer UI, if its API terms allow keeping them (check before design; Strava's don't, §8.12) |
| Strava | Service integration — **Phase 2** | Rider connects their Strava account in Settings → Accounts; routes are browsable from the Cyclometer UI and held only as a cache of at most seven days, never imported, as Strava's API terms require (§8.12) |
| Ride with GPS | Service integration — **Phase 2** | Rider connects their Ride with GPS account in Settings → Accounts; routes are browsable and importable directly from the Cyclometer UI, if its API terms allow keeping them (check before design; Strava's don't, §8.12) |

**Analysis at import (#252).** Every imported route is analysed on the device: gradient smoothed over 100 m, after dips narrower than 100 m are filled (a terrain model reads a creek crossing on fill as the creek bed), climbs categorized Cat 4 to HC on the length × average-grade scale, a FIETS score per climb, a one-word character (flat, rolling, hilly, mountainous, punchy), and a summary line of at most 80 characters shown on S19 and S20. Surface comes from OpenStreetMap after the route is saved (§12 Privacy); the import never waits on it.

**Route narrative (#203).** Where Apple Intelligence is available, the on-device model (`FoundationModels`) turns that analysis into a short paragraph for S20's Summary, such as where the climbs sit and how the ride finishes. The model only narrates. The route is split where its terrain changes, into each categorized climb and the stretches between them (thirds for a route with no climbs), at most five sections. Each section's position and gradient spread are computed first, and the model writes exactly one sentence per section. The paragraph contains no figures or units, which the app checks before storing it, so it can't contradict the numbers beside it or go stale when the unit system changes. It's written once, after import (earlier routes are caught up the same way), and stored on the route. A device without Apple Intelligence, or a route without elevation, gets no paragraph, and S20's Summary is unchanged. The S19 row never shows it.

> **Revised 2026-08-14.** The three service integrations move to Phase 2 along with the Accounts section that
> authenticates them (UX.md §S12). MVP loads routes from the Files app only. This is a consequence of
> deferring Accounts rather than a separate decision — a route service cannot be browsed without a connected
> account, so the two ship together or not at all.

> **Resolved (OQ12):** MVP does not use `MKDirections` (Apple Maps routing). Route creation is not an in-app feature in MVP — riders plan routes externally using tools like tribos.studio, Komoot, Strava, or OnTheGoMap.com and import the resulting GPX file.

**Turn-by-Turn Navigation (MVP):**
- Route overlaid on the live map as a polyline in `brMapRoute`, beneath the travelled track; while a route is loaded
  the map tilts into a 3D navigation view (#199)
- Turn notifications: a turn tone — left, right or U-turn (Audio.md, "Turn Left, Turn Right and U-turn"), held back during an L3 alert or a sounding Warning — plus a centred turn instruction (UX.md §S05, "Turn instructions") at configurable distance from turn
- A Turn-by-Turn toggle on S05.1, remembered from ride to ride, turns turn notifications and the off-route banner off; the route is then only drawn on the map (#197 review)
- No recalculation in MVP; if the rider goes off-route, an "Off route" banner displays with no auto-reroute

**Acceptance Criteria:**
- [ ] Map renders current position within 5 seconds of ride start (GPS lock)
- [ ] Position updates smoothly at 1Hz minimum with no jumping
- [ ] Route overlay renders correctly from imported GPX file
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
| Elevation | Barometric altimeter (`CMAltimeter`); CoreLocation altitude where there is none (#387) | `<ele>` |
| Timestamp | System clock (UTC), to the millisecond (#416) | `<time>` |
| Heart Rate | Active HR source (BPM) | `<gpxtpx:hr>` |
| Cadence | BLE cadence sensor (RPM) | `<gpxtpx:cad>` |
| Speed | Active speed source (m/s) | `<gpxtpx:speed>` |
| Power | BLE power meter (Watts, Phase 3) | `<gpxtpx:power>` |
| Horizontal accuracy | CoreLocation `horizontalAccuracy` (m) | `<cyc:horizontalAccuracyMeters>` |

**Which fixes become track points.** A fix whose `horizontalAccuracy` is worse than **10 m** — the same threshold wheel auto-calibration pauses its window on (§8.9) — produces no track point and no map polyline vertex. The track takes a gap, which a consumer straight-lines across; the app does not substitute a held or smoothed position for one it knows is untrustworthy. The live map marker still follows the freshest fix, since there is nothing better to show.

A backstop bounds this: if nothing has been recorded for **10 s**, the next valid fix is recorded whatever its accuracy. A ride under heavy tree cover records a coarse track rather than none.

> **What this does and does not remove.** On the ride of 2026-09-06 the reported position repeatedly crawled behind the speed channel for several seconds and then snapped forward — 20.1 m in one second against a reported 3.1 m/s, inside a window whose accuracy the app had already measured at 10.3 m. The gate removes those seconds. It is *not* a jump filter: over a window either side of each snap, the track's own distance and the speed integral agree to a few metres and the bearings through it are constant, so the snap is the fix catching up with ground the rider genuinely covered. Rejecting it would hold a stale position and then draw the same line three seconds later. Smoothing or map-matching the recorded track remains out of scope.

**Why not `<hdop>`.** GPX 1.1 has no element for positional accuracy in metres. `<hdop>` is *horizontal dilution of precision* — a unitless factor describing satellite geometry, not a distance — so metres written there would parse as a plausible number and mean something else entirely. Accuracy is exported in the Cyclometer-specific `cyc:` namespace instead, alongside `cyc:VehiclePassEvent`; consumers that don't know the namespace ignore it.

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
| Timestamp | `<time>` | UTC timestamp of pass, to the millisecond |
| Event type | `<type>vehiclePass</type>` | Standard GPX type element for filtering |
| Alert level | `<cyc:alertLevel>` | danger / caution / advisory — the ride-level alert at the vehicle's **peak closing speed**, not at the instant it drew level |
| Rider speed | `<cyc:riderSpeedKph>` | Rider speed at moment of pass (km/h) |
| Estimated pass speed | `<cyc:estimatedPassSpeedKph>` | The **vehicle's ground speed** (km/h) — an absolute speed, not a closing speed. Always greater than `<cyc:riderSpeedKph>`. Omitted if the vehicle was never observed approaching |

**What `estimatedPassSpeedKph` carries.** The radar reports *closing* speed — how fast the vehicle is gaining on the rider, not how fast it is travelling — so a ground speed has to be derived:

```
estimatedPassSpeedKph = riderSpeedKph (at the pass) + peak closing speed (over the vehicle's track)
```

The **peak** rather than an average over the track. Radar measures only the radial component of the closing speed, which decays by cos(θ) as a vehicle draws alongside, so a whole-track mean is dragged down by the tail near the rider — by 13–27 km/h across the four overtakes captured on 2026-09-06. The peak occurs while the vehicle is still lined up behind the rider (87–135 m out in every one of those captures), where θ is near zero and the radial component is the true speed difference.

Because both speeds are exported, a consumer recovers the raw radar closing speed as `estimatedPassSpeedKph − riderSpeedKph`, to the one-decimal precision of the file.

> **This is the vehicle's speed on approach**, not necessarily its speed at the instant it drew level: the two terms are measured up to 22 seconds apart. A vehicle that slows behind the rider before committing to the pass is described by how fast it came up, not how fast it went by.

**What `alertLevel` carries.** The ride-level alert sampled at the same instant as the peak closing speed above — the most threatening moment of the encounter, not its last.

Because radar measures only the radial component, a vehicle's closing speed is at its *minimum* as it draws level with the rider. Recording the alert level there recorded the least severe instant of every encounter, and inverted the severity ordering outright: on 2026-09-06 the pass that closed at 59 km/h was filed a band *below* the pass that closed at 47, because the first was last seen at 25 km/h and the second at 32.

The value remains **ride-level** — derived from every vehicle the radar can see, not this one alone — so a faster vehicle alongside at the peak is reflected in it. That is the level the rider was genuinely alerted at. Anchoring it to one tick rather than taking the worst level over the whole encounter is what bounds the effect: a running maximum would let any later vehicle raise a pass's severity and, because it only ever rises, hold it there for the rest of the track.

> `riderSpeedKph` deliberately stays the value **at the pass**, per the field table above. Two of the three fields are peak-anchored and one is not — that asymmetry is exactly what makes `estimatedPassSpeedKph` the vehicle's speed on approach, and it should not be reconciled away.

**Recording Rate:** Track points recorded at 1Hz. Vehicle pass events recorded discretely on occurrence.

**File Naming Convention:** `AcmeRide_YYYY-MM-DD_HH-mm.gpx`

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

### 8.10 Ride Live Activity (Lock Screen + Dynamic Island)

**Milestone:** M10.5. **Added:** v0.6.4.

A pocketed or bar-mounted phone with a locked screen hides ride state. Unlocking mid-ride to check speed, time or radar is unsafe (P1, P7). The Live Activity shows ~~live ride metrics, radar threat status and the next turn~~ the same ride state as the S05.3 mini-player (`ActiveRideAccessoryView`) on the Lock Screen and, on iPhones that have one, the Dynamic Island.

#### Scope decisions

| Decision | Detail |
|---|---|
| Visual only | The Live Activity never plays sound, fires a haptic or wakes the screen. No `AlertConfiguration` is passed on any update. Radar sound and haptics remain the audio client's job (§8.3, `Audio.md`) |
| Phone only | CarPlay, Mac and Apple Watch Smart Stack presentations are out of scope. No `.supplementalActivityFamilies` are declared; the absence of a default rendering on those surfaces is verified on device |
| Content | The S05.3 mini-player's: route progress ring (~~bicycle glyph~~ the app's rider glyph with no route, #310; pause icon while paused), elapsed time, distance and speed. No HR, radar or next-turn cue |
| ~~Next-turn cue~~ | ~~In scope whenever an M8 route is active; no turn row otherwise~~ |
| No controls | Display only. No Pause/Resume buttons or `LiveActivityIntent`s |
| Local updates only | Updates come from the running app. No APNs push tokens |

~~Live Activity rendering is scheduled by the system and carries no latency guarantee, so it is never the primary radar alert channel.~~

#### Lifecycle

| Event | Action |
|---|---|
| Ride starts | `Activity.request(...)` when `ActivityAuthorizationInfo().areActivitiesEnabled` and the S12 toggle is on |
| Metrics change | `activity.update(...)`, coalesced to at most 1 Hz |
| ~~Radar threat level increases~~ | ~~Immediate update, bypassing the throttle~~ |
| ~~Next turn changes, or its distance crosses 500 m, 100 m or 0 m~~ | ~~Immediate update, bypassing the throttle~~ |
| ~~Pause / resume~~ | ~~Update `status`; the elapsed timer freezes and resumes~~ |
| ~~Ride ends~~ | ~~`activity.end(finalContent, dismissalPolicy: .after(now + 15 min))`, showing a summary~~ |
| Pause / resume | Update `status` to show the pause icon; the elapsed timer freezes and resumes. The activity stays running |
| Ride ends | `activity.end(nil, dismissalPolicy: .immediate)`. No summary |
| App terminated | Each update sets `staleDate` about 30 s ahead, so a dead app's activity shows as stale. An unchanged activity, a paused ride's say, is sent again every 15 s so it doesn't go stale while the app is alive |
| Request refused | ActivityKit grants a request only to an app in the foreground. A ride that started or resumed in the background requests again when the app next comes forward. A card the rider swiped away isn't brought back (see the next row) |
| Ended outside the app | The activity's state shows how it ended. `.ended`, still on the Lock Screen, is the system's 8-hour limit: updates stop, and a new one is requested when the app next comes forward. `.dismissed`, off the screen, is a swipe-away or "Don't Allow" at iOS's prompt: updates stop either way. A swiped-away card isn't requested again this ride. "Don't Allow" turns the system setting off, so nothing is requested, this ride or later, until the rider turns it back on in iOS Settings; then one is requested when the app next comes forward |

System limits: an activity stays active for at most 8 hours and remains on the Lock Screen for up to 4 more; `ContentState` must stay under 4 KB.

#### Data model

```swift
struct RideActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: RideStatus            // .riding, .paused
        var startDate: Date               // drives Text(timerInterval:)
        var pausedElapsed: TimeInterval?  // frozen value while paused
        var speedMPS: Double
        var distanceMeters: Double
        var routeProgress: Double?        // 0…1; nil = no route followed → rider glyph (#310)
    }
    var units: UnitSystem
}
```

v0.6.7 dropped `heartRate`, `hrZone`, `rideName`, `RadarSnapshot` and `TurnCue`; speed is m/s like the rest of the app. `routeProgress` is `NavigationFeature.State.routeProgressFraction`.

State values are canonical (metric); unit conversion happens in the view.

#### Presentations

- **Lock Screen (primary).** ~~Elapsed timer large in D-DIN. Metric row: speed, distance.~~ One D-DIN row, per the S22 Sketch frame: elapsed time and distance small, speed large (#309). On a `brBgPrimary` card at 85% opacity (`Opacity.liveActivityCard`), the least that keeps `brTextSecondary` at WCAG AA over any wallpaper; Sketch's 67% black doesn't. Leading: the route progress ring, the ~~bicycle glyph~~ app's rider glyph (`cyclometer.rider`, #310) with no route, or the pause icon while paused. ~~HR tinted by `hrZone(_:)`. Radar strip on the trailing edge in the §8.2 sidebar language, `brRatingOkay` / `brRatingBad` by level, grey when disconnected. With a route active, a turn row above the metrics: maneuver symbol, distance, street name in `brTextSecondary`; "Off route" in `brRatingOkay` replaces it when off route. Pause/Resume button in `brPrimary`.~~
- **Dynamic Island** (iPhones with one; others show the Lock Screen presentation only). ~~Compact leading: elapsed time. Compact trailing: speed. Minimal: the progress ring, bicycle glyph or pause icon. Expanded: the Lock Screen's content.~~ Per the Sketch frames (#310): compact leading is the 26 pt status mark (ring, rider glyph or pause icon); compact trailing is speed alone, `.body` medium (Sketch's SF Pro Medium 18, as a text style) in `brTextPrimary`, with no unit (VoiceOver speaks it). Minimal is the status mark. At those sizes the ring drops its percentage. Expanded is the Lock Screen's row with distance's unit beside it (Sketch's `small-hero-h`); a metric or long ride is wider than the island that way, so the unit drops under distance rather than cut speed. Past 9 h (the timer's slot is then "44:44:44") or on a 393 pt phone even that can be too wide, so a last fallback shows speed without its decimal; this applies to the Lock Screen too (#310 review). The status mark's pause icon fills the mark, like Sketch's circle, rather than following Dynamic Type. The island is always black, so its views take the dark scheme. Expanded margins are 16 pt, against Sketch's 15 and the system's ~18. ~~Compact trailing and minimal follow a priority: radar threat, then a turn within 100 m, then speed. Expanded: speed, time, HR, radar count and distance, turn row, Pause button.~~
- **Reduced luminance.** Read `isLuminanceReduced`; ~~drop tinted backgrounds,~~ keep text white~~, keep radar colour~~. The card stays, always in its dark variant (#309): with no tint, iOS draws a light glass of its own, and `brTextSecondary` units all but vanished on it (seen on the simulator).
- **Stale.** Metrics dim to `brTextSecondary` with a "Reconnecting…" caption. In the compact island only the speed dims; there's no room for the caption.

Design frames in `Design.sketch`: ~~Lock Screen light and dark × radar none / approaching / fast, paused, ended, stale, turn far / near / arrive / off-route, threat and turn together~~ ~~no route / route, paused, stale; Dynamic Island compact, minimal and expanded~~ "S22 - LIve Activity" (Lock Screen), "S22 - Dynamic Island" (compact) and "S22 - Expanded Dynamic Island". There is no minimal, paused or stale frame; those follow the issue and the Lock Screen.

#### Interactivity

~~`PauseRideIntent` and `ResumeRideIntent` conform to `LiveActivityIntent` and run in the app process, reaching the ride store through a shared command bus. Buttons keep a 44 pt hit target.~~ None — the Live Activity is display only.

#### Architecture

- `CyclometerWidgets` widget extension (target `CyclometerWidgetsExtension`) with `ActivityConfiguration(for: RideActivityAttributes.self)`.
- ~~`RideActivityKit` Swift package shared by app and extension: attributes, snapshots, formatters, colour tokens, `HeroNumber` and the progress ring.~~ The extension compiles a set of the app's own files through target membership (#306): `RideActivityAttributes`, `UnitSystem`, `HeroNumber`, `OpenRingProgressView`, `Spacing`, `AppFonts`, the asset catalog and D-DIN. No package and no copies; a shared file that picks up an app-only type breaks the extension build. TCA.md §8 lists the set.
- `LiveActivityClient` dependency (`start`, `update`, `end`, `isEnabled`, `ended`); `liveValue` wraps ActivityKit; `testValue` is switched off, and tests supply a recording client. `start` reports whether an activity is showing. `update` takes no alert parameter. `ended` returns when the showing activity ends, as `.ended` or `.dismissed` (#412).
- `LiveActivityFeature` reducer scoped into the active ride feature. It observes ride ~~, sensor, radar~~ and `NavigationFeature` state (route progress only) and owns the 1 Hz throttle on an injected clock~~, and applies the threat and turn bypasses. Turn cues are derived by navigation; the Live Activity mirrors them~~. Built (#308) as a reducer layered onto `ActiveRideFeature`'s domain rather than a scoped child, so it reads the whole ride and ends the activity on the action that tears the ride down. The ride's 1 Hz tick, on the injected clock, is the throttle.
- `Info.plist`: `NSSupportsLiveActivities = YES`. Background updates rely on the ride's location background mode.
- S12 gains **Show Live Activity** (default on), `AppPreferences.isLiveActivityEnabled`. When the system setting is off, S12 explains and links to iOS Settings. Built (#313) in the General section. Changed mid-ride it takes effect at once: off ends the activity, on starts one (`SettingsFeature` delegates to `AppFeature`, which tells the ride). With the system setting off the toggle is disabled but keeps the rider's choice; the system setting is reread whenever the app comes forward.

#### Acceptance criteria

- [ ] Activity appears within 1 s of ride start and ends with ride end
- [ ] Elapsed time ticks without per-second updates
- [ ] No sound, haptic or screen wake from the Live Activity in any state
- [ ] No rendering on Apple Watch or CarPlay (device-verified)
- [ ] ~~Turn row appears only with an active route; radar wins Dynamic Island priority over the turn cue~~
- [ ] ~~Pause/Resume from the Lock Screen changes ride state and the dashboard~~
- [ ] Text/background pairs pass WCAG AA in light, dark and reduced luminance
- [ ] `ContentState` encodes under 4 KB at worst case
- [ ] "CyclometerAI" appears nowhere in the extension

### 8.11 App Intents (Siri, Shortcuts, Action Button, Control Center, Spotlight)

**Milestone:** M10.8 (proposed). **Added:** v0.6.13.

A rider with a bar-mounted phone and gloved hands can't reliably tap a sweaty screen, and unlocking mid-ride is unsafe (P1, P7). App Intents give the ride's controls a voice (Siri), a hardware button (Action Button) and a system control (Control Center, Lock Screen) without the rider looking at the app. The same framework exposes rides and routes to Shortcuts and Spotlight, so riders can export, query and compose without opening the app.

Riding controls come first. Queries, export and Spotlight are built on the same entities but are secondary.

#### Scope decisions

| Decision | Detail |
|---|---|
| Ride controls are the priority | Pause, resume and end ride, reachable from Siri, the Action Button and Control Center. These are the only intents usable during a ride without touching the screen |
| Live Activity stays display only | §8.10's "No controls" decision stands. No `LiveActivityIntent` buttons on the Lock Screen or Dynamic Island (OQ17) |
| Start opens the Start Sheet | Starting a ride opens the app on the S05.1 Start Sheet, with the route preselected if one was named. The rider taps Start. No ride starts without the sheet's sensor check, and the sheet stays the only writer of the Ride row (#344) (OQ18) |
| End asks first | Ending a ride asks for confirmation (`requestConfirmation`), matching the dashboard's finish alert. End is never a Control Center control: one stray tap must not end a ride |
| Dialogs, no custom snippets | Intents answer with spoken/printed `IntentDialog` text only. No custom snippet views in this milestone, so there is no new design work |
| GPX import is not an intent | Opening a `.gpx` from Files, Mail or AirDrop already works through `CFBundleDocumentTypes` and `onOpenURL`. An `ImportRouteIntent` exists only so Shortcuts can pass a file in (for example, a Mail attachment) |
| No Watch, CarPlay or Mac surfaces | Phone only, as §8.10 |
| No Siri action category | No `@AppIntent(schema:)` adoption until an Apple category fits a cycling workout; plain intents and App Shortcuts only |
| English phrases only | §12 Localization: English at launch |

#### Entities

| Entity | Display | Query |
|---|---|---|
| `RideEntity` | Title, date, distance, duration (from `RideListSummary`) | By id; suggested = 10 most recent; string search on title; `EntityPropertyQuery` on start date for Shortcuts' "Find Rides" |
| `RouteEntity` | Name, distance, elevation gain (from `RouteSummary`) | By id; suggested = all routes, most recently imported first; string search on name |

Both read through `PersistenceClient` (`fetchRides`, `fetchRoutes`, `fetchRouteSummary`). Neither copies data out of the store: an entity is a view of a row, resolved by id each time.

Both conform to `IndexedEntity` so iOS can index them in Spotlight. A deleted ride or route is removed from the index in the same step that deletes it.

Strava routes are not entities. Strava's API Policy forbids putting its data in a search index (§8.12), so `RouteEntity` covers library routes only.

#### Intents

| Intent | Parameters | Behaviour | Returns |
|---|---|---|---|
| `PauseRideIntent` | — | Same as the dashboard's Pause. No ride in progress → error dialog "No ride in progress." Already paused → "Your ride is already paused." | Dialog: "Ride paused." |
| `ResumeRideIntent` | — | Same as Resume, after a manual or auto pause. Not paused → "Your ride isn't paused." | Dialog: "Ride resumed." |
| `ToggleRidePauseIntent` | — | Pauses a moving ride, resumes a paused one. This is the intent for the Action Button and the Control Center control, since one press must do the right thing | Dialog naming the new state |
| `EndRideIntent` | — | Asks "End your ride?" first, then opens the app and runs the same finish as the dashboard (summary, GPX export, Health write), landing on S10. It runs in the foreground on purpose: the rider has stopped by then, and Health refuses writes while the phone is locked | Opens S10 |
| `StartRideIntent` | `route: RouteEntity?` | Opens the app on the Start Sheet with the route preselected. A ride already in progress → opens the dashboard instead | Opens the app |
| `GetCurrentRideStatsIntent` | — | Distance, elapsed time and average speed of the ride in progress, in the rider's units. No ride → "No ride in progress." | Dialog, e.g. "18.4 kilometres in 52 minutes, averaging 21.2 km/h." |
| `GetLastRideIntent` | — | The most recent finished ride | `RideEntity` + dialog: "Your last ride was 42.3 kilometres in 1 hour 52 minutes, on Saturday." |
| `GetRideTotalsIntent` | `period: RidePeriod` (this week / month / year) | Count, total distance and total time of finished rides in that calendar period | Dialog: "This week: 3 rides, 96 kilometres, 4 hours 10 minutes." |
| `ExportRideIntent` | `ride: RideEntity?` (default: last ride), `date: Date?` | Returns the ride's existing GPX file from `Documents/Rides`; never re-exports. With `date`, the ride on that day; more than one asks the rider to pick | `IntentFile` (`.gpx`) for Shortcuts to save, share or send |
| `ImportRouteIntent` | `file: IntentFile` | Runs the file through `GPXRouteImporter`, the same path as opening it from Files | `RouteEntity` |
| `OpenRideIntent` / `OpenRouteIntent` | the entity | Opens S15 / S20 for it. Spotlight uses these when a result is tapped | Opens the app |

Spoken numbers use `Measurement` formatting in the rider's `UnitSystem`, written out in full (no "km/h" abbreviations read letter by letter).

#### App Shortcuts (zero-setup phrases)

`CyclometerShortcuts: AppShortcutsProvider`, every phrase including `\(.applicationName)`:

- "Pause my ride in Cyclometer", "Resume my ride in Cyclometer"
- "Start a ride in Cyclometer", "Start a ride on `\(\.$route)` in Cyclometer"
- "End my ride in Cyclometer"
- "How's my ride in Cyclometer" (current stats)
- "What was my last ride in Cyclometer"
- "How far have I ridden this `\(\.$period)` in Cyclometer"
- "Export my last ride from Cyclometer"

#### Controls

In `CyclometerWidgets`, as `ControlWidget`s usable in Control Center, on the Lock Screen and on the Action Button:

- **Start Ride**: `ControlWidgetButton` running `StartRideIntent`.
- **Pause / Resume Ride**: `ControlWidgetButton` running `ToggleRidePauseIntent`. A button rather than a toggle, because a toggle's value provider runs in the extension and can't see the app's ride state. Revisit if ride state is ever shared through an App Group.

#### Architecture

- Intents live in the app target, under `Cyclometer/Intents/` (TCA.md §8), and run in the app's process.
- **Controls.** A `ControlWidget` names its intent type, so the two intents the controls run (`StartRideIntent`, `ToggleRidePauseIntent`) are also compiled into the extension through target membership, like the Live Activity set. They must still *perform* in the app's process, where the store is: `ToggleRidePauseIntent` conforms to `LiveActivityIntent` for that reason alone (it adds no Live Activity button), and `StartRideIntent` opens the app. Their files reach the command center only through a protocol in a shared file, keeping app-only types out of the extension build. Confirm the process each runs in on device before building on it.
- **One way into the store.** Ride commands reach `AppFeature` as a single action, `AppFeature.Action.intent(IntentCommand)` with `IntentCommand` = `pauseRide`, `resumeRide`, `toggleRidePause`, `endRide`, `startRide(routeID: UUID?)`, `openRide(UUID)`, `openRoute(UUID)`. The reducer maps each to the existing action (`pauseTapped`, `resumeTapped`, `finishTapped`'s confirmed path, `startRideButtonTapped`, the Rides and Routes stacks), so `TestStore` covers intent behaviour exactly as it covers taps. Intents never duplicate ride logic.
- **Bridge.** `CyclometerApp` registers a small main-actor `IntentCommandCenter` with `AppDependencyManager`. It holds the app's store, sends `.intent(...)`, and exposes a read-only snapshot of the ride (status, distance, elapsed, average speed) for `GetCurrentRideStatsIntent` and for the error dialogs. Intents depend on the command center, never on `AppFeature.Action`'s shape.
- **Query intents** read `PersistenceClient` directly; they change nothing in the store.
- **Name clash.** AppIntents and swift-dependencies both declare `@Dependency`. Intent files qualify the one they use.
- **Background launch.** A query or export intent can launch the app in the background with no scene. Whatever those intents need (the SwiftData container, `PersistenceClient`) must be available without the scene's `.task` having run. Verified in the first issue before anything is built on it.

#### Acceptance criteria

- [ ] "Pause my ride in Cyclometer" pauses a moving ride with the phone locked, and the dashboard shows paused on unlock
- [ ] The Action Button, set to Pause / Resume Ride, pauses and resumes a ride with the phone locked
- [ ] End ride asks for confirmation; declining leaves the ride running
- [ ] Start Ride opens the Start Sheet, with the named route preselected; it never starts a ride on its own
- [ ] Every ride-control intent with no ride in progress answers with a dialog and changes nothing
- [ ] Spoken stats use the rider's units and match the dashboard
- [ ] Export returns the same GPX file as Files, for the last ride and for a ride picked by date
- [ ] Rides and routes appear in Spotlight; tapping one opens S15 / S20; a deleted ride or route disappears from Spotlight
- [ ] Query and export intents work when the app was not running
- [ ] Every `IntentCommand` is covered by an `AppFeature` `TestStore` test

---

### 8.12 Strava (Phase 2)

Strava is the first connected service. It ships with the Settings → Accounts section that authenticates it
(UX.md §S12, §S12.1), and nothing in this section analyses the rider's fitness: Strava and other apps do that.

**Priorities, in build order:**

1. Connect a Strava account and keep the connection (S12 Accounts, S12.1): #625 token service, #626 sign-in, #627 client, #628 schema, #629 screens
2. Upload a ride to Strava, chosen per ride in S10's Sync To section: #630 queue, #631 Sync To, #632 S15 Sync and S14 retry
3. The ride's segment results on Ride Detail (S15): #633
4. Strava routes at ride start: browsed on S19 (#634), and chosen on S05.2 (#636), held as a cache, never imported
5. Later, with Multi-bike (§6, DataModel.md §3.9): the ride's Strava gear (#638)

Design.sketch frames for all of it: #637.

Not in scope: reading the rider's Strava activity history into Cyclometer, and live segments during a ride (below).

> **Live segments: partner apps have them; Cyclometer doesn't and can't.** Strava times segments live during a ride
> on licensed partner devices and apps (Garmin, Wahoo and others), for riders with a Strava subscription, through
> Strava Live Segments, a partner API outside the public API. Cyclometer has no such licence. Building the same
> thing on the phone from Strava's segment data would "compete with or replicate Strava functionality", which the
> API Agreement forbids (Policy §5.2: no use "competitive to Strava"). So no ride-time segment widget: a ride's
> segments appear only after Strava has processed the upload (S15). §15 records it.

**Connecting (OAuth 2).**

- Authorization code flow. When `canOpenURL` accepts `strava://`, the app opens
  `strava://oauth/mobile/authorize` and the Strava app handles sign-in; otherwise
  `https://www.strava.com/oauth/mobile/authorize` in an `ASWebAuthenticationSession`, so the rider never leaves the
  app. `LSApplicationQueriesSchemes` gains `strava`. The redirect is `cyclometer://acmeapps.xyz/strava`; the host must
  match the Authorization Callback Domain in Strava's API settings (the scheme follows the app if it is renamed)
- Scopes requested: `read`, `read_all` (private routes and the rider's segment data), `profile:read_all` (the
  athlete's bikes, for gear), `activity:read_all` (segment efforts on Only Me activities) and `activity:write`
  (uploads). Strava's consent screen lets the rider untick any of them. The callback's `scope` parameter is what was
  granted; it is stored, and a feature whose scope is missing is hidden and named on S12.1 rather than failing
- **Token service.** Exchanging the code, refreshing and revoking all need the app's `client_secret`, which must not
  ship in the binary. A stateless token service at `acmeapps.xyz/ride/api/strava/` holds it: `token` (code →
  tokens), `refresh`, `revoke`, and `webhook`, which Strava's API terms require. The webhook only acknowledges a
  deauthorization: with nothing stored it can't tell the app, which learns when Strava refuses its next refresh
  (below). The service stores no tokens and no athlete data; it forwards to Strava and returns Strava's answer.
  Built in #625 as Cloudflare Pages Functions in the acmeapps.xyz site repo, whose `docs/strava-token-service.md`
  covers deployment, the webhook subscription and secret rotation
- Tokens live in the Keychain (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), never
  in SwiftData or the AppPreferences document, so they don't travel in backups: a restored or new iPhone reconnects
- Access tokens last six hours. A request refreshes first when the token has under five minutes left, and refreshes
  once more on a 401. Each refresh can return a new refresh token that replaces the old one at once, so refreshes are
  serialized and the newest token is written before any request uses the new access token
- A refresh that Strava refuses (the rider revoked access on strava.com) leaves the account **Disconnected**, and the
  rider can connect again (UX.md §S12.1); uploads waiting on Strava stay pending. All Strava data on the device is deleted
  then, as on disconnecting
- Disconnecting (S12.1) revokes the token through the token service, deletes the Keychain item, the `ConnectedService`
  record, and all Strava data on the device (below): Strava routes and their analysis, and segment efforts. Rides keep their own data and their `RideSyncRecord`s, so S15 can still link to the activity. A route the
  rider exported from Strava and opened as a file is theirs, and stays (OQ-S3)

**Strava data on the device.** Strava's API Policy (effective 2026-06-01) allows Strava data, meaning anything read
through the API, only in a cache, for at most seven days (§6.2). That includes routes the rider drew and their GPX
export. A deletion on Strava must show in the app within 48 hours (§6.3), and revoked access means deletion within
30 days (§7.4). So nothing read from Strava is library data:

- Every Strava item carries the time it was fetched: a route and its analysis, a ride's segment efforts.
  When shown, an item more than a day old is refetched if the device is online, which keeps a deletion on Strava well
  inside 48 hours. Offline, the cached copy is shown until it expires
- An item seven days past its fetch is deleted, at launch and whenever the app becomes active, and is never shown
- Disconnecting, or a refused refresh, deletes all of it at once
- The athlete's name and profile photo are fetched each time the account screen (S12.1) appears, and never stored
- Strava data is never indexed (Spotlight, §8.11; Policy §5.5), never sent to anyone but Strava (the Overpass surface
  lookup, §12; WeatherKit, OQ-S4; Policy §5.10), and never given to a model (the route narrative, #203; Policy §5.3)
- What Cyclometer recorded itself is not Strava data. A ride's GPS track, sensor data and statistics stay, and so does
  its `RideSyncRecord`, the id of the activity the app uploaded

**Uploading.**

- The rider chooses destinations per ride in S10's **Sync To** section (UX.md §S10): one row per connected service and
  Apple Health, each defaulting to the rider's last choice for that destination. Strava uploads when S10 closes
  (Finish Ride or a swipe), so the name and description edited there go with it
- The file is the ride's GPX (§8.7), gzipped: `data_type=gpx.gz`, `sport_type=Ride`, `name` and `description` from
  S10, `external_id` the ride's UUID. Its `gpxtpx` heart rate and cadence are read by Strava; the `cyc:` extensions
  are ignored. `POST /api/v3/uploads` answers before Strava has processed the file, so the app polls
  `GET /api/v3/uploads/:id` — after 1, 2, 4 and then every 8 seconds, for two minutes — until `activity_id` arrives,
  stores it as `RideSyncRecord.remoteActivityId`, and marks the record synced
- **Duplicates.** Many riders' Strava app imports workouts from Apple Health, so the ride may already be on Strava.
  An upload Strava rejects as a duplicate of an existing activity is recorded as synced, with that activity's id.
  This is also why the Health workout is a Sync To choice rather than automatic (UX.md §S10)
- Uploads outlive S10: they run in an app-scoped queue, a ride still pending at quit resumes at the next launch, and
  a failed one is retried from S15's Synced To row, S14's Sync swipe or S12.1's Uploads section (#632). Nothing uploads without the rider's choice
- Not synced back: renaming or deleting a ride in Cyclometer after upload leaves the Strava activity as it is

**Segments on Ride Detail (S15).** For a ride synced to Strava, `GET /api/v3/activities/:id?include_all_efforts=true`
returns its segment efforts. Strava matches segments after processing, so an empty answer within ten minutes of the
upload is retried the next time S15 appears. Otherwise the efforts are cached on the ride under the rules above
(`Ride.stravaSegmentsFetchedAt`): refetched when S15 shows them more than a day after they were fetched, deleted
seven days after, and refetched at once by pull to refresh. S15 gives the rider the ride's efforts and their results:
the PR medal (`pr_rank` 1–3) and the KOM/QOM rank (top 10), free to every Strava account (a first effort on a segment
gets neither). How they're presented is UX.md's (§S15, §S15.1). The rider's best time and its date are not in this answer, even for a subscriber on a ride with
PRs (checked against Strava in #627). Whether S15 shows them, and from which call, is #633's decision.

> **No segments on Route Detail (S20).** Dropped from Phase 2 (#637; #635 closed). If they return, Explore Segments
> (`GET /api/v3/segments/explore`) is closed to Standard-tier apps since 2026-09-01, so a route's segments would come
> from a Strava route's own answer (`GET /api/v3/routes/:id`) and from the efforts of the route's rides synced to
> Strava.

**Routes.** Strava routes are browsed, not imported. The rider's Strava routes come from
`GET /api/v3/athletes/:id/routes` (rides only), on the Routes tab (S19) and at ride start (S05.2). The rider must be
able to tell them from the routes they own, because they behave differently: they follow Strava, and one deleted there
disappears here. How each screen presents them is UX.md's (§S19, §S05.2). Opening one fetches its line with
`GET /api/v3/routes/:id/export_gpx` and runs the GPX importer's parsing and analysis (§8.6) into the cache, without the surface lookup or the narrative. A Strava route
can be chosen at ride start like any other. Choosing one that isn't cached fetches it first, and a ride can start on
a cached copy offline.

- A Strava route's local id is a name-based UUID derived from its Strava id, so it is the same every time the route
  is fetched. Rides that followed it (`Ride.routeId`) relink when it's fetched again, after it expired or after a
  reconnect
- To keep a Strava route for good, the rider exports its GPX from Strava and opens it in Cyclometer like any file.
  It's then the rider's file, not data the app read from Strava. The app doesn't do this for them: fetching the GPX
  and saving it is the storage the terms forbid

**Gear (later, with Multi-bike).** `GET /api/v3/athlete` lists the rider's Strava bikes; each Cyclometer bike maps to
one (`Bike.stravaGearID`). Uploads can't name gear, so once the upload has an `activity_id` the app sets it with
`PUT /api/v3/activities/:id`.

**Limits and terms.**

- Rate limits belong to the app, shared by every rider: by default 200 requests per 15 minutes and 2,000 a day overall,
  of which non-upload requests (upload polling included) get 100 and 1,000. The client reads the `X-RateLimit-*` and
  `X-ReadRateLimit-*` headers, and on a 429 waits for the next quarter hour, or until midnight UTC when a daily count
  is spent (the 15-minute windows reset on the quarter hour, the daily ones at midnight UTC). Nothing polls Strava in
  the background
- New Strava apps are single-player; an upgrade allows 10 athletes, enough for development and a small TestFlight.
  Anything wider waits on Strava's app review (#288)
- Branding, per Strava's brand guidelines: connecting uses Strava's own "Connect with Strava" button, Strava data
  carries Strava's "Powered by Strava" attribution and links back to Strava, and Strava orange appears only in
  Strava's own marks. Where the attribution goes is UX.md's; Strava's app review (#288) confirms it
- Strava data is shown only to the rider it belongs to (Policy §2.3). How it is stored, and what it is never used for,
  is under Strava data on the device, above

**Open questions.**

- OQ-S1: Should S12.1 offer "Upload automatically", making Strava's Sync To default sticky without a choice per ride? No
- OQ-S2: Is the on-device route narrative allowed for Strava routes (read through the API, not a GPX file the rider
  exported from Strava and opened, which is theirs)? No. Policy §5.3 forbids any use of
  Strava data in an AI application, including loading it into a model's context, with no exception for on-device
  models
- OQ-S3: Must routes imported from Strava be deleted on disconnect or deauthorization? Yes, within 30 days (Policy
  §7.4). More than that, they can't be kept beyond the seven-day cache at all (§6.2), so Strava routes are browsed,
  not imported, and disconnecting deletes them at once
- OQ-S4: Is sending a Strava route's points to WeatherKit a transfer to a third party (Policy §5.10)? Until the app
  review (#288) answers, a Strava route sends none: the Start sheet (S05.1) sends the rider's location, as with no
  route; S20 shows no weather for it; and rain alerts that look ahead along the route are off on it
- OQ-S5: Does Policy §5.4's ban on combining Strava data "with other customer data" cover the rider's own Cyclometer
  data? S15 shows efforts beside the ride's own data. The section is about
  aggregate analytics, so the reading here is no; confirm in the app review (#288)
- OQ-S6: Is a Strava route's name, kept on a ride that followed it (`Ride.routeName` and the default title), Strava
  data? The reading here is no: the title is the rider's, accepted or edited in S10, and the name is part of the ride
  Cyclometer recorded. Confirm in the app review (#288); DataModel.md OQDM11

**Acceptance criteria:**

- [ ] Connecting with and without the Strava app installed; the connection survives relaunch
- [ ] A token refreshed from an expired access token; concurrent requests refresh once
- [ ] Unticked scopes hide their features and are named on S12.1
- [ ] A ride uploads from S10 and links to its Strava activity; a duplicate records the existing activity
- [ ] A ride pending at quit uploads after relaunch
- [ ] S15 shows the ride's efforts with their PR medals and KOM/QOM ranks
- [ ] Strava routes list on S19 and S05.2; one starts a ride online, or offline from its cached copy; its rides relink when it's fetched again
- [ ] Strava data more than a day old is refetched when shown, and deleted seven days after its fetch; a route deleted on Strava disappears the next time the list is shown
- [ ] Strava routes are absent from Spotlight, the Overpass lookup, WeatherKit requests and the narrative
- [ ] Disconnecting, or a refused refresh, revokes or marks the account Disconnected, clears the Keychain, and deletes all Strava data, Strava routes included
- [ ] `StravaClient` and the token flow covered by tests against a mock transport; reducers by `TestStore`

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
- Bytes 2–N: Vehicle records (see `DataModel.md` §3.3 RadarVehicle)

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
- `HKCharacteristicTypeIdentifierDateOfBirth` (read — for max HR estimation if not available, and the
  rider's age in the workout's heart-rate energy estimate)
- `HKWorkoutType` (write — the ride is written back when the rider sends it to Apple Health from S10's Sync To, UX.md §S10, and the share
  authorization is requested alongside the reads at S01 so the rider answers one sheet, not two)
- `HKQuantityTypeIdentifierDistanceCycling` (write — the workout's distance reaches it as a sample,
  which `HKWorkoutBuilder` only accepts with share access to that type)
- `HKWorkoutType` (read — only to skip writing a ride another source already recorded over the same
  time, UX.md §S10)
- `HKQuantityTypeIdentifierBodyMass` (read — the rider's weight for the workout's energy estimate; with
  none, no energy is written rather than an assumed weight)
- `HKCharacteristicTypeIdentifierBiologicalSex` (read — with date of birth, selects the workout's
  heart-rate energy equation; Not Set or Other falls back to the physics estimate)
- `HKQuantityTypeIdentifierActiveEnergyBurned` (write — the workout's estimated energy, which is what
  earns Move ring credit, UX.md §S10)

**Profile Data Read at Onboarding and Ride Start:**
- `restingHeartRate` → `HKQuantityTypeIdentifierRestingHeartRate`
- `maxHeartRate` → `HKQuantityTypeIdentifierHeartRate` (historical max, or age-based estimate: 220 − age)
- These values populate the Karvonen zone calculation and update if Apple Health values change
- Preferred heart-rate zones → `preferredWorkoutZoneConfiguration(for: .heartRate)` (iOS 27, #238). There is no zone
  object type, so nothing is added to the authorization request. Ahead of Karvonen, behind an S12 override (§8.5)

**HR Streaming During Ride:**
- Use `HKAnchoredObjectQuery` with live updates when Apple Watch is the active HR source
- Fallback: Apple Watch is secondary to BLE HR strap (see §8.4)

> **Decision note — issue #318.** Recorded 2026-09-26. The iPhone app does **not** run an
> `HKWorkoutSession` / `HKLiveWorkoutBuilder` during a ride. It is revisited with the S17 Watch
> companion (Phase 2), where #318 stays open.
>
> **What a session would buy.**
> - **Mainly, no Watch prompt.** While an iPhone workout session runs, a paired Apple Watch doesn't ask
>   the rider to start a workout that is already being tracked. Brian has seen this in use; the SDK
>   doesn't document it. Without a session, the Watch's "looks like you're cycling" prompt arrives a
>   few minutes into a ride.
> - iOS 27's live zone update, `workoutBuilder(_:didUpdateWorkoutZone:)`, which fires only on a live
>   builder.
> - Background execution, and a workout that exists while the ride is still in progress.
>
> **What it would replace.** Every part of the post-ride write (#250, UX.md §S10):
> - `RideHealthWorkout` rebuilds a plain `HKWorkoutBuilder` from the saved ride, and sync identifiers
>   make a rewrite replace the earlier copy.
> - The owed flag retries the write at Finish and at launch (#277).
> - The write is skipped when another source recorded an overlapping cycling workout.
> - Crash recovery (#175, #188) runs from SwiftData alone, and an orphan closed out at relaunch gets no
>   workout. Since #584, one the rider had already ended keeps its real end and gets its workout.
>
> A live builder's workout exists only inside its session, so `recoverActiveWorkoutSession` would
> have to agree with the SwiftData recovery and the pending-ride-end marker. That is two recovery
> systems for one ride.
>
> **Why not.**
> - **Health has nothing to add.** The live builder zones only heart rate that is in HealthKit, and
>   the strap's readings are held by the app over CoreBluetooth and never reach it. To feed the
>   builder, the app would write its own strap samples back (a new `heartRate` share permission,
>   double-counted against a Watch writing HR over the same ride). Health would then sort the same
>   readings the dashboard already classifies on arrival (§8.5), later, and against a zone
>   configuration that must be kept in step with the S12 override.
> - **The background time is already there.** The ride's `location`, `bluetooth-central` and `audio`
>   modes cover it, and §8.10's Live Activity relies on the location mode.
> - **The replaced write path works.** It is eventual and idempotent (#277), and a session would
>   trade that for a live object that has to survive the ride.
> - **Removing the prompt has a cost too.** A rider who accepts it gets the Watch's own workout, with
>   1 Hz heart rate, and the app's write is skipped as a duplicate. Without the prompt, the app's
>   workout becomes the record, and it carries no heart rate. For a Watch-only rider, the Watch also
>   drops back to background sampling every few minutes (§8.4). The prompt is a nuisance, but it
>   doesn't justify the costs above, and for Watch-only riders its absence makes their Health record
>   worse. S17 settles both, because the Watch runs the session there.
>
> **What stays.**
> - The dashboard's zone is classified locally on each reading.
> - S10's zone breakdown is derived from the saved track.
> - W12's time in zone (UX.md §W12, built in the Heart rate sheet; #145) accumulates locally from the
>   same readings, not from Health.
>
> **Open threads, neither needing a session.**
> - On iOS 27 a plain `HKWorkoutBuilder` computes zone durations (`HKWorkout.zoneGroupsByType`), but
>   only from HR samples added to the workout. That is the same HR double-write question as above.
> - Health's workout duration includes paused time, and pause/resume events could be added after the
>   ride with `addWorkoutEvents`.

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

> **Hybrid persistence:** In-memory ring buffer (`RideDataBuffer`) during active rides, flushed to CoreData via `NSBatchInsertRequest` at ride end for raw `TrackPoint` time-series. SwiftData with `@Query` for `Ride` summaries and history screens. The rider's profile and preferences are not SwiftData: each is a single JSON document (see Rider Profile, Preferences and Paired Sensors below).

---

### Ride, TrackPoint and Vehicle Events

> Specified in `DataModel.md`, which is canonical for their shape; this section only names them. The entity blocks of earlier revisions predated it.

- **`Ride`** (`DataModel.md` §3.1) — the SwiftData summary row: timing, distance, speeds, heart-rate and cadence aggregates, route link, recording state and crash-resume fields, and the GPX export's URL. Track points and vehicle events link to it by `rideId` only; it holds no `@Relationship` arrays (#172).
- **`TrackPoint`** (`DataModel.md` §4) — the 1 Hz time series, a CoreData entity (`TrackPointMO`) written by `NSBatchInsertRequest`, not a SwiftData `@Model`. `SensorSource` is §4.3.
- **`VehiclePassEvent`** (`DataModel.md` §3.4) — one discrete pass, recorded as a GPX `<wpt>` with the `cyc:VehiclePassEvent` extension (Appendix B).
- **`RadarEvent`** and **`RadarVehicle`** (`DataModel.md` §3.2, §3.3) — radar state snapshots. Specified, not built yet.

**Pass detection logic:**
```swift
// A pass is detected when a vehicle that was being tracked:
// 1. Was present in radar data for >= 2 continuous seconds
// 2. AND then disappears from radar tracking
// 3. AND closing speed was positive (approaching) for majority of tracking duration
// This guards against vehicles that turn off or slow before reaching the rider.
```

---

### Rider Profile, Preferences and Paired Sensors

> Replaces the `UserProfile` entity of earlier revisions (OQDM5, #67, #96). The shapes are specified in `DataModel.md`, which is canonical for them; this section only names them.

- **`RiderProfile`** (`DataModel.md` §3.5) — heart-rate *overrides* only: resting, max and the four zone boundaries. Each is `nil` until the rider disagrees with Health, and values resolve `override ?? healthKit ?? default` at read time (§8.5).
- **`AppPreferences`** (`DataModel.md` §3.6) — every other setting the rider makes: unit system, wheel circumference, map orientation, ride and display toggles, and the paired sensors.
- **`PairedSensor`** (`DataModel.md` §3.7) — one BLE sensor in one `SensorRole` (radar, heart rate, speed, cadence; power in Phase 3), held as an array inside `AppPreferences`. One sensor per role; a combo CSC sensor assigned both roles appears twice, once as speed and once as cadence.

`RiderProfile` and `AppPreferences` are not SwiftData `@Model`s: each is a `Codable` struct stored as one JSON document through `@Shared(.fileStorage)`.

---

## 11. Architecture

### Pattern: The Composable Architecture (TCA)

**Rationale:** Cyclometer has multiple concurrent real-time data streams (BLE radar, BLE HR, BLE speed/cadence, HealthKit, CoreLocation), safety-critical alert logic that must be fully unit-testable without hardware, and planned multi-target expansion (Apple Watch, AR glasses). TCA's explicit state management, side-effect isolation via `Effect`, dependency injection via `@Dependency`, and `TestStore` make it the strongest architectural fit.

**TCA Dependency Clients:** one `@Dependency` client per hardware or system service (BLE, HealthKit, location, altimeter, haptics, audio, persistence, weather and the rest). The list as built is the `Clients/` folder in `TCA.md` §8.

**Feature Decomposition:** the reducer tree as built is `TCA.md` §3, which is canonical for it. Heart rate, radar and location are slices of `ActiveRideFeature` state, not child features.

**Navigation Structure:**
The app uses a `TabView` with three tabs:

| Tab | Icon | Phase |
|---|---|---|
| Rides | `figure.outdoor.cycle` | MVP |
| Routes | `point.topleft.down.curvedto.point.bottomright.up` | MVP |
| Settings | `gearshape` | MVP |

All three tabs are functional in MVP. The Routes tab (S19, S20) came into MVP with UX.md v0.8 and shipped in M8.

**Project Folder Structure:** `TCA.md` §8 maps the source tree, the widget extension's shared files and the test layout (`Cyclometer/CyclometerTests/`, mirroring the top-level source folders), and is canonical for them. Follow it when adding files.

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
- HealthKit data: read-only, apart from the `HKWorkout` and its cycling-distance sample the app writes back when the rider chooses Apple Health in S10's Sync To (UX.md §S10); no data transmitted to any server
- GPS and ride data: stored locally only, apart from a free ride's start coordinate sent for its place name (below), which the rider can turn off
- Route surface lookup (#252): after a route is imported, its line — the planned route, never a recorded ride — is sent to the public OpenStreetMap Overpass API (`overpass-api.de`) to read the surface of the roads along it. Nothing else is sent, and no account or identifier is attached. A failed or offline lookup leaves the route without a surface; it is retried on the next launch, and the first failure in a batch stops the rest, so a refusing or unreachable server is not asked again and again. Surface data is credited "© OpenStreetMap contributors" wherever it is shown (ODbL). A Strava route is never sent, since Strava's API Policy forbids passing its data to a third party (§8.12)
- Ride place name (#283): when a ride that did not follow a route is summarised (S10), its start coordinate — that one point, nothing else — is sent to Apple's reverse geocoder (MapKit `MKReverseGeocodingRequest`) for the name of the town it started in, used in the ride's default name ("Fargo Morning Loop"). A ride on a route is named for the route and sends nothing. The S12 **Place Names** toggle (on by default) turns the lookup off, and the privacy policy says so. A failed or offline lookup keeps the offline name silently
- Weather (#148): current conditions and the hourly forecast come from Apple's WeatherKit, which is sent one coordinate per request and nothing else — no account or identifier. Each M10.6 surface says which coordinates it sends (the rider's location, a route's start, or points ahead on a loaded route for rain alerts). The Start sheet (S05.1, #149) sends the start of the chosen route (#559) as it opens and whenever the route changes; with no route it sends the rider's current location, only when location access is already granted. During a ride (W10, #150) it sends the rider's current location when a location fix arrives and the forecast is 10 minutes old, or a minute after a failed request, whether or not W10 is on a page. A Strava route's points are not sent (§8.12, OQ-S4). With a route loaded, each of those forecasts also checks the route ahead for rain (#152), sending up to seven points along the stretch the rider reaches within two hours, one request each: at most about 40 requests an hour. It checks only while the rider is on the route and the dashboard is on screen during a recording ride. Paused, locked, minimised or in the background, it sends nothing. W10's sheet (#561) sends up to seven points ahead along the route when it opens, and not again within 10 minutes. Nothing from either is stored. The current conditions from each of those forecasts are kept with the ride, on the device, for S15's weather summary (#151): nothing more is sent for them. It never asks for access itself, and the privacy policy says so. A failed or offline request leaves that surface's empty state, and WeatherKit data is credited with the Apple Weather mark and legal link wherever it is shown
- Route narrative (#203): written by Apple's on-device model (`FoundationModels`) from the route's computed terrain. Nothing is sent off the device
- App Intents (§8.11): ride titles, dates, distances and route names are indexed in Spotlight's on-device index. Siri and Shortcuts read them through the app's intents. Nothing is sent to a server by the app. Strava routes are not indexed (§8.12)
- Strava token service (#625, Phase 2, §8.12): connecting Strava sends the authorization code, and afterwards the refresh token (to refresh) or a token (to disconnect), to Cyclometer's token service at `acmeapps.xyz`. The service adds the app's client secret and forwards each to Strava. It sees the code, the tokens and Strava's answer (which includes the athlete's public profile) in transit, and stores and logs none of them. Strava's deauthorization webhook reaches the same service and is acknowledged without being stored. Nothing is sent until the rider connects Strava
- BLE device identifiers: not transmitted externally
- No analytics or crash reporting without explicit user consent

### Localization (MVP)
- English only at launch
- Unit system: metric / imperial toggle in AppPreferences (`DataModel.md` §3.6)
- Date/time: respects device locale
- GPX timestamps: UTC per GPX 1.1 spec

### Platform
- **iOS 27.0 minimum**
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
| M8 | Navigation: live map; GPX route import; turn alerts; off-route banner; Routes tab (S19, S20) and the S05.2 route picker (tribos.studio and the other route services move to Phase 2 with Accounts) |
| M9 | Ride summary; ride history persistence; vehicle pass event count in summary |
| M10 | Settings (S12, less Accounts); full device management (S11 flat list, extending the M6 pairing sheet); replace-or-cancel on role collision; radar and HR pairing brought under the paired-record gate; `RiderProfile` + HR zones; onboarding (S01, S02) |
| M10.5 | Fit & finish, widgets and dashboard personalization; Ride Live Activity on the Lock Screen and Dynamic Island (§8.10) |
| M10.8 (proposed) | App Intents (§8.11): ride controls from Siri, the Action Button and Control Center; Start Ride; ride queries; GPX export and import through Shortcuts; Spotlight for rides and routes |
| M11 | QA; TestFlight open beta; bug fixes |
| M12 | App Store submission |

### Phase 2 — Companion & History (Target: +2 months post-launch)
Route service integrations (tribos.studio, Strava, Ride with GPS) with the Settings → Accounts section that authenticates them, plus S20's current weather — the Routes tab itself shipped in M8. Ride history (S14) + detail view (S15) with vehicle pass timeline. Apple Watch app + complication (S17). HR/cadence graphs. Strava/Garmin export. Dashboard customization (S07, S08). Multi-bike management — bikes own their sensors, circumference lives on the speed sensor (DataModel.md §3.9) — plus the S05.1 bike picker.

### Phase 3 — AR, Power & Platform (Target: +4 months post-Phase 2)
Power meter BLE support, ENGO 2 / ActiveLook AR integration (S18).

---

## 14. Open Questions

| # | Question | Owner | Priority | Status |
|---|---|---|---|---|
| OQ1 | SwiftData vs CoreData? | Engineering | High | ✅ **Resolved: Hybrid — CoreData for TrackPoint time-series, SwiftData for summaries** |
| OQ2 | Does Garmin's mobile SDK provide a cleaner Varia BLE path than raw CoreBluetooth? Evaluate in M2 spike. | Engineering | High | ✅ **Resolved: Combined approach. Use CoreBluetooth and apply for Garmin developer program** |
| OQ3 | iPad support? | Product | Low | ✅ **Resolved: No iPad** |
| OQ4 | Audio alert delivery: tones vs synthesized voice? | Design | Medium | ✅ **Resolved: Tones — three-tone system (All Clear, Warning, Danger). Spec in `Audio.md`.** |
| OQ5 | Override Silent Mode for L3 danger alerts? | Design | High | ✅ **Resolved: Yes, user opt-in. Warning and All Clear respect Silent Mode always.** Superseded 2026-11-03: every tone rings through, because `.ambient` can't play with the screen locked |
| OQ6 | App name for App Store? | Product | Medium | ✅ **Resolved: Cyclometer** |
| OQ7 | Minimum Varia RTL515 / RCT715 firmware version required for BLE characteristic support? | Engineering | High | ✅ **Resolved: v2.00 or v3.00 depending on the production run** |
| OQ8 | Include basic Apple Watch complication in Phase 1? | Product | Medium | ✅ **Resolved: Defer to Phase 2** |
| OQ9 | HR zone formula: Karvonen-only or allow custom percentages in MVP? | Design | Low | ✅ **Resolved: Karvonen-only** — since #238 the fallback behind Health's preferred zones (§8.5) |
| OQ10 | TestFlight beta: open or closed? | Product | Low | ✅ **Resolved: Open beta** |
| OQ11 | Does Garmin Varia RTL515/RCT715 expose radar return signal amplitude over BLE for vehicle size inference? | Engineering | Medium | ✅ **Resolved: No it does not** |
| OQ12 | Navigation: `MKDirections` routing or GPX import only? | Design | Medium | ✅ **Resolved: GPX import only. No in-app route creation in MVP.** |
| OQ13 | Wheel circumference presets and calibration? | Design | Low | ✅ **Resolved: Common presets (700c, 650b, 29", 26") + manual entry + GPS auto-calibration at 2% discrepancy threshold over two consecutive 1,500 m windows (revised from 5% / 500 m — see §8.9.2). See §8.9.** |
| OQ14 | Radar visualization approach: arc, strip, ring, adaptive, or map overlay? | Design | High | ✅ **Resolved: Option F — right-side sidebar strip with car icons; vehicle position encodes relative distance. See §8.2 and `assets/design/Design.sketch` — S06.** |
| OQ15 | Vehicle pass detection: minimum approach distance threshold before qualifying as a pass vs. turn-off? | Engineering | Medium | Open — requires field testing with RTL515/RCT715 to determine realistic detection parameters |
| OQ16 | Audio tone fine-tuning: exact frequencies, durations, and waveforms validated on real ride (phone in jersey pocket at speed)? | Design | Medium | Open — `Audio.md §Acceptance Criteria` defines test requirements; field test required before M4 freeze |
| OQ17 | Should the Live Activity gain Pause / Resume buttons (`LiveActivityIntent`) now that the intents exist? §8.10 removed them in v0.6.7. | Product | Medium | Open — §8.11 keeps the Live Activity display only; Siri, the Action Button and Control Center cover pause and resume |
| OQ18 | Should Start Ride start a ride directly, skipping the Start Sheet, for a true one-press start from the Action Button? | Product | Medium | Open — §8.11 opens the Start Sheet, keeping its sensor check and its role as the only writer of the Ride row (#344) |

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
| **`.fit` route import** | GPX only. Every route source the rider plans on exports GPX, and a second parser buys nothing |
| **In-app route creation** | Riders plan routes externally (tribos.studio, Komoot, Strava) and import GPX |
| **`MKDirections` routing** | Resolved out of scope for MVP (OQ12) |
| **Live Strava segments during a ride** | Strava licenses Live Segments to partner devices and apps only, for its subscribers. Building it from Strava's segment data would replicate Strava functionality, which its API terms forbid (§8.12). A ride's segments show on S15 after Strava processes the upload |

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
     creator="Acme Ride"
     xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v2"
     xmlns:cyc="http://acmeapps.xyz/ride/xmlschemas/VehicleEvent/v1"
     xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
     xsi:schemaLocation="
       http://www.topografix.com/GPX/1/1
       http://www.topografix.com/GPX/1/1/gpx.xsd
       http://www.garmin.com/xmlschemas/TrackPointExtension/v2
       http://www.garmin.com/xmlschemas/TrackPointExtensionv2.xsd">

  <metadata>
    <name>AcmeRide_2026-03-31_08-15</name>
    <time>2026-03-31T08:15:00.000Z</time>
  </metadata>

  <!-- Vehicle pass events recorded as waypoints at rider position when vehicle cleared -->
  <!-- Apps that don't support cyc: namespace will read these as generic waypoints -->
  <wpt lat="36.0726" lon="-79.7920">
    <time>2026-03-31T08:15:23.418Z</time>
    <name>Vehicle Pass</name>
    <type>vehiclePass</type>
    <extensions>
      <cyc:VehiclePassEvent>
        <cyc:alertLevel>danger</cyc:alertLevel>
        <!-- at the peak closing sample, not at the pass: 62.1 - 28.4 = 33.7 km/h closing, past the 30 km/h danger threshold -->
        <cyc:riderSpeedKph>28.4</cyc:riderSpeedKph>
        <cyc:estimatedPassSpeedKph>62.1</cyc:estimatedPassSpeedKph>
        <!-- vehicle ground speed, not closing speed; omitted if the vehicle was never observed approaching -->
      </cyc:VehiclePassEvent>
    </extensions>
  </wpt>

  <trk>
    <name>Morning Ride</name>
    <type>cycling</type>
    <trkseg>

      <trkpt lat="36.0726" lon="-79.7920">
        <ele>220.1</ele>
        <time>2026-03-31T08:15:01.004Z</time>
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
- Every `<time>` is UTC with a 3-digit fraction of a second (#416). Track points are stamped on a 1 s timer tick whose jitter can put two consecutive points in one whole second; whole-second times would give them the same `<time>`, and a reader deriving speed from time deltas would divide by zero. A reader of these files must also accept whole seconds: exports made before #416, and other tools' files, carry them
- `cyc:VehiclePassEvent` is a Cyclometer-defined extension. No industry standard exists for vehicle pass events as of v0.4.
- The `cyc:` namespace URI (`http://acmeapps.xyz/ride/xmlschemas/VehicleEvent/v1`) does not need to resolve to a live schema document; it serves as a unique identifier
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
