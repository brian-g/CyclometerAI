# tasks/todo.md — #199 W8 route polyline overlay + persisted map orientation

Branch: `feat/199-map-route-orientation` · Milestone M8 · Plan: `~/.claude/plans/joyful-crunching-starlight.md`

Decisions (Brian, planning):
- The widget is always heading-up and has no controls.
- `mapOrientation` governs the sheet only.
- A loaded route tilts both maps, north-up included.
- No pixel snapshots of a live Map: logic tests, a button snapshot and simulator shots instead.
- The sheet gains `MapPitchToggle`, route overview and the orientation toggle.

## 0. Spike: tilted follow (gate). PASSED, `spike-a`

- [x] Throwaway seed-then-follow plus camera logging in `ActiveRideMapView` (replaced by the real view)
- [x] Sim run on `42B5213B`, a free ride at 8 m/s (`.build/199/spike.sh`):
  - A seed lands within about 5 ms of the write, and the next `.onEnd` switches to follow.
  - **Pitch holds.** The widget read 35.0° across 1,921 continuous samples, the sheet 35.0° across 194.
  - MapKit clamps a 60° (and a 40°) request to **35°** at the default follow distance: 1.6 km on the widget,
    5.3 km on the sheet.
  - The tilt is visible in the screenshots: 3D buildings at the widget's edge, and the sheet's toggle reading "2D".
  - **MapKit never dropped the widget's heading-follow by itself:** 0 of 671 samples between seed A and the
    deliberate north-up seed C.
  - The north-up seed holds heading 0 with `followsHdg=false`.
  - **The simulator never rotates:** heading stayed 0°/360° through the right turn. Heading-up rotation is a
    device check.
- Moved to the final drive: body cost with a 5,000-point route (it needs the route plumbing), and location denied
- Harness findings for the final drive:
  - **The tap missed.** A tap on the widget's user-location dot didn't open the sheet. Later found to be the
    auto-dim wake tap (section 8), not the dot.
  - **"Open" hit the map.** The minimised-ride accessory's "Open" stays in the hierarchy under the dashboard, so
    `app.buttons["Open"]` exists even when the dashboard isn't minimised, and tapping it hits the map widget.
  - **The grabber ignored drags.** Neither XCUITest drag on it minimised the dashboard.

## 1. Preference

- [x] `MapOrientation.swift`; `AppPreferences.mapOrientation` plus its decode line

## 2. Camera policy

- [x] `RoutesMapCamera.region(fitting:)` extracted
- [x] `LiveMapCamera.swift`:
  - Surface, Mode, mode, needsSeed, seed, follow, isFollowing, needsCorrection, orientationTap, overviewRegion
  - a 1 s fallback in case a seed never reports landing

## 3–5. Views and wiring

- [x] `ActiveRideMapView`: route line, camera sequence, widget correction, the sheet's control column (`.mapScope`)
- [x] `MapSheetButtons.swift`: orientation and overview buttons
- [x] `Spacing.strokeMapRoute` / `strokeMapTrack`, and `Spacing.mapControl`
- [x] `MapWidget`, and one `mapWidget` helper for both `RideDashboardView` call sites
- [x] `ActiveRideFeature`: `@Shared`, `mapOrientationToggled`, comments

## 6. Tests

- [x] `AppPreferencesTests`: round trip and legacy decode
- [x] `LiveMapCameraTests`
- [x] `ActiveRideFeatureTests`: the toggle
- [x] `MapSheetButtonsSnapshotTests`, plus its CI skip line
- [x] Run the targeted suites; record and verify the snapshots; look at every image (section 8)

## 7. Specs

- [x] UX.md §W8
- [x] PRD §8.6: orientation, route colour, tilt
- [x] DataModel.md §3.6: the field, its consumers, the #94 note, OQDM8

## 8. Verify

