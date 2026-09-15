# tasks/todo.md — #200 [M8] W9 Directions widget

Branch: `feat/200-w9-directions` · Plan: `~/.claude/plans/hidden-snacking-garden.md`

Decisions (Brian, planning):
- W9 takes the **W10 Weather cell** (row 5 right, 1×1) while a route is followed.
- The gate is `navigation.isFollowingRoute`, so a loaded route **and** turn-by-turn on.
- No distance (before the first match, off route, past the last turn, complete) → "—", with no arrow.

Spec tensions:
- Design.sketch has no W9 artboard, so W9 follows its sibling widgets.
- "No Route" can't be reached on today's dashboard. It's built and snapshotted for S07/S08.

## Implementation

- [x] Branch
- [x] `UnitSystem.turnDistance(fromMeters:)`: m/ft rounded to 10 below 1 km / 0.1 mi, km/mi to 1 decimal above
- [x] `View.liveMapSheet(...)` extracted from `MapWidget`, shared with W9
- [x] `DirectionsWidgetView.swift`: 1×1 / 2×1 / 2×2, turn / "—" / No Route
- [x] `Font.cyTurnGlyphCompact` token (40 pt) for the 1×1 / 2×1 arrow
- [x] `RideDashboardView` row 5: W9 in place of Weather while `isFollowingRoute`

## Tests

- [x] `UnitSystemTests`: `turnDistance` thresholds, rounding, clamping
- [x] `NavigationFeatureTests`: the distance counts down and rolls to the next turn; nil off route and past the last turn
- [x] `NavigationFeatureTests`: `isFollowingRoute` needs a route and turn-by-turn
- [x] `DirectionsWidgetSnapshotTests`: 14 references, every PNG looked at, none blank
- [x] `tests.yml` skip list

## Verify

- [x] Build
- [x] Full suite green locally: 1043 Swift Testing tests in 98 suites plus 93 XCTest, 0 failures. All 5 new Swift Testing
  tests appear by name, and all 14 W9 snapshots pass against their references.
- [x] Live sim, on a route (throwaway seed + XCUITest, since deleted): W9 sits in Weather's cell reading "↱ 0.2 mi",
  and a tap opens the map sheet with the route
  - Log: "route loaded — 1 turns over 1200 m", "on route at 201 m". The only runtime issue is the known onboarding
    `ifLet` warning.
- [ ] Live sim, free ride with Weather back: **not driven**. The drive's swipe-down minimised the ride, so it never
  reached Finish. The else branch is the unchanged pre-#200 layout, and the unit test pins the gate.

## Review

**Outcome.**
- W9 is built at 1×1 / 2×1 / 2×2 and placed in W10's cell while `isFollowingRoute`.
- The full suite is green: 1043 Swift Testing tests plus 93 XCTest.
- The live drive confirms placement and the tap-to-map sheet.

**Observed, not changed:**
- Above 0.1 mi the imperial display steps in 0.1 mi (161 m), so on a live approach "0.2 mi" held for 10 s. The
  metre-level countdown is proven in `NavigationFeatureTests`. Apple Maps uses the same steps.

## Review round 1 (Brian, on PR #237)

- [x] "There is no 2x2 variant of this." The `.twoByTwo` case now falls through to the 1×1 layout, as W5 does.
  The 4 2×2 snapshots and their references are gone. UX.md §W9 now lists sizes 2x1 and 1x1.
- [x] "The Directions widget is there all of the time." The `isFollowingRoute` gate is removed and W9 always sits in
  row 5 right. With it went the gate test and the now-unused `WeatherWidget` placeholder, and UX.md §S05.4's row 5
  now says Directions. "No Route" is what a free ride shows.
- [x] "Add a 2x1 route widget to the second page under the cadence." Page 2 now has a W9 2×1 row under Cadence.
- [x] Lesson and memory: dashboard widgets are always present, and ride state never gates a grid cell.
- [x] Full suite green: 1042 Swift Testing tests in 98 suites plus 89 XCTest, 0 failures. All 10 W9 snapshots pass.
  A first run was killed by the system for low memory; I shut down the drive simulator and re-ran.
- [x] Push, and update the PR body

