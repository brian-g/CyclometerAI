# #79 — Cadence zones: always drawn on W5, configurable in S12

Plan: /Users/brian/.claude/plans/groovy-chasing-spring.md
Branch: `feat/79-cadence-zones`

- [x] 1. Tests first: `CadenceZoneTests` (5 zones, boundaries, stepping, decoding)
- [x] 2. Model: `CadenceZone` (5 cases), `CadenceZoneBoundaries`, `AppPreferences.cadenceZones`
- [x] 3. `Ride` columns zone1…5 + migration test; persistence round-trip
- [x] 4. `CadenceFeature` classifies with shared boundaries (+ test)
- [x] 5. W5 widget: bands always drawn, configured bands/colours; detail sheet labels
- [x] 6. S12 Cadence Zones section (+ SettingsFeature tests)
- [x] 7. Compile fallout in other tests; snapshots re-recorded and inspected; previews
- [x] 8. UX.md §W5/§S12, DataModel.md §3.1/§9
- [x] 9. Full suite, review, PR (sim drive not run — see review)

## Review

- Unit suite: 1,819 passing, 0 failures (run without `PersistenceClientTests` and `MapWidgetAccessibilityTests`, which deadlock together locally). `PersistenceClientTests` on its own: 47 passing, 0 failures.
- Snapshots re-recorded: all 9 W5 references, the Add Widget catalog, and Dashboard edit chrome. Each was compared visually with main. The No Signal states now draw the bands. There is a new full-height S12 snapshot that shows the Cadence Zones section.
- Not verified: the simulator drive of S12 (step until clamped, relaunch, Reset). The throwaway test was written but never run, then deleted at commit. Stepping, clamping, persistence and reset are covered by `SettingsFeatureTests`. The detail sheet's new zone labels have no snapshot because the sheet is private.
- Follow-up: W4 `HeartRateWidget` still hides its bands until data arrives, so it is now inconsistent with W5.