- [x] Build clean, no new warnings: every warning in the log is in a file this branch doesn't touch, or is one of the
      pre-existing `fixedNow` warnings in `ActiveRideFeatureTests` (lines 2219–2457, above this branch's insert)
- [x] Targeted suites: **157 tests in 18 suites passed**. All 19 new or changed test names are in the log, each once
- [x] Button snapshots recorded (6 fail on first record, as expected), then verified (6 pass). Looked at all six:
      the glyphs render in `cyPrimary`, light and dark. **The glass circle doesn't render in the offscreen harness**,
      so the snapshots pin glyph, colour and size; the sim shots judge the material
- [x] Drive build (`.build/199/dd-drive`, fresh, caching off). `Cyclometer.debug.dylib` carries "Show whole route",
      "Map orientation", `location.north.line.fill` and `n.circle`
- Edits after the drive's build, so not in the drive binary (they are in the revert and final builds):
  - the `Spacing` map strokes became literals, with the same values;
  - `engage()`'s no-camera branch now asks `needsSeed`.
- First final drive, stopped after run 1 of 7:
  - **The route widget looked right:** `cyMapRoute` ahead of the rider, the track inside the wider route line over
    the part ridden, and no compass.
  - **The sheet never opened.** The tap at (0.2, 0.78) didn't reach the widget, like the spike's tap on the location
    dot. The UI test now tries six points and prints which one opened the sheet.
  - **A new fault, caused by #199:** `Bound preference MapScopeRegistryKey tried to update multiple times per frame`,
    as the route loaded. Fixed: only the sheet is map-scoped now, since the widget has no controls to scope.
- [x] Second drive, route-light only (fresh `dd-drive` with both fixes): **passed**, and there is no MapScopeRegistryKey fault.
  - Every sheet check held: heading-up → north-up; overview; re-engage without switching; the ride resumes after
    a relaunch (on route at 467 m) and the sheet reopens north-up.
  - **Widget taps "missed": not a bug, and my first diagnosis was wrong.** 3 of 6 widget taps across the drives
    didn't open the sheet. I blamed MapKit and moved the tap into a clear overlay, and the next drive missed the same
    way.
    - The cause is the auto-dim (#110). After `dimAfterSeconds` (30 s) without a touch the dashboard dims, and its
      blocker swallows the first tap to wake it. The dim lowers backlight only, so no screenshot shows it.
    - The timings fit: every miss came 32 s or more after the last touch, while the post-relaunch taps (about 12 s)
      and the taps just after a wake all worked.
    - The overlay is reverted. The UI test keeps its retry, with a corrected comment.
  - **The shared column looked wrong:** MapKit's scoped controls lost their styling (a green square re-centre, a bare
    "2D"), and my glass buttons were about 63 pt against MapKit's 42 pt.
- **Brian: one column, restyled** (asked with both screenshots, 2026-09-14). MapKit's controls get
  `.buttonBorderShape(.circle)` (WWDC23), and my buttons shrink to MapKit's size.
- Revert checks stopped (SIGINT, so the script restored its mutation) to rerun on the final code. Every mutation
  target was checked present exactly once afterwards.
- Results of the stopped pass:
  - baseline: 0 failed (35 Swift Testing and 6 XCTest);
  - (a) to (g): each failed exactly its predicted tests, and every file was restored.
- [x] Restyled build (incremental `dd-drive`, caching off): clean, with no warnings from touched files. Button
      snapshots re-recorded (6 recorded, then 6 verified), and all six looked at. They still show only the glyph:
      the glass circle doesn't render offscreen, with `glassEffect` either. So the snapshots pin glyph and colour,
      not the button's size or material (a glyph swap still fails them); the sim shots judge the circle
- [x] Restyled column checked on route-light: five matching 44 pt glass circles (re-centre, 2D/3D, compass,
      orientation, overview), and every sheet state right
- [x] Final drive, all seven runs: fresh `dd-drive` with the app code final (scope fix, restyle, overlay reverted).
      The build is clean, with no warnings from touched files, and the binary carries the new strings
  - Route light and dark, free ride light and dark, cpu-L and cpu-dense: **all passed**. On the free rides the
    sheet offers no route overview.
  - **Screens:** route, light and dark, and free ride, light and dark, all look right. Dark mode draws the route in
    the lighter `mapRoute` (#7D7AFF), and the glass column is dark too.
  - **CPU:** the 123-point route averaged 10.3% (max 145%), the 5,000-point route 11.6% (max 149%). A dense route costs
    about a point.
  - **Denied couldn't run.** With location denied, onboarding's "Next" stays disabled (#105's own gate), so no ride
    starts. It isn't driven. The map's denied path is safe by construction: a `.userLocation` position counts as
    following even without a fix, so the correction never fires.
  - **The MapScopeRegistryKey fault came back, once per route run and never on a free ride.** In both runs it fell
    about 0.1 s before the post-relaunch sheet tap, the one opening north-up:
    - `onAppear` wrote heading-up → north-up follow while the sheet's map registered its scope;
    - heading-up openings write the value already there, and none of the five has faulted;
    - one earlier north-up opening didn't fault, which fits a same-frame race.
  - Fix: the initial position comes from `init`, and `onAppear` no longer writes it.
- [x] Verified the fix (incremental `dd-drive`, no warnings from touched files):
  - two light route runs and one dark route run all passed;
  - each opened the sheet north-up after the relaunch, with **0 MapScopeRegistryKey faults and no other new fault**
    (2 of 3 north-up openings faulted before the fix);
  - each first sheet tap still hit the auto-dim wake, as expected.
- [x] Screenshots sent to Brian: the widget and sheet with a route (light and dark), heading-up, north-up, overview,
      and the free ride (light and dark)
- [x] `.build/199/final.sh`:
  - **Throwaways moved out:** no `SimDrive` file is in the tree, and none appears in either test log.
  - **Revert checks,** from a fresh `dd-revert`. The baseline passes. Each of 16 mutations fails exactly its predicted
    tests, and every file is restored byte-for-byte:
    - (a) decode line → round trip; (b) fallback → legacy decode;
    - (c) widget honours orientation → both widget tests; (d1)/(d2) controls, gestures → the #62 guard;
    - (e) sheet hardcoded → the sheet test; (f)/(g) tilt rules → tilt, flat;
    - (h) heading reset → the north-up seed test; (i) `region(for:)` → overview contains, tiny-route floor;
    - (j) always toggle → both re-engage tests; (k)/(l) correction → sheet left alone, widget put back;
    - (m) no write → the TestStore test; (n) never seed → the seed rule; (o) glyphs → the 4 orientation snapshots;
    - (p) unpadded `region(fitting:)` → a `RoutesMapCameraTests` floor test and both overview tests.
  - **"TREE DIFFERS FROM START" is my own edit.** The script printed it because I wrote this file at 19:31:06, a
    second after the script hashed the tree (about 19:31:05). Every file it mutated was verified restored, and
    `git status` shows exactly this branch's files.
  - **Final build**, from a fresh `dd-final` with caching off: clean, with no warnings from touched files.
  - **Full suite, parallel: 1,117 / 1,117 passed.**
  - **CI-equivalent** (serial, 13 snapshot suites skipped): **1,045 / 1,045 passed**, with **1,038 Swift Testing
    tests in 98 suites**.
  - That is `main`'s 1,094 / 1,021, plus 17 new Swift Testing tests and 6 snapshots. The new tests are in both logs
    by name.
- [x] Memory:
  - `mapkit-heading-follow-gotchas`: the #62 outcome, tilted follow, map-scope faults;
  - `mapkit-snapshot-flaky`: the pattern, replacing an example that never existed;
  - `simulator-ui-drive`: the auto-dim wake tap, the hidden "Open", grabber drags.
- [x] Commit and PR: `de31541`, #235

## Carried over

- [ ] #202 comment on Brian's go-ahead (open from #198). Add #199's flags to it; draft in the scratchpad
  (`comment-202.md`):
  - S19/S20's route colour;
  - PRD's `UserProfile` appendix.
  - Dropped: UX §W8's "position dot in `brPrimary`". The system marker takes the app tint and is green in every
    drive screenshot.

## Review

**Built.**
- The route being ridden is drawn in `cyMapRoute`, beneath the travelled track, on the W8 widget and its sheet.
- The widget is always heading-up and has no controls. Its compass was #62's way out, and it's gone.
- The sheet opens in the saved `mapOrientation`. Its one restyled column holds re-centre, 2D/3D, compass, orientation
  and route overview.
- A loaded route tilts both maps: 35° at MapKit's default follow distance.

**Verified.**
- A spike proved seed-then-follow before anything was built on it.
- Targeted suites: 157 tests in 18 suites.
- Revert checks: 16 mutations, each failing exactly its predicted tests.
- Drives: light and dark, with and without a route, and dense against normal CPU. No new faults after the two scope
  fixes.
- Full suite: 1,117 parallel, 1,045 CI-equivalent.

**Deviations from the approved plan.**
- **Only the sheet is map-scoped, and the initial camera comes from `init`.** Each change fixed a
  MapScopeRegistryKey fault.
- **The sheet's column is restyled** (Brian's call, after the first drive). It gets `.buttonBorderShape(.circle)` and
  44 pt glass buttons (`Spacing.mapControl`), instead of buttons the size of a tap target.
- **`needsSeed` is added.** A free ride's widget never seeds, so it starts exactly as it did before.
- **Re-engaging after the overview keeps the current distance**, rather than the last following camera's, as native
  re-centre does.
- **Location-denied wasn't driven**, because onboarding blocks without location.
- **The snapshots pin glyph and colour only.** Glass doesn't render offscreen.

**Caught before shipping.**
- The widget-tap "misses" were the auto-dim wake tap (#110). I blamed MapKit first, and a tap-overlay "fix" went
  through one drive before I checked the timings. It is reverted.

**For Brian.**
- **Tilt:** 35° is MapKit's clamp. A steeper view needs a closer camera, which is zoom, excluded by #199.
- **Heading-up rotation** needs a ride on a device.
- **#62** can close with this PR; your call.
- **#202:** the comment is drafted (S19/S20's route colour, PRD's `UserProfile` appendix).
- **Onboarding:** its location step keeps Next disabled when location is denied. Seen in the drive; not in scope.
