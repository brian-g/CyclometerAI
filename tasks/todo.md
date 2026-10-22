# #426 — S20 Previous Rides ↔ S15 Route links

Plan: /Users/brian/.claude/plans/precious-napping-sunrise.md
Branch: `feat/426-route-ride-links`

- [x] 1. Tests first: persistence (`fetchRides(routeId:)` title, `fetchRideStats` routeId, `fetchRouteSummary`), RideDetail route load, Rides/Routes stack pushes, App delegate
- [x] 2. Data: `RouteRideSummary.title`, `RideListSummary(_:)`, `RideStats.routeId`, `fetchRouteSummary`
- [x] 3. Shared `RideRoutePath` + `RideRoutePathView`; both tabs on it; `.detail` renames
- [x] 4. `RidesFeature.delegate.useRoute` → `AppFeature`
- [x] 5. `RideDetailFeature.route` + S15 Route section; S20 Previous Rides links
- [x] 6. Snapshot harnesses, re-record S20, new S15 cases; previews
- [x] 7. UX.md §S15/§S20
- [x] 8. Full suite, sim drive, review, PR

## Review

- **Navigation.** S15 and S20 each link to the other, so both tabs now stack one `RideRoutePath` (`.ride`, `.route`). TCA's `NavigationLink(state:)` only presents when its state type is the stack's element type, so a per-tab `Path` could not hold a link built inside the shared detail lists. `RideRoutePathView` is the one `destination:` both stacks render.
- **Use Route on the Rides tab.** `RidesFeature` forwards S20's delegate as its own `useRoute`, and `AppFeature` handles both tabs' delegate the same way. The CTA hides while a ride records, as on the Routes tab.
- **Data.** `RouteRideSummary.title` seeds S15's title. `RideStats.routeId` plus a new `fetchRouteSummary` (summary only, no polyline decode) gives S15 its route. The route arrives in the same action as the stats, so the row never turns from plain text into a link on screen. A deleted route shows its name with no link.
- **Tests.**
  - 11 new cases.
  - Full `CyclometerTests` minus the two known local hangs: exit 0, 1,790 unique passing cases. `PersistenceClientTests` (47) and `MapWidgetAccessibilityTests` (3) were run alone and passed.
- **Snapshots.**
  - Both harnesses now host the list in a `NavigationStack` with its bar hidden, and set TCA's `navigationDestinationType` (SPI). Outside any stack a link reports "not presentable" and draws dimmed. With the stack, only the two link cases moved.
  - Re-recorded S20 `no-elevation-rides`. New S15 `on-route` and `deleted-route`.
- **Sim drive** (throwaway XCUITest, deleted), with no TCA runtime issues logged:
  - Routes → S20 → Previous Rides row → S15 under the ride's title → Route → S20.
  - Rides → S15 → Route → S20 → Use Route → Start sheet on that route.
- **Found, not fixed.**
  - `RouteDetailSnapshotTests`' `elevation-rides` reference ends at Current Weather. Since #252's Summary section it never shows Previous Rides, despite its doc comment.
- **Branch.** Mid-session the checkout switched to local `main` without a command from this session. It was switched back with the work intact.

---

# #402 — Shared TrendIndicator for W1, W4, W5

Plan: /Users/brian/.claude/plans/silly-knitting-iverson.md
Branch: `feat/402-trend-indicator`

- [x] 1. `CadenceTrendTests` (written first): W5's rule, cadence vs ride average, ±5 rpm, hidden at 0/nil/no average
- [x] 2. `AppFonts.dDINCapAccessory(_:)` (shared with the widget extension); `TrendIndicator.swift` (`Trend`, view, `.trendIndicator(_:)`, `HeroNumber.heroTrend(_:)`)
- [x] 3. `HeroNumber.heroCapAccessory(_:)`, offset to follow `.baselineOffset`
- [x] 4. W1 on the shared modifier — existing references unchanged
- [x] 5. `HeartRateTrend` → `Trend`; W4 on `heroTrend`; re-record + inspect W4
- [x] 6. W5 on `heroTrend`; new trend snapshots
- [x] 7. UX.md §W1/§W4/§W5
- [x] 8. Pixel measurement (≤1pt, ≈0.25×), unit-position diff, full suite, ios-reviewer

## Review

- **Component.**
  - `UI/Components/TrendIndicator/TrendIndicator.swift` holds the one `Trend` enum (W1's private `Trend` and `HeartRateTrend` are gone) and `TrendIndicator`, the single ▲ `cyRatingGood` / ▼ `cyRatingBad` mapping.
  - It is placed with `.trendIndicator(_:)` (W1's raw `Text`) or `HeroNumber.heroTrend(_:)` (W4, W5).
- **Shared with the widget extension.**
  - `HeroNumber.swift` and `AppFonts.swift` also compile into `CyclometerWidgetsExtension` (#306), so they can't see `Trend` or `cy*` tokens.
  - The digit-top placement moved out of `SpeedWidget` into `AppFonts` as a generic `dDINCapAccessory(_:)`, which hands the accessory the digits' height. `HeroNumber` exposes it as `heroCapAccessory(_:)` and applies it only when one is set (review), so other heroes render exactly the view tree they had before.
- **Baseline offset.** `HeroNumber` lowers its digits with `.baselineOffset(-6)` (medium). That moves glyphs, not an overlay, so the first W4/W5 recording put the arrow 5.3–6.0pt above the digits (measured). The accessory now takes the same offset.
- **W5 rule (asked).** Cadence against the ride average, more than 5 rpm (`CadenceWidget.trend(cadence:average:)`). Steady at 0 rpm, nil, or no average.
- **Measured** (3× snapshots, scratchpad `measure.swift`):
  - W4 and W5: arrow top within 0.0–0.7pt of the digit tops, 0.26× their height.
  - W1 at 2×1 and 1×1: 0.7pt, 0.24×.
  - W1 at 2×2: 1.3pt below the tops of "22.0", which is D-DIN's round-glyph overshoot (1.22pt at 136pt, measured with CoreText; flat digits end exactly on the cap height).
- **Unit.** W1's references are unchanged. W4's changed pixels are confined to y 24–39pt (the arrows); "bpm" sits at y ≈ 63–75pt.
- **Tests.**
  - `CadenceTrendTests` (3) was written first and failed to compile, then passed.
  - W4: 4 references re-recorded and inspected. W5: 3 new trend snapshots.
  - Full `CyclometerTests` minus the two known local hangs: exit 0, 1737 unique passing cases. `PersistenceClientTests` (47) and `MapWidgetAccessibilityTests` (3) were run alone and passed. The run was repeated after the review fix.
- **Scheme.** The local checkout had no `Cyclometer` scheme (the xcuserdata suppressed autocreation, and the shared file never existed). A shared `Cyclometer.xcscheme` is now added and tracked (asked).
- **Not done.** VoiceOver for W5's trend (with #401).

---

# #309 — Live Activity: Lock Screen presentation

Plan: /Users/brian/.claude/plans/shimmering-leaping-flask.md
Branch: `feat/309`

- [x] 1. Tests first: `RideLockScreenSnapshotTests`, `LiveActivityContrastTests` (fail to compile)
- [x] 2. `HeroNumber` stores a `Text`; `init(_ value: Text, unit:)` — existing HeroNumber/widget references unchanged
- [x] 3. `RideLockScreenView` (shared with the extension): Sketch hierarchy, `pauseTime` timer, stale, reduced luminance, `backgroundOpacity = 0.85`
- [x] 4. `RideLiveActivity` on it: background tint, previews for every state
- [x] 5. Record + inspect references; contrast test green
- [x] 6. PRD §8.10, colors.md, TCA.md §8
- [x] 7. Build, full suite, simulator Lock Screen screenshots, ios-reviewer
- [x] 8. (asked) `HeroNumber` reports the baseline its digits are drawn on — 24 references re-recorded
- [x] 9. Simulator findings: timer slot, dark card on the Always-On display

## Review

- **View.** `RideLockScreenView` is shared with the extension (exception set, plus `Opacity.swift`). The row is the status mark, then time and distance at `.small` (distance's unit under it, Sketch's `small-hero`), then speed at `.medium` (asked: Sketch over the PRD). Stale dims values to `cyTextSecondary` and adds "Reconnecting…".
- **Timer.** One `Text(timerInterval:pauseTime:)` for riding and paused, so the frozen value is formatted like the running one. The old `.minuteSecond` read 94:34 past the hour.
- **`HeroNumber` takes a `Text`.** The `String` inits wrap with `Text(verbatim:)`, so they behave as before.
- **Baselines (asked: fix globally).**
  - `.baselineOffset` lowered `HeroNumber`'s digits but not the baseline it reported. Measured on W1 2×1: the medium hero sat at 70.0pt and the small avg/max at 74.0pt.
  - `digitBaselines(_:)` reports the drawn baseline. All three now read 70.0pt; on the Lock Screen, time and speed both read 72.0pt.
  - 24 references moved: W1, W4 and W5 at 2×1, Elevation, Directions (the street name's last line now sits on the distance baseline), and S07/S08, which draw them. Each change is confined to the stat column at x ≈ 280–384pt.
- **Card (asked).** `cyBgPrimary` at `Opacity.liveActivityCard` = 0.85. `LiveActivityContrastTests` checks both modes' text over the worst-case wallpaper: dark 4.8:1 and light 5.3:1 for secondary.
- **Simulator Lock Screen** (throwaway XCUITest, deleted).
  - `Text(timerInterval:)` took a far wider slot than it showed, pushing distance across the card. It's now laid over a hidden "0:00:00" hero.
  - With the tint dropped to `.clear` on the Always-On display (the PRD rule), iOS drew a light glass and the units nearly vanished. The Always-On card is now always the dark variant; the PRD line is struck and amended.
  - The simulator was in light appearance, but iOS rendered the activity dark on its wallpaper. The light card is covered by the snapshots, not by a Lock Screen capture.
- **ios-reviewer.**
  - Fixed:
    - D-DIN's digits are proportional (no `tnum`; "4" is 14.14pt against "0" at 13.70pt at 34pt). So "4:44:44" overflowed the "0:00:00" slot. The slot is now "4:44:44", or "44:44:44" from 9 h.
    - The contrast test now resolves the production `card(...)` and covers the Always-On case. Mutation check: at 0.67 all three cases fail.
  - Not taken:
    - "Always-On tint may not follow": the simulator showed it does (glass with `.clear`, dark after the fix).
    - Increase Contrast: no colour set has a high-contrast variant.
    - Swift 6 strict mode: project-wide, not #309.
    - Global layout change: approved.
- **Tests.**
  - New: `RideLockScreenSnapshotTests` (11, all inspected) and `LiveActivityContrastTests` (3).
  - Full `CyclometerTests` minus the two known local hangs: 1817 unique passing cases. `PersistenceClientTests` (47) and `MapWidgetAccessibilityTests` (3) were run alone and passed.
- **Not done.**
  - The light-mode ring and pause glyph (`cyPrimary`) are 1.7:1 at worst against the card, under the 3:1 non-text minimum. The shared `OpenRingProgressView` is a follow-up.
  - The Dynamic Island is still a placeholder (#310). It now shares `ElapsedTime.text` and `RideStatusMark`.
  - Device sunlight and AOD checks (#316) haven't been run for this design.

---

# #310 — Live Activity: Dynamic Island presentations

Plan: /Users/brian/.claude/plans/310-calm-starlight.md
Branch: `feat/310-dynamic-island`

Sketch "S22 - Dynamic Island" and "S22 - Expanded Dynamic Island" win over the issue (asked): compact leading is the status mark, not elapsed time; compact speed is white.

- [x] 1. Tests first: `RideDynamicIslandSnapshotTests`, island rows in `LiveActivityContrastTests`
- [x] 2. `OpenRingProgressView.showsPercent` (default on; mini-player unchanged)
- [x] 3. `RideStatusMark`: `cyclometer.rider` with no route, `showsPercent`; `RideLockScreenView.distanceLayout`; `RideIslandSpeed`
- [x] 3a. (asked) Expanded row: `Spacing.lg` island margins, unit inline with a `ViewThatFits` fallback to unit-below; padding moved out of `RideLockScreenView`
- [x] 4. `RideLiveActivity`: compact, minimal, expanded; previews
- [x] 5. Record + inspect references; re-record #309's two no-route references
- [x] 6. PRD §8.10, UX §S22, colors.md
- [x] 7. Build, full suite, simulator island screenshots, ios-reviewer

## Review

- **Frames over the issue (asked).** Sketch's new "S22 - Dynamic Island" puts the 26pt status mark in compact leading, not elapsed time. Speed is trailing, white SF Pro Medium 18 (read from the layer), with no unit. "S22 - Expanded Dynamic Island" is the Lock Screen row with distance's unit beside it (`small-hero-h`). There's no minimal frame: minimal is the status mark, as the issue says.
- **Rider glyph (asked: whole Live Activity).** `RideStatusMark` draws `cyclometer.rider` itself with no route, sized to the mark (`resizable`, `Spacing.xs` inset): at `.title3` it ran 37pt wide. #309's two no-route Lock Screen references moved; only the glyph changed.
- **Small ring (asked).** `OpenRingProgressView.showsPercent`, off in compact and minimal. The mini-player is unchanged.
- **Expanded on the simulator:**
  - The expanded row overflowed. `RideLockScreenView` padded itself 16pt inside the island's own ~18pt margins. The padding moved to the call sites; the Lock Screen references are unchanged.
  - Measured ideal row widths: inline 327pt (Sketch's values) to 359pt (4:44:44, 125.3 km, 45 km/h); unit below, 308–337pt. The island leaves ~338pt at its default margins.
  - Asked: `.contentMargins(.horizontal, Spacing.lg, for: .expanded)` (342pt), and a `ViewThatFits` that drops the unit under distance when inline doesn't fit.
  - "mph" was still cut. A red debug fill showed why: the region's bottom corners are rounded, and `HeroNumber`'s units hang below its frame. `.padding(.vertical, Spacing.sm)` fixed it.
  - Final shots: compact riding and paused, expanded riding and paused, nothing cut.
- **Stale.** Not seen on the simulator. With the app terminated for ~45s, the island still drew live styling: iOS hadn't marked it stale, or hadn't re-rendered. Snapshots cover the stale styling, as #309's do.
- **ios-reviewer.**
  - Fixed:
    - The minimal island had no VoiceOver element with no route (the glyph was hidden). Labels are now "Riding" and "Paused" (the symbol said "Pause", like a button).
    - Island speed speaks `spokenSpeed` (wide unit) plus "Reconnecting" when stale.
    - Header comment updated.
  - Not taken: none.
  - Noted:
    - On a 393pt phone (iPhone 15/16) the row gets ~333pt. Only the extreme case (337pt with the unit below) would truncate speed. Not simulated; follow-up if it matters.
    - Dynamic Type at accessibility sizes is unchecked.
- **Tests.**
  - New: `RideDynamicIslandSnapshotTests` (11, all inspected) and `LiveActivityContrastTests.islandPassesOnBlack`.
  - Full `CyclometerTests` minus the two local hangs: 1998 passed. `PersistenceClientTests` and `MapWidgetAccessibilityTests` passed alone (50).

### /code-review --fix (xhigh)

- **Kept the reviewer's 7 fixes:**
  - island speed spoken to the whole number shown (`spokenSpeed(fromMPS:fractionLength:)`);
  - `RideIslandStatusMark` extracted from five copies;
  - a metric island preview;
  - the remaining "bicycle glyph" docs (PRD, UX, `RideActivityAttributes`);
  - `Spacing.dynamicIsland` for the compact canvas;
  - the `metrics(_:)` parameter shadowing.
- **My miss:** the "337pt worst case" left out rides past 9 h, where `ElapsedTime.widest` reserves "44:44:44". Metric long rides then overflow the island (~351pt against 342) and the Lock Screen card alike; so does a 393pt phone at 4:44:44.
  - Asked: a last `ViewThatFits` fallback with speed's decimal dropped.
  - New snapshots: island 9:30 metric, island at 333pt, Lock Screen 9:30 metric. All three showed "4…" before the fix.
- **My miss:** `.font(.system(size: 18))` broke the design-system rule (no hardcoded sizes; map to the nearest text style). It's now `.body` medium, and the compact references moved.
- **Pause icon (asked):** sized to the mark, like the rider glyph, so Dynamic Type can't grow it past 26pt. On the Lock Screen it is now 40pt, filling the mark as Sketch's circle does. #309's seven paused/stale references re-recorded.
- **Not taken:**
  - Design.sketch on disk lacks the island frames (Brian to save and commit).
  - Ring track contrast on black (design).
  - Test helpers vs the system renderer.
  - `HeroNumber` reporting its drawn bounds (follow-up).
  - The `.now` timer snapshot pattern (pre-existing).

# #313 — Live Activity: S12 Show Live Activity setting

Plan: /Users/brian/.claude/plans/eager-enchanting-sonnet.md
Branch: `feat/313`

- [x] 1. `AppPreferences.isLiveActivityEnabled` (default on, `decodeIfPresent`) + test
- [x] 2. `SettingsFeature`: toggle + delegate, system setting read on `.task`/`.appBecameActive`, Open Settings + tests
- [x] 3. `LiveActivityFeature`: gate the start on the preference; `.preferenceChanged` starts/ends mid-ride; late `.started(true)` ends + tests
- [x] 4. `AppFeature`: forward scene-active to Settings, delegate to the ride + test
- [x] 5. `SettingsView`: row after Place Names, disabled when iOS is off, in-row explainer + Open Settings; previews
- [x] 6. Snapshots: re-record S12, add the iOS-off state, inspect
- [x] 7. UX.md §S12, PRD §8.10 + changelog
- [x] 8. Full suite (simulator check not done — see Review)

## Review

- **Preference.** `AppPreferences.isLiveActivityEnabled`, on by default; an older document decodes to on.
- **Gate.** `LiveActivityFeature`'s start (ride start, foreground retry) now needs S12's toggle as well as the system
  setting, through one `start(&state)` helper.
- **Mid-ride (asked).** `SettingsFeature` sends `.delegate(.liveActivityToggled)`; `AppFeature` passes it to a running
  ride as `.liveActivity(.preferenceChanged)`. Off ends the activity; on starts one. A request that lands after the
  toggle went off (`.started(true)` outside `.starting`) is ended, so nothing is orphaned.
- **System setting.** S12 reads `liveActivityClient.isEnabled()` on `.task` and on every scene-active (`AppFeature`
  forwards it), so coming back from iOS Settings updates it. Off: the toggle is disabled with its value kept (asked),
  and the row explains and links to iOS Settings (`openSettingsURLString`, as `WelcomeFeature`).
- **PR review: explainer in the row.** It moved from General's footer into the toggle's row, under it
  (`VStack` + `.caption`, as the HR override errors). Open Settings is `.borderless` so it, not the whole row, is
  the tap target. The footer is main's again. That also removed a ~7.5pt gap the first round had added above HR
  Zones in *every* state: an empty `VStack` still counts as a footer. I hadn't compared those references
  against main's, so I missed it; `testDefault` and `testHRZoneOverridesSet` are back to main's spacing (measured, 88px).
- **Placement (asked).** General, after Place Names.
- **Compiler.** `LiveActivityClient.previewValue = testValue` hit a circular-reference error once a preview used
  `testValue`; it now has an explicit type.
- **Tests.**
  - 5 `LiveActivityFeatureTests`, 3 `SettingsFeatureTests`, and 2 `AppPreferencesTests` assertions.
  - Mutation check: removing the gate, the late-start end, or AppFeature's forward turns 5 tests red.
  - S12 snapshots re-recorded, plus `liveActivitiesOffInIOS`; images inspected.
  - Full `CyclometerTests` green: 1824 unique cases passed, 0 failed.
- **Not verified.** No simulator drive with Live Activities off in iOS Settings; the explainer and link are covered by
  the snapshot and the reducer tests only.

---

# #424 — S12 wheel-circumference message under Circumference

Plan: /Users/brian/.claude/plans/ethereal-napping-pancake.md
Branch: `fix/424-circumference-message`

- [x] 1. `SettingsView`: message into the Circumference row (`VStack` + `.caption`, as Resting/Max HR); General's footer removed
- [x] 2. Previews: Custom wheel size; Custom wheel size, out of range (review: `bleCSCClient` stubbed)
- [x] 3. `SettingsSnapshotTests`: `customCircumferenceDraft` seed; `testCustomWheelCircumferenceInvalid`
- [x] 4. Run unrecorded first — only the custom reference should move
- [x] 5. Record, re-run green, compare against main's references
- [x] 6. Full `CyclometerTests` (Settings suites included)

## Review

- **Move.** The range message is a `.caption` line inside the Circumference row (`VStack(spacing: 4)`, as Resting/Max HR).
  It is still shown only for Custom: secondary colour, red while `isCustomCircumferenceInvalid`. General has no footer.
- **Nothing else moved.** Before re-recording, only `testCustomWheelCircumference` failed (plus the new test, which had no
  reference yet). `testDefault`, `testHRZoneOverridesSet` and `testLiveActivitiesOffInIOS` stayed pixel-identical.
- **Gap measured** (column x=70, 3×): General card → HR Zones card is 220px in custom, invalid and default (218px dark in
  both). On main the custom state had 304px, because of the footer. Rows above Circumference are unchanged.
- **New:** `testCustomWheelCircumferenceInvalid` (draft "900", red message). Previews: Custom wheel size, plus Custom out
  of range. The review stubbed `bleCSCClient` in `previewStore`, so committing in the canvas doesn't reach live BLE.
- **Tests.** The first full run hung on the known PersistenceClientTests × MapKit deadlock (confirmed with `sample`).
  Rerun with that suite skipped: 1778 unique cases, 0 failed. The suite alone: 47 passed. 1825 total, #423's 1824 + 1.
- **Not changed (review, left for a decision).** `Color.red` caption contrast on white (~3.55:1; `cyRatingBad` ≈4.98:1),
  shared with the HR rows. The validity of the message is shown only by its colour (pre-existing). The range copy is
  hard-coded rather than built from `WheelPreset.validRange`.

---

# #429 — S12 field errors in cyRatingBad; wheel message only when out of range

Plan: /Users/brian/.claude/plans/ethereal-napping-pancake.md
Branch: `fix/429-error-color`

- [x] 1. `SettingsView`: wheel message only while invalid; all three errors `cyRatingBad`
- [x] 2. Preview: HR overrides out of range
- [x] 3. `SettingsSnapshotTests`: HR draft seeds; `testHRZoneOverridesInvalid`
- [x] 4. Unrecorded run — only the two custom references + the new test should fail
- [x] 5. Record, re-run green, inspect against main (pixel colour check)
- [x] 6. No `Color.red` left; full `CyclometerTests`
# #433 — Absolute barometric altitude steps ~300 m mid-ride

Branch: `fix/433-altitude-step`
Approach (revised after review): **check against the relative barometer.** The first approach (a 10 m/s
rate gate) assumed 1 Hz readings through pauses. The CMAltimeter header says absolute updates arrive "whenever a
change in elevation is detected", and `CMLogItem.timestamp` is Mach time, which stops in sleep. A return step after a
gap passed the gate, so the ride stayed 97 m high for good. PR #434 is reworked on the same branch.

Now: on a phone with absolute altitude, the client also runs relative updates and attaches the barometer's latest
relative altitude to each absolute reading. The resolver compares Core Motion's change with the barometer's since
the last absolute reading. A disagreement of more than `reanchorToleranceMeters` (30 m, about 3.6 hPa, more than
weather moves a barometer in a ride stop) is a re-anchor and goes into the offset. Only the disagreement is taken
out, so real climb across a gap is kept. Timing and sleep don't matter, and slow re-anchors are caught.

- [x] 1. `AltimeterReading.absolute(meters:accuracy:barometerMeters:)`, defaulting to nil; drop `timestamp`
- [x] 2. `AltimeterSession`: relative updates alongside absolute on the same serial queue; latest attached
- [x] 3. `AltitudeResolver`: tolerance check replaces the rate gate; no barometer → pass through as on main
- [x] 4. Tests: step carried; step back after a gap cancels; lift passes; small drift passes; no barometer
      passes; ended drops offset (1473.9 m, from review)
- [x] 5. Replay without pause filling; barometer = the ride's own per-point changes minus Core Motion's jumps
- [ ] 6. UX.md §W14, doc comments; elevation suites; full suite; push to #434 and update its description

## Review

- **Client.** With absolute altitude available, relative updates run too, on the same serial queue, and the latest
  is attached to each absolute reading as `barometerMeters`. If the relative stream errors, it logs and the check
  switches off; absolute carries on as on main.
- **Resolver.** `reanchor = Δabsolute − Δbarometer` since the last absolute reading. Past 30 m it goes into
  `reanchorOffset`. Only the disagreement comes out, so real climb across a gap is kept. With no barometer value
  either side, it passes through unchanged (main's behaviour).
- **Tests** (`AltitudeResolverTests`, 6 new): step carried across (exact); step back after a 111 s gap cancels
  (the review's case); lift passes; a 5 m disagreement passes; no barometer passes; ended drops offset (1473.9 m,
  which fails if either reset is removed).
- **Replay** (no invented readings): Core Motion sends only the recorded points. The barometer is synthesized
  from the track's own changes minus Core Motion's four jumps, and the test says so. Ends within 10 m of Core
  Motion's final reading; the old rate gate would end 97 m high.
- **Mutation.** With the tolerance set to infinity (main's behaviour), `reanchorIsCarriedAcross` and
  `replayKeepsTheClimb` fail.
- **Open (not changed):** a ride killed mid-fault resumes on the wrong value and then absorbs the step back; a real
  >30 m correction after trust is rejected. Two concurrent CMAltimeter streams are device-only.
- **Full suite.** `CyclometerTests`: 2069 passed, 0 failed (TEST SUCCEEDED).

---

# #412 — Live Activity: notice when the system ends the activity

Plan: /Users/brian/.claude/plans/toasty-chasing-abelson.md
Branch: `feat/412-live-activity-system-end`

- [x] 1. Spike on the simulator: state transitions for a swipe-away and for "Don't Allow" (stop if a swipe passes `.ended`)
- [x] 2. `LiveActivityClient`: `LiveActivityEnd`, `ended()` (live: first `.ended`/`.dismissed`, logged), test value
- [x] 3. `LiveActivityFeature`: `Phase.dismissed`, `.ended(_)`, wait started on `.started(true)`, cancelled before own end
- [x] 4. Tests: feature (system end, dismissed, late signal), live client (`.default` → ended, `.immediate` → dismissed), mutation check
- [x] 5. PRD §8.10 + changelog
- [ ] 6. Full `CyclometerTests`; delete the throwaway UI test

## Review

- **Spike, iOS 27 simulator.** A throwaway launch hook plus a Lock Screen UI test, both deleted. A swipe-away and
  "Don't Allow" each go `active → dismissed` directly, never through `.ended`. After the swipe `isEnabled()` stays
  true; after "Don't Allow" it's false by the time the state arrives. `activityStateUpdates` emits the current
  state (`active`) first.
- **Client.** `ended()` waits on the showing activity's `activityStateUpdates` and returns `.ended` (the 8-hour
  limit, still on the Lock Screen) or `.dismissed` (swipe-away, "Don't Allow"). It logs each state at info level
  for #316's device check.
- **Reducer.** `.started(true)` starts the wait (`cancelInFlight`, one at a time). `.ended` → `.notShowing`,
  so the existing foreground retry requests again. `.dismissed` → new `Phase.dismissed`, which `start` and the
  tick both skip.
- **Changed from the plan.** On Finish, `ifLet` cancels the wait (`finishCancelsTheWait` proves it), so there's no
  explicit cancel there. S12's off does cancel it, as planned (restored in code review): `cancelInFlight` cancels
  only once the new wait's task runs, which leaves a gap for the old wait's dismissal to land on `.showing`.
- **Code review, asked.** "Don't Allow" no longer makes `.dismissed` permanent. A dismissal with `isEnabled()` false
  goes to `.notShowing`, so turning Live Activities back on in iOS Settings mid-ride brings the card back on the next
  foreground (`dontAllowThenReenabledComesBack`). A swipe-away (still enabled) stays `.dismissed`.
- **Tests.** 6 new `LiveActivityFeatureTests` and 2 new `LiveActivityClientTests` (real ActivityKit: `.default` end →
  `.ended`, `.immediate` → `.dismissed`). Mutation check: each of these turns a test red when removed: the phase guard,
  the dismissed mapping, the `isEnabled()` condition, and (in code review) the cancel on S12 off.
- **Full suite.** `CyclometerTests` without `MapWidgetAccessibilityTests` and `PersistenceClientTests`: 1804 passed,
  1 failed. The failure, `LocationOneShotTests/oneShotDoesNotDisturbAnActiveStream`, is a timing race outside this
  diff (4.6 s under load; 3/3 green alone at 0.3 s). `PersistenceClientTests` alone: 47 passed.
  `MapWidgetAccessibilityTests` hung twice in `Host.settle()` on a live MapKit view, as CI's skip comment says.
  It was skipped, not run.
- **Not verified.** The full reducer on a real ride in the simulator (only the client was driven); the 8-hour end
  itself; device behaviour (#316).

---

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
- Review follow-up: zone time is now kept per whole rpm (`secondsByRPM`, `Ride.cadenceSecondsByRPMData`) and sorted into the current zones when read, as HR does. A zone change mid-ride re-sorts the whole ride's time. The old behaviour left time recorded before the change in the old zones. Zone time also now uses the rounded rpm that W5 displays.
- Not fixed (user's call): a ride resumed across the upgrade loses its zone time but keeps its coasting time, so Pedaling vs Coasting is skewed for that one ride.

---

# #411 — Serialise LiveActivityClient's start / update / end

Plan: /Users/brian/.claude/plans/enumerated-conjuring-leaf.md
Branch: `fix/411-live-activity-serialise`

- [x] 0. Spike: does `activities` list a requested activity at once; do client closures run nonsending
- [x] 1. Real-ActivityKit test `endDuringAStartLeavesNothingShowing`; confirm it fails unserialised
- [x] 2. Serial queue in `LiveActivityClient.liveValue` (start/update/end); doc comments
- [x] 3. Reducer: drop the extra `end` in `.started`; update `settingOffWhileStartingSendsNothingMore`
- [x] 4. Flake check (10× each way), LiveActivity suites, full suite
- [x] 5. Review section, PR

## Review

- **Cause.** `start` waits on ActivityKit (about 4 ms per `activity.end` in the sim) while it sweeps older ride activities, and only then requests. An `end` arriving in that window snapshots `Activity.activities` before the request lands, so it never sees the new card.
- **Fix.** `LiveActivityClient.liveValue` runs `start`, `update` and `end` through `SerialCalls`: a `Mutex`-held tail of tasks, each waiting for the one before (the `RideDataBuffer.flush` idiom). An actor alone wouldn't serialise these calls, because it's reentrant across ActivityKit's awaits. `ended` stays out of the queue, since it waits as long as the card shows. Each call runs in its own task, so a cancelled caller can't drop an `end`.
- **Spike findings.** `Activity.activities` lists a requested activity as soon as `request` returns, so the queue doesn't need to hold the `Activity`. The client's closures run on the caller's actor up to their first await (approachable concurrency, nonsending), so the queue order is the call order.
- **Reducer.** The extra `end` in `.started` for a start that was pending when the S12 toggle went off is gone. The client's ordering covers that case now. `settingOffWhileStartingSendsNothingMore` now expects one `end`. The finish path is unchanged.
- **Tests.**
  - New `LiveActivityClientTests.endDuringAStartLeavesNothingShowing`, against real ActivityKit: **failed 10/10** on the old client, each time on "nothing left showing", and **passed 10/10** with the queue.
  - Full `CyclometerTests` minus the two known local hangs: 1,821 unique cases, all passing. `PersistenceClientTests` and `MapWidgetAccessibilityTests` run alone: 50 cases, all passing.

---

# #440 — Convert store bindings to `.sending`; toggle actions take a Bool

Plan: /Users/brian/.claude/plans/jiggly-hatching-glacier.md
Branch: `refactor/440-sending-bindings`

- [x] 1. Reducers: Settings toggles + turn-by-turn → `…Changed(Bool)`; guard `liveActivityChanged`
- [x] 2. Views: SettingsView, StartSheetView, RideDashboardView → `.sending`
- [x] 3. Tests: idempotence in Settings/StartSheet; Live Activity on/off through AppFeature
- [x] 4. Greps, targeted suites, snapshots
- [x] 5. Full suite
- [x] 6. Review section, PR

## Review

- **Bindings.** Eleven `Binding(get:set:)` sites became `$store.x.sending(\.action)`: nine in `SettingsView`, one in `StartSheetView`, one in `RideDashboardView`. Five remain, all of them sites the issue excludes: `AppView.dashboardStore`, three `RoutesView` range-slider bindings, and `RoutesView`'s camera.
- **Actions.** `autoPause`, `autoDim`, `placeNameLookup` and `liveActivity` (SettingsFeature), plus `turnByTurn` (StartSheetFeature), are now `…Changed(Bool)` and set the value rather than toggling it. `Delegate.liveActivityToggled` keeps its name.
- **Guard.** `liveActivityChanged` returns early when the value is unchanged, so the delegate only fires on a real toggle. A repeat wouldn't have broken anything, because `LiveActivityFeature.start` and the off path are already idempotent. The guard is there so the delegate's name stays true.
- **Tests.**
  - Each toggle test sends the same value twice; the second send asserts no state change.
  - The Live Activity Settings test also asserts that no delegate fires.
  - `settingsToggleReachesTheRide` now turns the setting off and back on through `AppFeature`, and checks the ride's activity ends and then starts again.
  - **Mutation:** removing the guard fails `liveActivityTogglePersists`.
- **Verification.**
  - The targeted suites pass: Settings, StartSheet and LiveActivity feature tests, plus Settings and StartSheet snapshots. No reference images changed.
  - Full `CyclometerTests` minus `PersistenceClientTests`: 1,823 unique cases, all passing. `PersistenceClientTests` alone: 47 cases, all passing. The first full run hung on the known Persistence × MapKit deadlock (a sample confirmed it), so it was split.
  - No test renders `RideDashboardView`'s body, so the plan's dashboard snapshot check had no suite to run. Its `TabView` binding is covered only by compilation and the `dashboardPageChanged` reducer tests. A swipe on the simulator would confirm it.
- **#439** is still open, so the text bindings were converted in place. Whichever of the two lands second rebases `SettingsView`.

---

# #445 — Live Activity: a start's answer or end-wait can attach to the wrong activity

Branch: `fix/445-live-activity-wrong-activity`

- [x] 0. Spike (iOS 27 sim): how far `activityState` lags `await activity.end(...)`; do cases 2 and 3 reproduce
- [x] 1. Case 1 test (`LiveActivityFeatureTests`): off → on while start #1 is out; start #1's answer must not be taken. Confirm red
- [x] 2. Case 1 fix: off cancels the in-flight start effect (`CancelID.start`), so its `.started` is dropped by `Send`
- [x] 3. Cases 2 + 3: real-ActivityKit tests in `LiveActivityClientTests` (other-units replace → `ended()` waits on the new one; `end` then `start` → one showing, not adopted)
- [x] 4. Doc comments: `LiveActivityClient` (`ended`, `liveValue`) and `LiveActivityFeature` (`.started`, off) agree
- [x] 5. Delete the spike; LiveActivity suites, full suite; review section; PR

## Spike findings

- `await activity.end(nil, dismissalPolicy: .immediate)` takes 3–5 ms, and `activityState` already reads `.dismissed` when it returns: 8/8 runs, zero lag. The activity is also gone from `Activity.activities` by then.
- Case 2 (other units): right after `start` returns, the only `.active` activity is the new one, 5/5.
- Case 3 (`end` then `start`, same units): never adopted the dismissed one, 5/5.
- So with #411's queue, cases 2 and 3 don't happen on the simulator. The "3 s late" in memory is `activityStateUpdates` delivery, not `activityState`.

## Review

- **Case 1 (fixed).** S12's "off" now cancels the pending start's effect alongside the end-wait (`.cancel(id: CancelID.start)`). TCA's `Send` drops actions from a cancelled effect, so the first request's `.started` never arrives to be taken as the second's. The client still finishes the request, and the queued `end` still ends it (#411). The `phase == .starting` guard in `.started` is gone, because nothing else can leave a stale answer.
- **Cases 2 and 3 (pinned, no client change).** By decision: the sim shows no lag, so the "holds no `Activity`" design stays. Two new real-ActivityKit tests pin the assumption. `updateAll` is left as is (optional item skipped).
- **Tests.**
  - `settingOffAndOnWhileStartingTakesTheSecondAnswer`: the two starts answer `true` then `false`, so the final phase shows whose answer was taken. It **failed** on the old reducer (phase `.showing`) and **passes** with the fix.
  - `settingOffWhileStartingSendsNothingMore` no longer receives `.started`; it waits for the request to be recorded instead.
  - `endedAfterAReplacementWaitsOnTheNewActivity` and `startRightAfterEndShowsANewActivity` pass on the real client. Mutation check: with every client `end` delayed 100 ms (a simulated lag), both **fail** on the issue's symptoms: `ended()` returns the old card's `.dismissed`, and `start` re-adopts the ended activity.
  - Full `CyclometerTests` minus the two known local hangs: 1,823 unique cases passing (plus the deliberate `withKnownIssue`). `PersistenceClientTests` and `MapWidgetAccessibilityTests` run alone: `TEST SUCCEEDED`.

---

# #314 — Live Activity: unit tests

Branch: `test/314-live-activity-unit-tests`

Audit of #314's checklist against the suites #306–#313, #411, #412 and #445 shipped; test-only gap fills.

- [x] 1. Sustained throttle test: 4 Hz readings for 10 s → one update per tick, none between
- [x] 2. `pauseShowsAndStaysAlive`: assert no `.end` and `phase == .showing`
- [x] 3. Mutation checks: update on speed reading fails (1); end on pause fails (2)
- [x] 4. LiveActivity suites green; review section; PR

## Review

- **Already covered on `main`:** start / disabled / S12 off (`startShowsTheRide`, `disabledShowsNothing`, `settingOffShowsNothing`); ride end (`finishEndsTheActivity`, `finishCancelsTheWait`; `AppFeature.swift:267` is the only place `activeRide` is set to nil); `routeProgress` nil with no route (`startShowsTheRide`'s full `Content` equality); 4 KB (`RideActivityAttributesTests.worstCaseFitsTheLimit`); `#Preview(as: .content)` per state in `RideLiveActivity.swift`, with stale / Always-On in `RideLockScreenView.swift` previews and snapshots.
- **"`update` never alerts": no test, by decision.** `LiveActivityClient.update` takes no alert parameter and `AlertConfiguration` appears nowhere in the repo. A test could only grep the source, so it could never fail for a real reason.
- **Added:** `sustainedReadingsStayAtOneHertz` (4 Hz GPS for 10 s → exactly one update per tick, none between); `pauseShowsAndStaysAlive` now asserts no `.end` and `phase == .showing`.
- **Mutation checks:** an `update` on every `.gpsSpeedReceived` fails the new test (and `readingsCoalesceToTheTick`); an `end()` on `.pauseTapped` fails `pauseShowsAndStaysAlive` on the new assertion ("a pause doesn't end the activity", read from the xcresult). Both reverted.
- **Tests:** `LiveActivityFeatureTests` + `RideActivityAttributesTests`, with a fresh build in its own derivedData: 27 cases passed, both new/changed tests in the list.

---

# #391 — Warn the rider when a BLE sensor is unreliable

Branch: `feat/391-sensor-health`

Plan: verdict per physical device at ride end (lowest battery reading of the ride; worst 5-min window of CBError 6 drops), saved on `PairedSensor.lastRideHealth`; shown as a full-width footer on the Start sheet row and a "Sensors" section on S10 when flagged.

- [x] 1. `SensorHealth.swift`: log, report, thresholds (tests first: AC1, AC2)
- [x] 2. `BLEClient.linkTimeouts` + `isSupervisionTimeout` (tested)
- [x] 3. `PairedSensor.lastRideHealth` (old JSON still decodes)
- [x] 4. `SensorHealthFeature` child of ActiveRide; started with the ride
- [x] 5. Ride end writes reports to paired records
- [x] 6. Start sheet footer warning + snapshots (AC3)
- [x] 7. S10 Sensors section + snapshot (AC4)
- [x] 8. UX.md / BLE.md updates
- [x] 9. Full suite green; review section; PR

## Review

- **Pipeline.** `BLEClient.linkTimeouts()` filters the existing `events()` for `CBError.connectionTimeout`. It is an extension, not a new endpoint, so none of the 8 hand-built test clients changed. `SensorHealthFeature` (child of `ActiveRideFeature`, started on `.task`) records each paired device's lowest battery reading and worst 5-min window of drops. At `confirmFinish` the reducer writes the verdict onto every `PairedSensor` record of that device, synchronously, because `activeRide` is nil before any effect runs. A device that reported nothing keeps its previous verdict.
- **Surfaces.** The Start sheet row gets a full-width footer: "LOW BATTERY ON LAST RIDE" or "UNRELIABLE CONNECTION ON LAST RIDE — CHECK BATTERY OR MOUNT". S10 gets a "Sensors" section only when the ride flagged a device; a combo CSC device is listed once ("Speed & Cadence").
- **Deviations from the plan.**
  - Warnings are drawn in `cyRatingBad`, not `cyRatingOkay`: amber caption text is 2.5:1 on white, under AA. Red is 5.0:1 in light and 4.9:1 in dark, and matches `SensorBatteryLabel`'s low tint.
  - S10 rows drop the "· N%". One shared `SensorWarningLabel` serves both screens.
  - The S10 snapshot uses its own 1,900 pt canvas. At 1,500 pt the floating button covered the section, and the other references must not move.
  - `RideSummaryView.swift` had no previews; it now has two (rule).
- **Battery window.** The window is the whole ride, since there is no mid-ride alert. The link window is 5 min. Both are documented in BLE.md §14.5.
- **Tests.**
  - The full `CyclometerTests` suite, minus the two known local hangs: 1,849 unique cases passing, with every new test confirmed in the log. `PersistenceClientTests` and `MapWidgetAccessibilityTests` run alone: `TEST SUCCEEDED`.
  - The existing Start sheet and S10 references are unchanged.
  - The new references were checked by eye and are not blank.


### Code review follow-up

- **Applied by the review:**
  - `SensorWarningLabel.message` is a `LocalizedStringResource` made of whole sentences (#430).
  - `linkTimeouts()` is a `compactMap` over `events()`.
  - The S10 icon comes from `SensorRowStyle.device`.
  - `assets/TCA.md` §8 lists `SensorHealth/`.
- **Fixed (findings 5, 10 and 7):** the verdict is now `AppPreferences.sensorHealth: [UUID: SensorHealthReport]`, keyed by device, and `PairedSensor.lastRideHealth` is gone. S11's `apply()` rebuilds the role records and so used to drop it. It is decoded with `try?`, so a verdict that can't be read never resets the other preferences.
- **Fixed (finding 1):** a sensor reaching `.active` (HR: `pairingStatus` true) now counts as showing up for the ride. A sensor without the Battery Service is cleared by a clean ride.
- **Fixed (finding 3):** link losses count only while the ride records. `SensorHealthFeature.State.isRecording` is forwarded the way `CadenceFeature`'s is.
- **Left, by decision:**
  - Finding 2: a sagging cell that connects at 95%, drops once and never reconnects scores healthy.
  - Finding 4: the S10 Sensors section sits inside the loaded block.
- **Tests:**
  - New cases cover the paused link loss, the presence signal, a recording state forwarded through ActiveRide, legacy and corrupt `sensorHealth` decoding, and connected-only being healthy.
  - Three exhaustive ActiveRide resume tests now also expect `sensorHealth.isRecording = true`.
  - Full `CyclometerTests` minus the two known hangs: 1,851 unique cases. The only failures were those three; after the fix their suites (`ActiveRideFeatureStateMachineTests`, `ActiveRideFeatureTimerTests`) pass.
  - `PersistenceClientTests` and `MapWidgetAccessibilityTests` run alone: `TEST SUCCEEDED`.
  - Snapshot references are unchanged.

---

# #392 — Crash-resumed auto-paused ride never restarts the track recorder

- [x] 1. Failing TestStore test: a ride resumed auto-paused moves, and its tick reaches `RideDataBuffer`
- [x] 2. Auto-resume sends `.trackRecorder(.resumeRecording)` when the recorder isn't recording
- [x] 3. Full suite green; review section; PR

## Review

- **Cause, as the issue said.** `.task` leaves the recorder off for a ride that comes back `.paused` (#175), and the auto-resume in the `.speed` case set `.active` without turning it on. `TrackPointRecorderFeature`'s `isRecording` guard then dropped every `.timerTick`.
- **Fix.** The auto-resume sends `.resumeRecording` (the same action a manual Resume sends), but only when the recorder isn't already running. A live auto-pause never stops the recorder, so the live path sends nothing new.
- **Test.** `resumedAutoPausedRideRecordsAfterAutoResume` (`ActiveRideFeatureStateMachineTests`) drains the buffer after one tick. Before the fix it failed with `isRecording == false` and `recorded.count == 0`.
- **Suite.** Full `CyclometerTests`, including `PersistenceClientTests` and `MapWidgetAccessibilityTests` (no hang this time): `TEST SUCCEEDED`, 1,904 unique cases. The new test and the live auto-resume tests (`movingAgainAutoResumes`, `autoResumeOpensANewSegment`, `motionResumesAnAutoPausedRide`) are in the log and pass.
