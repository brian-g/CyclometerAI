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

### Follow-up plan: one pause path, one resume path (review findings 1–2, prepares #267)

The auto-resume does three of the five things a resume does (state, `isAutoPaused`, `zeroSpeedSeconds`, segment) and skips the other two (recorder, checkpoint). #392 was the recorder half, review finding 2 is the checkpoint half, and #267 would add a third caller that needs all five. So the auto-resume and `.resumeTapped` should share one helper, and auto-pause and `.pauseTapped` likewise.

- [x] 1. `private func resume(_ state: inout State) -> Effect<Action>`: `.active`, clears `isAutoPaused`/`zeroSpeedSeconds`, `beginTrackSegment`, checkpoint, `.resumeRecording`. `.resumeTapped` and the `.speed` auto-resume both call it. It's a helper, not `.send(.resumeTapped)`, so the resuming reading still counts toward max speed in the same reduce.
- [x] 2. `private func pause(_ state: inout State) -> Effect<Action>`: `.paused`, checkpoint, `.pauseRecording`. `.pauseTapped` calls it; `.autoPauseTriggered` sets `isAutoPaused` and then calls it. This restores the `.task` invariant `trackRecorder.isRecording == (recordingState == .active)`, and the `if !isRecording` from the first fix goes away.
- [x] 3. Tests: the three exhaustive auto-pause tests now also receive `.pauseRecording`. The new #392 test also checks the segment index (finding 3), and a new test covers the auto-resume checkpoint (finding 2).
- [x] 4. Full suite; update the PR.

Out of scope: #267 itself (the preference, Settings row, and its open questions). After this change, #267 only has to widen the guard on the `.speed` auto-resume.

#### Review

- **Done as planned, plus auto-end.** `.autoEndTriggered` now goes through `pause` too. A rider who cancels its Finish alert used to be left paused with the recorder running, and a kill while the alert was up resumed as stale `.active`. That makes `pause` truly the only pause path, so the `.task` invariant holds everywhere.
- **No test plumbing change.** `PersistenceClient.testValue.updateRideSummary` does nothing rather than failing, so the auto-resume tests that use it needed no change, despite the review's concern.
- **Tests.** Four exhaustive tests now also receive `.pauseRecording`: `autoPauseTriggersAtThreshold`, `autoPauseTriggeredPersistsImmediately`, `autoPausePreemptsAutoEnd` and the auto-end trigger test. New: `autoResumeCheckpoints` (finding 2). The #392 test also checks `segmentIndex == summary.trackSegmentIndex + 1` (finding 3). The six pause/resume suites pass: 74 tests. Full `CyclometerTests`: `TEST SUCCEEDED`, 1,907 unique cases.

---

# #390 — Stale BLE speed when the wheel sensor flaps; a stale zero auto-pauses a moving ride

Plan (spec: PRD §8.4 "never left staring at a stale value"; issue scope is authoritative):

- [x] 1. `SpeedFeature.staleDataWindow = .seconds(4)` replaces `fallbackDelay`. Doc comment: sensors notify ~1 Hz and `CSCCalculator` stays silent for at most `zeroThreshold` (3) frames on a healthy sensor (2 duplicates → nil, 3rd → 0; the re-prime after a stop is 1 nil), so 4 s is one interval of slack over the longest legitimate gap.
- [x] 2. `.bleSpeedReceived` (re)arms the watchdog (`cancelInFlight: true`) → `.bleFallbackTimedOut` → existing `fallBackToGPS` (guarded on `.bleWheel`, unchanged).
- [x] 3. `.reconnecting` / `.active` only record `connectionState`. `.disconnected` cancels the watchdog and falls back immediately (unchanged).
- [x] 4. Banner bound: `lastFallbackBannerAt: Date?`; `fallBackToGPS` switches the source every time but shows the banner only if none was shown in the last `fallbackBannerCooldown` (5 min, wall clock via `date.now`, as `expireHeldHR` does).
- [x] 5. Tests (SpeedFeatureTests): frames stop while `.active` → GPS + banner; stop with a healthy sensor (nil, nil, 0 at 1 Hz) → no fallback; first frame after fallback promotes; repeated flap cycles → one banner per cooldown, banner again after it. Rework the connection-timer tests to the watchdog.
- [x] 6. Test (ActiveRide auto-pause suite): 2026-10-07 replay → GPS before zero-tick 10, no `autoPauseTriggered`.
- [x] 7. Full suite; review section.
- [ ] 8. Commit + PR (awaiting go-ahead).

## Review

- **Cause.** The fallback timer ran off connection state: each `.reconnecting` restarted the 5 s timer and each `.active` cancelled it, so a link flapping every 1–5 s never let it fire. The last reading (including a `0.00`) held on screen, and auto-pause, distance and Avg/Max all read it.
- **Fix.** Every `.bleSpeedReceived` re-arms a 4 s `staleDataWindow` watchdog, cancelling the old timer explicitly (`cancelInFlight` cancels late, #412). On expiry the existing `fallBackToGPS` runs. `.reconnecting`/`.active` no longer touch the timer. `.disconnected` still falls back at once and now also disarms the watchdog. Promotion back is still the first real reading.
- **Banner.** `fallbackBannerCooldown` = 5 min of wall clock (`lastFallbackBannerAt`). The source switches on every fallback; the banner shows at most once per 5 min. Brian chose this over 1 min and a stability re-arm.
- **Tests.** SpeedFeature: silent sensor on a live link, each reading restarts the window, a flapping link doesn't drive the timer, a healthy stop (2.0, –, –, 0…, –, 1.5) stays on the sensor, round trip re-arms, banner cooldown, and a disconnect disarms the watchdog. ActiveRide: a 2026-10-07 replay switches to GPS at zero-tick 7 and never auto-pauses. Four connection-timer tests were replaced. The two shared-peripheral tests also assert `lastFallbackBannerAt`.
- **Mutants.** Restoring the `.active` cancel fails the flapping-link and replay tests. A 3 s window fails the healthy-stop test. A zero cooldown fails the cooldown test.
- **Suite.** `CyclometerTests` without `PersistenceClientTests`/`MapWidgetAccessibilityTests`: `TEST SUCCEEDED`, 1,857 unique cases. Those two suites alone: `TEST SUCCEEDED`, 49. Every new test is in the log and passes.
- **Not done.** A sensor that stops notifying while stationary (rather than repeating its counter) would fall back at every stop. The 2026-10-07 sensor repeats, so this isn't handled. BLE.md §6.2 still says "banner shown" without the cooldown.

---

# #390 follow-up — Speed stale-data window is 5 s, not 4

#455 merged with a 4 s window. The #456 code review showed the calculator's longest silence on an unbroken link is 4 s, not 3: a single wheel turn at a stop re-primes and resets the duplicate count, so 0, –, –, –, 0. A 4 s window expires as that 0 arrives, so creeping at a light could flip speed to GPS and show the banner.

- [x] 1. `SpeedFeature.staleDataWindow` = 5 s; doc comment gives the re-prime + two-duplicate case.
- [x] 2. `healthySensorStopDoesNotFallBack` includes one wheel turn mid-stop. It fails at 4 s and passes at 5 s.
- [x] 3. BLE.md §6.2 "Why 5 s" and the test-matrix row.
- [x] 4. The 2026-10-07 replay still reaches GPS before auto-pause (zero-tick 8 of 10).
- [x] 5. Full suite; PR.
# #456 — Cadence holds a stale reading when the sensor link flaps

Plan (issue scope as approved; mirrors #390 / PR #455):

- [x] 1. `CadenceFeature.staleDataWindow = .seconds(4)` replaces `reconnectGraceDelay`; doc comment justifies it from the crank calculator's 3-frame silence. `CancelID.staleDataTimer`, `.staleDataTimedOut` replace the reconnect names.
- [x] 2. Every valid `.cadenceReceived` cancels and re-arms the watchdog; expiry clears `cadenceRPM`. A negative reading already clears and arms nothing.
- [x] 3. `.reconnecting` / `.active` only record `connectionState`; `.disconnected` clears at once and disarms.
- [x] 4. Tests: silent sensor on `.active` clears; flapping link with no readings clears; coasting (nil, nil, 0, 0…) doesn't; first reading after a clear shows; disconnect disarms. Replace the four grace-window tests; drain the watchdog in exhaustive tests; give clock-less stores a `TestClock`.
- [x] 5. BLE.md §6.2; full suite; review; PR.

## Review

- **Cause, as the issue said.** `.reconnecting` restarted the 10 s grace timer and `.active` cancelled it, so a flapping link never let it fire. The last cadence reading stayed on screen and in every track point (`ActiveRideFeature.swift:1350`).
- **Fix.** Every valid `.cadenceReceived` re-arms a 4 s `staleDataWindow` watchdog, cancelling the old one explicitly, and on expiry cadence clears to "--". `.reconnecting`/`.active` only record the state. `.disconnected` clears at once and disarms. `reconnectGraceDelay`, `CancelID.reconnectTimer` and `.cadenceReconnectTimedOut` became `staleDataWindow`, `.staleDataTimer` and `.staleDataTimedOut`, because "reconnect" no longer describes them.
- **Tests.** New: a silent sensor on a live link clears, each reading restarts the window, a flapping link doesn't drive it, coasting (85, –, –, 0…, –, 80) doesn't clear, the first reading after a clear shows and re-arms, and a disconnect disarms. The four grace-window tests were replaced. Exhaustive tests that send a reading drain the watchdog through `expireStaleData`. `makeTimedStore` and one ActiveRide crash-resume test now get a `TestClock`.
- **Mutants.** Restoring the `.active` cancel fails the flapping-link test. A 3 s window fails the coasting test.
- **Suite.** `CyclometerTests` without `PersistenceClientTests`/`MapWidgetAccessibilityTests`: `TEST SUCCEEDED`, 1,858 unique cases. Those two alone: `TEST SUCCEEDED`, 49. Every new test is in the log and passes.
- **Not done.** A cadence sensor that stops notifying while coasting (rather than repeating its counter) would now show "--" instead of 0 when coasting. That's better than the old held pedalling rpm, but the 0 is lost. The window duplicates speed's 4 s (#455); once both are merged they could share one constant on `BLECSCClient`.
- **Merging with #455.** The code and BLE.md merge cleanly with `390-speed-stale-watchdog` (dry run). `tasks/todo.md` will conflict because both append at the end; keep both sections.
- **Code review: window raised to 5 s.** 4 s equalled the calculator's real longest silence on an unbroken link, not outlasted it: the first stroke after a stop re-primes and resets the duplicate count, so one crank turn mid-coast is re-prime + two duplicates before the next 0 (0, –, –, –, 0 = 4 s). The coasting test now includes that sequence; it fails at 4 s and passes at 5 s. Speed's 4 s (#455) has the same gap.

---

## #389 — Cadence and Directions detail sheets can go stale while open (W5, W9)

Fix once in `WidgetDetailModifier`: present a wrapper whose own `body` calls the detail builder, so whatever the
builder reads invalidates the open sheet directly (#144's fix, for every widget).

- [x] `WidgetDetail.swift`: `WidgetDetailContent` wrapper; `.sheet` presents it; doc comment
- [x] `cadenceSheetFollowsTheRideWhileOpen` (card unchanged, Pedaling vs Coasting follows)
- [x] `directionsMapSheetFollowsTheRideWhileOpen` (card unchanged, orientation button follows)
- [x] Frozen-value control fails each new test
- [x] Revert loop: builder in `.sheet` again, 20 fresh invocations
- [x] Fixed loop: 20/20 fresh invocations pass
- [x] Full `CyclometerTests`
- [x] Memory `sheet-builder-reads-go-stale` updated

### Review

- **Fix.** `WidgetDetailModifier` presents a private `WidgetDetailContent` whose `body` calls the widget's builder,
  so whatever the builder reads invalidates the open sheet itself. That covers W5 and W9, and any future
  `.widgetDetail` whose builder reads store state, with no widget changes. W8 gains nothing from it, and needs
  nothing: everything its sheet shows is a `MapWidget` input, so a change redraws the card as well as re-running
  the builder. That redraw is the path that masked the bug in #144; it only went stale with the card unchanged.
  The `metrics:` closures on the RideMetrics/HR/Elevation sheets are now redundant; left as they are.
- **Tests.** `cadenceSheetFollowsTheRideWhileOpen` (Pedaling vs Coasting "—" → "50% / 50%") and
  `directionsMapSheetFollowsTheRideWhileOpen` (orientation button "Heading up" → "North up"). In both, the card
  never changes. The frozen-value control fails both at the follow step.
- **Fresh-invocation loops** (own DerivedData, no compile cache, 3 cases counted in every run):
  - Reverted (`.sheet(isPresented:content: detail)`): Cadence failed 2/60. In both, the open sheet read only
    Avg/Max Cadence for the full 6 s, never getting past its first partial build. Directions: 0/60.
  - Fixed: 0/100 for all three sheet tests.
- **What that does and doesn't show.** The revert rate here is ~1 in 30, well below #144's ~1 in 7, and two
  failures is thin evidence: by chance alone, both would land in the revert runs ~14% of the time. The fix rests
  mostly on being the same mechanism #388 proved for RideMetrics. The Directions test never reproduced the bug.
  It pins the behaviour (the frozen control fails it) but isn't evidence the bug existed there. The live map
  likely keeps the sheet's host updating on its own. [Likely]
- **Suite.** `CyclometerTests` without `PersistenceClientTests`/`MapWidgetAccessibilityTests`: `TEST EXECUTE
  SUCCEEDED`, 1,864 unique cases, 0 failed. Those two alone: 49, 0 failed.

---

## Dashboard watermarks on a shared time axis

Plan: `~/.claude/plans/precious-stargazing-wren.md`. Branch `fix/watermark-time-axis`. From the 2026-10-24 ride
(IMG_5589): W1 drew the 11:29–11:45 stop, W5 didn't — the watermarks plot by sample index, and cadence had no
samples while its sensor slept (speed had GPS fallback).

- [x] `Watermark` helper: shared window + time buckets, runs broken at silences > 2 min
- [x] `ActiveRideFeature.State`: `watermarkWindow` + four `…Watermark` series; remove the index-bucket versions
- [x] W1 / W5 / W4 / W17–W18 charts plot against time over the window; previews incl. "Sensor gap"
- [x] Build (app target `BUILD SUCCEEDED`); hand to Brian to run on device
- [x] Tests: `WatermarkTests` (12, incl. this ride's regression); HR watermark test rewritten; the speed/cadence
      count tests removed (properties gone, covered by `WatermarkTests`); snapshot call sites on `asWatermark`
- [x] Snapshots: existing references unchanged (evenly spaced data draws the same against time); new
      `testCadenceTwoByOneSensorGap` records the break
- [x] Review follow-ups: lone points (a run of one) draw as a `Spacing.watermarkDot` dot, per Brian — Watch HR
      via HealthKit lands minutes apart and drew no trace at all; W18 reads the window only without a route
      profile (`aNewSampleDoesNotRerenderRouteElevationOnARoute` caught the redraw); new
      `testHeartRateWidgetSparseWatchReadings`
- [x] Full suite on the final tree: `CyclometerTests` without `PersistenceClientTests`/`MapWidgetAccessibilityTests`
      `TEST EXECUTE SUCCEEDED`, 1,879 unique cases, 0 failed; those two alone `TEST EXECUTE SUCCEEDED`, 0 failed
## #406 — A resumed ride forgets it finished its route

Persist `navigation.isRouteComplete` with the ride's route progress and restore it on resume (#197's path).

- [x] `Ride.isRouteComplete` (declaration default), `RideSummaryUpdate`, `summarySnapshot`, `apply`
- [x] Checkpoint writes it; `State(resuming:)` restores it
- [x] Extend the #197 persistence, checkpoint, resume and migration tests
- [x] Pipeline: a ride killed after finishing relaunches finished, and riding past the end isn't off route
- [x] Pipeline: a ride killed mid-route still completes after the relaunch
- [x] Revert check: the new pipeline test fails without the restore
- [x] Full `CyclometerTests`

### Review

- **Fix.** `isRouteComplete` takes `routeProgressMeters`'s path: `Ride` (declaration default `false`, so older rows
  migrate as unfinished), `RideSummaryUpdate`, `summarySnapshot`, `apply`, the checkpoint, and `State(resuming:)`.
  `routeLoaded` doesn't reset it, so it survives `.task`'s reload. `nextManeuverIndex` comes back 0, but W9, its only
  reader, shows a turn only with a distance, which is nil while complete. So nothing on screen changes.
- **Tests.** The #197 persistence, checkpoint, resume and migration tests now cover the flag.
  `finishedRideRelaunchesFinished` (pipeline: real store, GPX fixture) finishes 10 m short of the end, checkpoints, is
  killed and relaunched, then rides 60 m+ past the end for six fixes. `killedRideRelaunchesStillNavigating` now also
  checks that a ride resumed mid-route starts unfinished and still finishes (AC 3).
- **Revert check** (restore line removed, fresh DerivedData, no compile cache): the new pipeline test failed on
  `isRouteComplete`, `routeProgressFraction == 1` (twice) and `isOffRoute == false`. The issue's off-route claim
  ([Likely; not reproduced]) is now reproduced. The resume unit test failed too; the mid-route test passed.
- **Suite.** `CyclometerTests` without `PersistenceClientTests`/`MapWidgetAccessibilityTests`: `TEST EXECUTE
  SUCCEEDED`, 1,866 unique cases, 0 failed. Those two alone: 49, 0 failed.
- **Not done.** Completion is saved only at the next checkpoint (30 s) or pause, the same as progress. A kill within
  that window after finishing still relaunches unfinished. Writing a checkpoint on completion would close it.

---

## #365 — Finish slides the dashboard down (on `brian/fixSafeAreas`)

Mechanism, measured per frame on the sim (2026-10-25). A zoom dismissal with no source (the accessory goes at
Finish) scales the root `_UIHostingView` to ~0.915. `UIKitTabBarController` computes its insets in that scaled frame
(t24.3 b0) and never again. Keeping the strip up as the zoom target avoids it, but UIKit's zoom completion, and so
`onDismiss`, lands ~0.63 s after the collapse looks done, so the strip lingers. A cover-vertical dismissal scales
nothing. Setting the cover's `preferredTransition = .coverVertical` after it's on screen is honored.

- [x] `DashboardFinishTransition`: from the Finish alert on, the cover's transition is cover-vertical. Cancel restores
      the zoom. Re-applied after the cover opens, for an auto-end alert raised while minimized.
- [x] Strip back to main's rule (gone at Finish); `dismissingRide` removed
- [x] S10 still waits for `onDismiss` (`pendingRideSummary`); comments say why, without the disproved mechanism
- [x] Reducer test updated; app and test target build
- [x] ~~First device run~~: top safe area broken again. SwiftUI re-ran the cover's content closure (it read
      `finishAlert`), re-applied `.navigationTransition(.zoom)` and replaced the slide a frame later
- [x] Fix: the store is read in `DashboardFinishTransition`'s own body, so the closure never re-runs
- [x] Sim drive on the shipped code: Finish slides, nav bar 62 before/after; Finish → Cancel → Resume → minimize
      zooms into the strip, reopen, Finish slides, nav bar 62
- [x] Brian ran it on device (same two flows): "Perfect". Auto-end while minimized not driven
- [x] Tests

### Review

- **Root cause.** #365 is UIKit's zoom dismissal. With no source to zoom into, it scales the root host view, and the
  tab bar controller computes its insets in that scaled frame and never again. Finish removes the accessory, so the
  zoom has nothing to land in. Finish now dismisses cover-vertical, which scales nothing. Zoom open and drag-to-minimize
  are unchanged.
- **Why not the two earlier branches.** fix/365 heals the insets after the fact, so the stale frames show first: the
  jank. The Codex branch kept the accessory as the zoom target until `onDismiss`, but UIKit's zoom completion lands
  ~0.63 s after the collapse looks done, so the strip lingered.
- **Suite.** `CyclometerTests` without `PersistenceClientTests`/`MapWidgetAccessibilityTests`: `TEST EXECUTE
  SUCCEEDED`, 1,864 unique cases, 0 failed. Those two alone: 49, 0 failed.
- **Not covered.** Auto-end while the dashboard is minimized (the alert is up as the cover opens) is handled by
  re-applying after the opening, but no drive or device run has exercised it. No automated test covers the
  transition. The sim drives were throwaway.

---

## #439 — Extract NumericEntryRow and split SettingsView into section views

Plan: `~/.claude/plans/streamed-wishing-sunbeam.md`. No visual, copy or behaviour change. Deviations from the issue's
API sketch (approved): the row takes `text: Binding<String>` rather than `text` + `onChange`, and `errorMessage: Text?`
so the wheel message (`LocalizedStringResource`) and the HR errors (`String`) keep their own line-wrapping (#430).
Cadence Zones (#79, after the issue was filed) gets a section too.

- [x] `NumericEntryRow` in `UI/Components/NumericEntryRow/`: owns its `@FocusState`, commit-on-blur and keyboard Done;
      previews for placeholder, valid, error (light + dark)
- [x] `SettingsView` is a thin `Form` of `GeneralSection`, `HRZonesSection`, `CadenceZonesSection`, `AboutSection`;
      no `@FocusState`
- [x] `NumericEntryRowSnapshotTests`: placeholder, valid, error × light/dark; PNGs opened
- [x] App and test target build
- [x] Brian runs it ("never seen 2 done buttons"): one Done per field; Done and tap-elsewhere commit; out-of-range caption
- [x] `SettingsSnapshotTests` zero diffs (en, and `-testLanguage de`); `SettingsFeatureTests` unchanged; full suite

### Review

- **Settings unchanged.** `SettingsSnapshotTests` 7/7 against the existing 14 references, with nothing rewritten on
  disk, in en and under `-testLanguage de -testRegion DE`. `SettingsFeatureTests` 33/33, unchanged.
- **New row.** `NumericEntryRowSnapshotTests` recorded 6 references, each opened (placeholder, valid, error; light and
  dark), then 3/3 in en and de. Added to CI's snapshot skip list (review), like every other snapshot suite.
- **Done.** Per-row keyboard toolbar gated on the row's own focus; Brian has never seen two Done buttons, so the
  screen-level fallback wasn't needed.
- **Suite.** `CyclometerTests` without `PersistenceClientTests`/`MapWidgetAccessibilityTests`: `TEST SUCCEEDED`,
  1,884 unique cases, 0 failed. Those two alone: 50, 0 failed.
- **Not covered.** Whether removing a focused row still sends a commit wasn't checked; it's a no-op either way (the
  preset has already cleared the draft), and `SettingsFeature`'s comment no longer relies on it.

---

## #267 — Resume When Moving: let motion resume a manually paused ride

Plan: `~/.claude/plans/cached-stirring-widget.md`. Off by default. Decisions (Brian, planning): a manual pause can be
resumed by motion only after the ride has been seen stopped (≤ `stationarySpeedMPS`) since the pause, so a Pause
tapped while coasting holds; the toggle doesn't depend on Auto-pause (OQ1); label "Resume When Moving", with a
caption in the row (OQ2/OQ3).

- [x] `AppPreferences.isResumeWhenMovingEnabled` (default false, `decodeIfPresent`)
- [x] `SettingsFeature` read-through + `resumeWhenMovingChanged`; `SettingsView` row with caption under Auto-pause
- [x] `ActiveRideFeature`: `hasStoppedWhilePaused`, `.speed` guard, cleared in `resume`
- [x] UX.md §S12, DataModel.md §3.6
- [x] App builds
- [ ] Brian runs it on device — not yet; no ride at 9 PM. Walking (≥ 1.0 m/s) exercises the same path
- [x] Tests: auto-pause/resume, track segment, Settings, AppPreferences; snapshots re-recorded and opened (en + de); full suite

### Review

- **Targeted.** 121 unique cases across the auto-pause, auto-pause threshold/replay, track segment, Settings,
  AppPreferences, ride-end and Live Activity suites; 0 failed. Six new cases, all found in the log by name.
- **Mutations.** Dropping the stop check failed `pauseTappedWhileCoastingHolds` and `invalidFixDoesNotCountAsAStop`;
  ignoring the preference failed only `manualPauseHoldsWithoutThePreferenceAfterAStop`. The old
  `motionDoesNotResumeAManuallyPausedRide` passed under that mutation: it never stops first, so it couldn't tell.
- **Beyond the plan.** `invalidFixDoesNotCountAsAStop`: a nil displayed speed (negative GPS speed) doesn't arm.
  Auto-pause does count nil seconds as stopped, but it needs ten in a row. One dropout right after a Pause tapped
  while coasting would otherwise arm the resume.
- **Snapshots.** All 7 `SettingsSnapshotTests` (14 PNGs) moved as expected. Re-recorded with
  `TEST_RUNNER_SNAPSHOT_TESTING_RECORD=failed`. Opened default, full height dark, Live Activities off, custom wheel
  invalid dark and HR invalid light; byte check shows none flat. 7/7 in en and under `-testLanguage de`.
- **Suite.** `CyclometerTests` without `PersistenceClientTests`/`MapWidgetAccessibilityTests`: `TEST SUCCEEDED`,
  1,888 unique cases, 0 failed. Those two alone: 50, 0 failed.
- **Not covered.** Device behaviour. The Simulator may report a fixed location as no speed, which by design never
  arms the resume [Guessing], so walk it on a phone.

---

# #452 — Delete a just-finished ride from S10

Plan: `~/.claude/plans/keen-bouncing-papert.md`. Decided with Brian: a trash button in the nav bar's leading slot, and
one rule for every delete — the ride's Health workout goes with it, from S10 or S14's swipe.

- [x] `HealthKitClient.deleteWorkout`: route, distance and energy samples, then the workout, by sync identifier; share-authorized types only
- [x] `RideHealthWorkout.deleteRide`: under `healthWorkoutGate`; Health first, then `persistenceClient.deleteRide`
- [x] `RidesFeature.deleteRecordedRide` goes through it
- [x] `RideSummaryFeature`: `deleteTapped` (loaded only) → alert → `delegate(.deleteRide)`
- [x] `RideSummaryView`: leading trash toolbar item, `cyDestructive`, disabled until loaded; "loading" preview
- [x] `AppFeature`: delegate → `rideSummary = nil` (no rename) → `rides(.deleteRecordedRide)`
- [x] UX.md §S10 / HKWorkout / §S14
- [x] Tests written: RideHealthWorkout (order, failure, no share, gate), RideSummaryFeature, presentation, RidesFeature
- [x] Brian runs it (sim/device): delete from S10; History swipe; Health shows no workout
- [x] Unit tests

## Review

- **Build.** `build` and `build-for-testing` succeed; no new warnings in the touched files.
- **Brian's run.** Looks good.
- **Suite.** `CyclometerTests` without `PersistenceClientTests`: `TEST SUCCEEDED`, 1,890 unique cases, 0 failed, the
  10 new ones among them. S10's three snapshot references passed unchanged. `PersistenceClientTests` alone: 47, 0 failed.
- **Plan correction.** The plan said toolbar items don't render in iOS 27 snapshots. They do (memory
  `snapshot-toolbar-not-rendered`). S10's snapshots render `RideSummaryList` without a `NavigationStack`, so the new item
  still can't appear there and the references shouldn't move.
- **[Likely], unverified.** `deleteObjects(of:predicate:)` succeeds with a count of 0 when nothing matches, e.g. a ride
  whose workout was skipped as another source's duplicate. The live client logs the count for each type.

### #452 review (`/code-review xhigh --fix`)

- **Fixed by the review, committed as `5d71e6c`.** S14 filters rides that are mid-delete out of every read, because a delete can wait behind a
  backfill. `deleteWorkout` treats `errorNoData` as 0 deleted. The gate comment is corrected, and an always-true check
  was dropped.
- **Fixed after, at Brian's call.** `deleteRide` no longer checks Workouts share before Health. The client already checks
  share access type by type, so distance and energy samples go even with Workouts off.
- **Skipped.**
  - The S10 delete can race that ride's thumbnail capture, which then stops the batch. History deletes already had
    this race, and the fix belongs in `RideMapThumbnail.backfill`.
  - A delete waits for a backfill's whole batch.
  - If the Health delete succeeds and the ride delete then throws, the ride comes back without its workout.
- **Suite.** 1,891 unique cases, 0 failed. `PersistenceClientTests` alone: 47, 0 failed.

---

# #476 — A ride deleted mid-capture stops the map-thumbnail backfill

Found in #452's review. `saveMapThumbnail` throws `rideNotFound` for a ride deleted while it rendered. The batch
`break`s on it, so older rides missing a thumbnail wait until the next launch or Finish.

- [x] `RideMapThumbnail.backfillNow`: a `rideNotFound` capture is logged and skipped, like `RideHealthWorkout.settle`;
  any other error still ends the batch
- [x] Test: `RideMapThumbnailTests.deletedRideDoesNotEndBatch`

## Review

- **Mutation check.** With the new `catch` removed, `deletedRideDoesNotEndBatch` fails. Restored, `RideMapThumbnailTests` passes 15/15.
- **Suite.** On `main` after #452's merge: 1,892 unique cases, 0 failed. `PersistenceClientTests` alone: 47, 0 failed.
  A plain `' passed'` count read 1,890 because two result lines were split by interleaved `IDESchemeActionSDKRecord`
  log lines. Both cases had passed. Join lines before counting.
- **Not covered.** Nothing visible to check on device: the bug only left placeholder rows until next launch.

---

# #203 — On-device route narrative (Apple Intelligence)

Plan approved. S20's Summary section gets a number-free paragraph from `FoundationModels`. It's generated at import
plus a backfill, the same way the OSM surface lookup works, and stored on `Route`. Without Apple Intelligence, S20 is unchanged.

- [x] `RouteTerrain.gradeProfile` extracted; `analyze` uses it
- [x] `RouteNarrative.swift`: input (histogram, climb positions), prompt, instructions, validator
- [x] `RouteNarrativeClient` (live `FoundationModels`; inert test/preview)
- [x] `Route.terrainNarrative`, `RouteSummary.narrative`, `saveRouteNarrative`
- [x] `RoutesFeature.resolveMissingNarratives` + `.narrativeResolved`
- [x] `RouteSummarySection` row
- [x] Docs: UX §S20, PRD §8.6 / §12 / changelog
- [x] Build; hand over to Brian to run
- [x] Tests: `RouteNarrativeTests` (sections, words, answer rules), `RoutesFeatureTests` narrative cases,
  `RoutePersistenceTests` round trip, `RouteSchemaMigrationTests` nil column, `RouteDetailSnapshotTests` reference

## Notes

- **The prompt shape changed after probing the real model.** I ran the on-device model from a macOS script over hilly, flat and punchy inputs.
  - With one gradient histogram for the whole route, it invented positions ("the final third drops gently" on a flat route) and put the hardest climb in the wrong third. The input is now **per third**, put into words in code, and a route that's the same end to end is said once.
  - Asked for a paragraph, it answered in lower case, one clause per line. The output is now `@Generable` sentences (structure only, no terrain enum), tidied and joined by `RouteNarrative.paragraph`.
  - Sampling is the default rather than greedy, because a rejected route is asked again next launch and greedy would repeat the same rejected answer.
- **Thirds became terrain sections (Brian's call, after a probe).** Thirds kept positions right but cut across climbs. A
  length-based count was considered and dropped: a fixed 2–3 sentences can't carry more sections, and the model drops
  facts when a sentence holds two. The route now splits at its climbs and the stretches between them (thirds when there
  are none), merges alike neighbours, and caps at five sections by joining the shortest neighbouring pair with its parts
  in order. The sentence count is exactly the section count, set per request with a `DynamicGenerationSchema`, because a
  static `@Generable` count let the model pad one section into five sentences.
  - End to end, with the real `RouteNarrative.swift` compiled into a macOS probe over synthetic routes (Summit Climb, back-half
    climbs, short sting, flat, climb-then-flat, six climbs, punchy), every climb was in the right place in riding order.
  - Six climbs ran to 457–690 characters, so the cap is 600 (4 of 5 runs passed); the other routes ran 42–410.
  - Folding a climb into a recomputed spread ("mostly flat, including a Cat 4 climb") made the model leave out every climb, which is why
    merged sections keep their parts.
- **Residual risk.** Wording can still drift ("the path twists"). The validator catches figures, not invented adjectives.
- **Verification.** The first full local run hung for 2 h 20 min on the PersistenceClientTests × MapKit deadlock (sampled:
  main in `MapEngine::~MapEngine`, 19 pool threads in `makeLiveClient()`). The rerun with that suite skipped passed:
  2,179 passed, 11 skipped. The suite alone then passed 47/47.

---

# #447 — Paging dots down to the ride controls' bottom edge

Plan: `~/.claude/plans/validated-zooming-sphinx.md`

- [x] `RideDashboardView`: dots and ride controls share one bottom-aligned row; the `cornerMd` offset moves onto the row
- [x] Build; hand over to Brian to run
- [x] Docs: UX §S05 Multiple pages, Structural Zones, Dashboard Paging
- [x] Tests: `CyclometerTests` (no snapshot covers this view)

## Review

- Brian checked it on the sim: the dots sit flush with the buttons' bottom edge.
- The `-cornerMd` bottom padding moved from `rideControls` onto the shared row. Negative padding shrinks the layout
  frame, so leaving it on the buttons would have lined the dots up 12 pt above the visible buttons.
- Open: there's no page cap, so about 9+ dots reach Finish while paused. The buttons draw on top and keep their
  touches. UX §S05 said the dots show "when there are multiple pages", but the code always shows them. Brian:
  code wins. UX now says always visible, one dot per page, even for one page.
- Verification: `CyclometerTests` without PersistenceClientTests passed 2,179, 0 failed. PersistenceClientTests alone
  passed 47/47.

---

# #393 — Heart Rate sheet keeps time in zone across a crash resume

Plan: `~/.claude/plans/functional-zooming-koala.md`

- [x] `HeartRateSecondsTally.add(secondsByBPM:)` — sums a histogram; exact because a Watch hold never crosses a segment
- [x] `ActiveRideFeature`: `seedElevation` → `seedFromSavedTrack` (one fetch); sends `.elevationSeeded` and new `.heartRateSeeded`
- [x] Tests: resume path matches `secondsByBPM(saved + recorded)`; a seed after live seconds adds to them
- [x] Build; hand over to Brian to run
- [x] Tests: `ActiveRideFeatureHRDropoutTests`, `ActiveRideElevationTests`

## Review

- Saved and live tallies are summed rather than replayed together: exact, since a resume always opens a new segment
  and a held Watch reading never crosses one.
- One `fetchTrackPoints` now feeds both resume seeds (`seedFromSavedTrack`), instead of reading the track twice.
- Verification: `ActiveRideFeatureHRDropoutTests` + `ActiveRideElevationTests` passed 23, 0 failed.

---

# #399 — One bucket-average helper for the dashboard series

Plan: `~/.claude/plans/greedy-launching-spring.md`

- [x] `Models/TimedSample.swift`: protocol + `buckets(to:)` + `bucketAveraged(to:)`
- [x] Conform `SpeedSample`, `AltitudeSample`, the three chart `Point`s; delete the old copies
- [x] Move `RideSpeedChart.elevationPoints`, HR/Cadence `downsampled`, `PaceTrace.runs` onto it
- [x] `TimedSampleTests`: partition 1…4000 × {60, 120}; means; prove it bites on the Cadence formula
- [ ] Build; hand over to Brian to run
- [ ] Targeted tests + chart snapshots

## Review

- Six copies, not four: Cadence's chart and `PaceTrace.runs` also sliced by hand. Cadence still had the #140
  floating-point edges and dropped the newest sample at 160 counts in 1…4000 (×{60, 120}); now fixed.
- HR and Cadence keep `downsampled` as a one-line forwarder: two call sites each, same resolution.
- Partition test failed 160× against Cadence's old formula, then passed; `TimedSampleTests` + `SpeedFeatureTests`
  24 passed, 0 failed.
- Not yet run: `RideMetricsTests`, `HeartRateMetricsTests`, `ElevationMetricsTests`, chart snapshots, AddWidgetSheet.
# #397 — Resume seed fetches only the columns it replays

Plan: `~/.claude/plans/greedy-launching-spring.md`

- [x] Measure: 18k points, full fetch vs dictionary fetch (throwaway); go only if ≥ ~1.5× faster
- [ ] `TrackSample` protocol + `TrackSampleDTO`; `TrackPointDTO` conforms
- [ ] `Seed(savedTrack:)`, `secondsByBPM`, `HeartRateSecondsTally.add` generic over `TrackSample`
- [ ] `PersistenceClient.fetchTrackSamples` (live dictionary fetch, test, mock); shared sentinel helper
- [ ] `seedFromSavedTrack` uses `fetchTrackSamples`
- [ ] `PersistenceClientTests` case: samples == full fetch mapped; unknown id empty
- [ ] Build; hand over to Brian to run
- [ ] Targeted tests

## Review

- Stopped at the gate. Simulator, Debug, 18,000 points, median of 7, three runs: full fetch 42.7 / 44.0 / 47.8 ms,
  dictionary fetch of the 6 columns 32.7 / 33.9 / 35.8 ms — **1.29–1.33×**, about 10 ms saved.
- The issue's 3 columns became 6 after #393 (HR seed reads bpm, source and timestamp too), which is most of why the
  gain is small: SQLite still reads every row, and row materialisation, not column count, dominates.
- Recommendation: close #397 as not worth a second track-point read path. Nothing below the gate was built.

---

# #398 — W14–W16 re-render only when their number changes

Plan: `~/.claude/plans/greedy-launching-spring.md`

- [x] Tests first: stopped tick and flat moving tick leave W14–W16 un-invalidated; a climb invalidates W14
- [x] Confirm the new negative cases fail on current code
- [x] `ElevationTracker` → `@ObservableState`; ascent/descent stored, set by `updateTotals()`
- [ ] Build; hand over to Brian to run
- [ ] Targeted tests + AddWidgetSheet snapshot

## Review

- `ElevationTracker` is `@ObservableState`; ascent/descent are stored, set by `updateTotals()` on a recorded or
  seeded change. An in-place mutation keeps the tracker's `_$id`, so `\.elevation` observers aren't notified;
  only changed properties are.
- New tests failed 7 ways on the old code (every card on a stopped and a flat tick, W15 on a climb); 4/4 pass after.
- Not yet run: `ElevationTrackerTests`, `AltitudeReanchorReplayTests`, `ActiveRideElevationTests`, AddWidgetSheet snapshot.

---

# #401 — W1 Speed: VoiceOver reads the trend

Plan: `~/.claude/plans/greedy-launching-spring.md`

- [x] Tests first: above (existing test's strings), below, even / no reading — at 1×1, 2×1, 2×2
- [x] Confirm above/below fail and even/no-reading pass on current code
- [x] `SpeedWidget.accessibilityValue`: "above average" / "below average" after the speed
- [x] UX.md §W1 trend bullet
- [x] W5 Cadence too (Brian): same words, its own trend rule; HR already reads "rising"/"falling"
- [ ] Targeted tests; hand over for a VoiceOver check

## Review

- W1 and W5 read their ▲/▼ as "above average" / "below average" straight after the value, from the same `trend`
  that draws it, so threshold and no-reading cases match by construction. W4 already read "rising"/"falling".
- `widgetIsOneButton` hard-coded W1's old string; its live element already read the new one.
- Above/below cases failed before the change; `WidgetAccessibilityTests` 68 passed, 0 failed after.

---

# #461 — W19 Distance Remaining and W20 ETA

Plan: `~/.claude/plans/lively-herding-pike.md`

- [x] `NavigationFeature.State.remainingDistanceMeters`, by `routeProgressFraction`'s rules
- [x] W19/W20 adapters (`RouteProgressDashboardWidgets.swift`), views with previews, catalog
- [x] ETA: `TimelineView` each second so a stop moves it; 12 h → "3:42" + "pm", 24 h → "15:42"; "—" once complete
- [x] Tests: remaining (no route, TBT off, mid, off-route hold, complete, loop wrap), arrival, clock face, VoiceOver
- [x] Snapshot suites written; UX.md §W19, §W20, §S08
- [x] Build
- [ ] Hand over to Brian to run
- [x] Targeted tests; record + look at W19/W20 references

## Review

- The second lap of a loop is only the wrap case: `isRouteComplete` is terminal, and matching stops once it is set.
  `total − progressMeters` counts the wrapped lap down with no extra logic.
- The first run caught the 24-hour face reading "9:05". `.defaultDigits` drops the leading zero a 24-hour clock keeps,
  so a 24-hour cycle now uses `.twoDigits`.
- `AddWidgetSheetSnapshotTests` leaves the Route section out (live `Map`), so its references don't move.
- 150/150 across NavigationFeature, RouteProgressWidget, WidgetAccessibility, both new snapshot suites and
  AddWidgetSheet. All 11 new PNGs checked by eye: none blank, "pm" on the digits' baseline.

### #486 review follow-up

- [x] W20 reads "—" until 60 moving seconds (`ETADashboardWidget.settlingSeconds`): the first seconds' average gave arrivals hours out
- [x] W20's `TimelineView` ticks only while there is an arrival (`EverySecondSchedule`), one schedule type so the sheet's identity holds
- [x] VoiceOver says why "—": "No route" / "Turn-by-turn off" / "No reading" (`RouteProgressReading`)
- [x] Clock face from the locale's own `jmm` pattern, day period removed: "9:05" US, "09:05" UK, "9.05" Finland — replaces the forced two-digit hour
- [x] Map-sheet duplication filed as #487
- 153/153 targeted. fr_CA's pattern turned out to be "HH:mm", not "HH 'h' mm" as I'd assumed; test dropped
- Not verified: the schedule restarting when an arrival appears while stopped — needs a look on the simulator

### #486 CI fix

- [x] CI red on 387722e: `AddWidgetSheetTests` (two hardcoded Route lists) and `DashboardLayoutTests` (factory must show
      every widget at every size) didn't know W19/W20. `main` green
- [x] Route lists updated; W19 at row 4 right and W20 at row 5 left of the Elevation showcase page (Brian chose)
- [x] Local run blocked: the simulator's launchd spawned nothing until the Mac rebooted — CI verified instead: 1803
      passed on eee5b0b, but the job hit its 30-min timeout twice (build 21 min on a slow runner)
- [x] `timeout-minutes` 30 → 45, comment updated with today's timings (Brian, option 1)

---

# #487 — One map-sheet builder for W8, W9, W19 and W20

Stacked on `feat/461-distance-remaining-eta` (#486 is open, and W19/W20 only exist there).

- [x] Move `Store.liveMapSheet` from `RouteProgressDashboardWidgets.swift` to `MapDashboardWidget.swift`, next to
      `mapSheetRoute`, internal
- [x] `LiveMapSheet.placeholder` in `MapWidgetView.swift`; W9/W19/W20 `detail` defaults use it
- [x] W9's adapter: `detail: { store.liveMapSheet }`
- [x] W8: left as is (Brian, option 1) — `MapWidget` builds its sheet from the values it already draws; #487's AC
      to be reworded
- [x] Build
- [x] `DirectionsDashboardWidgetTests`, `WidgetAccessibilityTests`, `MapWidgetAccessibilityTests`, Directions/
      DistanceRemaining/ETA snapshots: 101/101, every suite non-empty
- [ ] Hand over to Brian to run

## Review

- `LiveMapSheet(` now appears three times: `store.liveMapSheet` (W9, W19, W20), `.placeholder`, and W8's own.
- No reference image moved: the sheet is never drawn by a card, and the placeholder is the same empty sheet.

---

# #462 — W21 Time to Sunset

Brian's answers: h:mm; "—" not "--"; VoiceOver says why it's empty; showcase row 5 right on the Elevation page;
last in S08's Ride 1×1s; no Sketch check.

- [x] `Models/Sunset.swift`: NOAA solar-position sunset (zenith 90.833°, no elevation) for a coordinate and
      a calendar day, rounded to the minute as NOAA publishes it; nil for polar day/night
- [x] `Sunset.countdown(now:coordinate:calendar:)`: the earliest of yesterday's and today's sunset still ahead
      (a high-latitude sunset can fall after midnight), else `.passed`; `.noFix` without a coordinate; `.noSunset`
      at polar day/night
- [x] `ActiveRideFeature.State.sunsetFix`: the latest fix, taken at most once a minute in `.locationUpdated`,
      so W21 re-renders once a minute, not once a fix
- [x] `SunsetDashboardWidget` (id `sunset`, 1×1, `.ride`), `TimelineView(.everyMinute)` — exact because the sunset
      is minute-rounded; tap opens `store.liveMapSheet`
- [x] `SunsetWidget` view + previews (countdown, after sunset, no fix; light/dark)
- [x] Catalog line; `AddWidgetSheetTests` Ride lists; factory showcase placement
- [x] Tests written: NOAA cases (values from NOAA's own calculator JS run in node), both hemispheres, solstices/equinox,
      polar day/night; countdown across midnight and a time-zone change; reducer throttle; accessibility; 6 snapshots
- [x] UX.md §W21, §S08 Ride list, header line
- [x] Build (app + tests)
- [x] Hand over to Brian to run — "looks right"
- [x] Record the 6 snapshots (checked: "1:12", and "—")
- [x] Full `CyclometerTests` less `PersistenceClientTests` (#480): 2251 passed, 2 failed — fixed below; then Sunset,
      Sunset snapshots, S08 catalog snapshot and `PersistenceClientTests` alone: 74/74, every suite non-empty

## Review

- The Reykjavik test was wrong, not the code: at 00:04 on the 22nd the 21st's sunset has set and the 22nd's (00:04 on
  the 23rd) is ahead, so near midsummer it never reads "—". Test and UX.md now say so.
- S08's catalog reference re-recorded: the only change from main is W21 beside Grade. It reads "—" there, as W19 and
  W20 do, because the sample ride has no fix; a sample countdown would tie the reference to the wall clock.
- No other exhaustive store needed `sunsetFix`: the six that assert `coordinate` were the lot.
- NOAA values come from NOAA's own `main.js` (`calcSunriseSetUTC`, two passes, minute-rounded), run in node.


### #490 review (`/code-review xhigh --fix`)

- [x] Fixed: a day's sunset is the one whose solar noon falls on it, so Samoa/Tonga/Kiritimati (clock a day ahead of
      the sun) read "—" after sunset instead of counting to tomorrow's; the time-zone test used Tokyo and expected the
      bug, now Chicago, plus Apia; `SunsetFix.isFresh` two-sided for a clock set back; `utcMinutes` doc; W21 in
      `MapDashboardWidget`'s caller lists; VoiceOver reuses `spokenElapsed`; `Sunset/` in TCA.md §8
- [x] `SunsetTests` 23/23 (review ran it)
- Skipped: refresh `sunsetFix` by distance instead of time (design change, small saving); no-fix and after-sunset
  snapshots are identical images (kept: one per state)

### W21 sunset icon (Brian, after review)

- [x] `sunset.fill` in the lower right, `.title2`, `cyTextSecondary`, inset `Spacing.sm`; drawn in every state, hidden
      from VoiceOver by `widgetDetail`; UX.md §W21
- [x] Brian ran it: "looks good"
- [x] Re-recorded the 6 W21 snapshots and S08's catalog; the catalog's pixel diff against the last commit is only the
      icon (73×59 pt-px box, light and dark)
- [x] Sunset, Sunset snapshots, S08 catalog snapshot, WidgetAccessibility: 107/107, every suite non-empty

---

# #463 — W22 Climb: current and next climb on the route

From main (Brian), so it conflicts with #490 in the catalog, S08 lists and UX.md until that merges. Brian chose: the W5
2×1 arrangement; climbs from stored `Route.terrain`; showcase on the Elevation page, row 5. No W22 frame in Sketch.

- [x] `RouteClimb` + `ClimbReading.at(progressMeters:climbs:)` in `Models/RouteClimb.swift`
- [x] `NavigationRoute.climbs` from `detail.summary.terrain`, profiles from `RouteTerrain.gradeProfile` at load
- [x] `NavigationFeature.State.climbReading`
- [x] `ClimbWidget` view + previews; `ClimbDashboardWidget` adapter (tap → Elevation sheet)
- [x] Catalog, factory showcase (Elevation page row 5), `AddWidgetSheetTests` Route lists
- [x] Tests: `ClimbReadingTests`, `NavigationFeatureTests`, accessibility, 10 snapshots
- [x] UX.md §W22, §S08 Route list, header line
- [x] Build (app + tests)
- [x] Hand over to Brian — "looks right"
- [x] Recorded the 10 W22 snapshots (checked: profile behind, ridden darker, stats on the baseline, "—")
- [x] Full `CyclometerTests` less `PersistenceClientTests` (#480): 2246 passed, 0 failed, every new suite present;
      `PersistenceClientTests` alone: 47/47

## Review

- The S08 catalog reference didn't move: its image ends before the Route section, so W22 there is unpinned (as W19/W20).
- Climb distances need no conversion: `Climb.startMeters` is a sample index × the resample spacing, which is distance
  along the same polyline `cumulativeDistances` measures; `ClimbReadingTests` pins a climb's top to the road's elevation.
- "To climb" reaches exactly 0 at the top because the ride re-runs `RouteTerrain.gradeProfile` at load, the pipeline
  the stored climb was found on. If that pipeline changes, stored climbs would sit on a different profile until
  re-analysed; `RouteClimb` drops one that falls off the profile rather than misplacing it.

### #493 merge with main (#490 landed)

- [x] Merged `origin/main` (no rebase, so no force push). Conflicts were W21 and W22 adding a line in the same places;
      each keeps both, W21 first: catalog, Elevation showcase page (+ its comment), `WidgetAccessibilityTests`, UX.md
      (header lines, §W21 then §W22, S08's Ride and Route lists), and this file (#462's section, then #463's)
- [x] Build; S08 lists, S08 catalog snapshot, DashboardLayout, WidgetAccessibility, Sunset, Climb, NavigationFeature:
      224/224, every suite non-empty

### #493 review (`/code-review xhigh --fix`)

- [x] Fixed: climbing left measured from the climb's own profile top (`elevations.last`), not the stored
      `topElevationMeters`, so it reads 0 at the top even after a pipeline change; `RouteClimb.sample` moved into
      `ClimbWidgetView.swift` (shared by previews and tests, replacing a copy); W22 in TCA.md §8 and `ElevationSheet`'s doc
- [x] ClimbReading 8/8, NavigationFeature 57/57, WidgetAccessibility 80/80, Climb snapshots 10/10 (review ran them)
- Correction to the review above: `RouteClimb` drops a stored climb only when it falls *outside* the profile; one from a
  different pipeline that still fits would be placed as stored.
- Skipped, for Brian: analyze at load when a route has no stored terrain (pre-#252, not yet backfilled → "No climbs
  ahead" on a hilly route); `ClimbWidgetSnapshotTests` on CI's skip list. Also skipped: a loop joined after its climb
  reads "No climbs ahead" until the wrap (pinned by a test); keeping each climb's samples in the analysis instead of
  re-deriving at load; the straight-route "second lap" unit test; exact float compares; S08's sample has no route

### #493 review follow-ups (Brian: "#5, do it. #6, add to ci skip list")

- [x] No stored analysis (pre-#252, not yet backfilled): `RouteClimb.climbs` runs `RouteTerrain.analyze` at load, so W22
      finds the climbs instead of reading "No climbs ahead"; a stored analysis is still used as is. Test:
      `noStoredAnalysisIsAnalysedAtLoad`; UX.md §W22 and `NavigationRoute.climbs`' doc say so
- [x] `ClimbWidgetSnapshotTests` on CI's skip list, beside `ElevationWidgetSnapshotTests` (both draw a Swift Charts area)
- [x] ClimbReading, NavigationFeature, NavigationPipeline, ElevationDashboardWidget: 79/79, every suite non-empty

---

# #465 — W23 Active Calories widget and Calories sheet

Brian chose: showcase page 3 row 4 left; the sheet's average rate over W3 Moving Time; the chart over elapsed ride time,
whole ride. The live estimate is `RideEnergy.activeKilocalories` over an in-memory copy of the recorded track, once a
minute, with the rider built as `RideHealthWorkout.write` builds it.

- [x] `RideEnergy.Rider.init?(kilograms:dateOfBirth:sex:on:)`, used by `RideHealthWorkout.write`
- [x] `CaloriePoint`, `CalorieSeries.rebuild(track:through:rider:)` + `CalorieSeriesTests`
- [x] `ActiveRideFeature`: calorie track, rider status, minute recompute, resume seed + rebuild; TestStore tests
- [x] `CaloriesWidget` + adapter, `CaloriesSheet` + `CaloriesMetrics`, previews
- [x] Catalog, factory showcase (page 3 row 4 left), S08 sample, `AddWidgetSheetTests` Ride lists
- [x] Accessibility test; widget + sheet snapshots (sheet on CI's skip list)
- [x] UX.md §W23, "Sheet: Calories", S08 Ride list, S10 calories line, header; TCA.md §8
- [x] Build (app + tests)
- [x] Hand over to Brian. He asked for `bolt.fill` in the lower right (W21's treatment), and for the sheet's rows to
      become small hero columns, Total and Average, with the model in the section footer. Both done, and UX.md matches
- [x] Recorded 12 Calories snapshots (widget + sheet: no body mass, early, long; light + dark) and re-recorded the S08
      catalog. Opened them: none flat, W23 at the end of the catalog's Ride section
- [x] Targeted suites: Calorie/ActiveRideCalories/RideEnergy/RideHealthWorkout/RideEndFailure, WidgetAccessibility,
      AddWidgetSheet (+ snapshot), DashboardLayout, both Calories snapshot suites and every ActiveRideFeature suite:
      369/369, every suite present, no host restarts
- [x] #494 filed: the other widget sheets to the same hero columns

## Review

- **Same inputs as Health.** The live estimate runs on `calorieTrack`, filled in the same tick as the recorder, and
  `minuteSeriesMatchesHealthWorkout` runs `RideHealthWorkout.write` on what the recorder flushed and gets the same kcal.
  The CoreData round trip is exact: a negative GPS speed is already nil before it reaches the track.
- **The host crash was mine.** `ActiveRideCaloriesTests` lacked `@MainActor`, so `TestStore.init` tripped the runtime
  isolation check (SIGTRAP) and every suite running in parallel reported 0.000 s failures. Every sibling suite has it.
- **Sample fixed.** `CaloriesMetrics.sampleLong` multiplied a varying rate by elapsed minutes, so the chart dipped;
  calories never fall. It now rises everywhere and still steps where physics hands over to heart rate.
- **One existing test touched.** `zeroSpeedCounterResetsOnSpeed` is exhaustive and its tick now appends a point with a
  random `UUID()` id to `calorieTrack`. That one step runs non-exhaustive and the point's speed is checked after.
- **Not covered.** Rebuild time for a 4 h ride after a kill (≈240 recomputes, off the main thread) isn't measured.

### #495 review (`/code-review --fix`)

- [x] Fixed by the review: the sheet's Average divides each point's energy by its own moving time (`CaloriePoint.movingSeconds`);
      "No estimate yet" previews; DashboardLayout's free-cell comment
- [x] Brian: "#3 do as recommended": a resumed ride whose saved track is empty or unreadable doesn't rebuild its minutes
      before the resume (`isSavedTrackMissing`); the series starts at the resume. UX.md §W23 says so
- Not done, Brian's call: the total can fall when the model drops back to physics (#1); no extra estimate at a pause, so
  a ride ends on its last whole minute's value, not Health's (#2); #4–#7 left
- Not run: `ActiveRideCaloriesTests` after the #3 change (built only)
- [x] Run after the #3 change: the #465 suites, 189/189 passed (incl. `liveMinuteWaitsForSavedTrack`); full `CyclometerTests` not run

---

# #464 + #466 — Sensors toolbar button and Sensors sheet

Brian chose: **one** toolbar button, glyph `antenna.radiowaves.left.and.right`, shown when any paired device is missing
*or* low (≤ `SensorHealthReport.lowBatteryPercent`, 20%); its badge counts those devices. One PR closes both issues.
Placement follows the Design.sketch `Sxx - Route overlay` frame, group **sensor button**: trailing, left of Bell.

**State: `SensorHealthFeature`** (already subscribes to every status and battery stream)
- [x] `.connected(SensorRole)` becomes `.statusChanged(SensorRole, isConnected:)`; the log still records only the
      first connect. Connected means `.active` (HR: notifying), the bar #391 already used, not the Start
      sheet's `.connected`/`.active`: #464 excludes changes to the verdict
- [x] Keep each role's live status and current battery beside the log; battery clears on the client's `nil`
      only. Clearing on a status change would race the once-per-connection read, which can land before `.active`
- [x] Derived `devices`: paired sensors grouped by peripheral (combo CSC is one row with both roles), each with
      connected (every role up), battery, name; `attentionCount` = missing + connected-and-low
- [x] TestStore: ≤20 shows / >20 hides; low then disconnect stops counting as low and counts as missing;
      combo counts once; never-found counts; nothing paired → 0; no extra effects (no sound/haptic/banner)

**UI**
- [x] `SensorsButton` (internal, `Features/ActiveRide/SensorHealth/`): 52 pt glass circle like the other controls, red count badge
      as in the frame. VoiceOver "Sensors, 1 not found" / "Sensors, low battery: Radar, 18 percent" / both joined;
      hint "Opens sensor status"
- [x] `rideControls`: `[Pause | Resume Finish] · Spacer · [Sensors] [Bell]`, `controlTransition` (fade under Reduce Motion)
- [x] `SensorsSheet`: one row per device via `SensorListRowView` + `SensorRowStyle.device`, Connected/Searching
      capsule, `SensorBatteryLabel` when connected. No pair/forget. Reads live state in its body (#144 lesson)
- [x] `ActiveRideFeature`: `isSensorsSheetPresented` + tap / presentation-changed actions, as Add Widget does; TestStore
- [x] Previews for every state; snapshots of button (1 missing, 2 missing, 1 low, missing + low) and sheet, light + dark;
      accessibility label test

**Specs**
- [x] UX.md §S05 Bottom Toolbar row + button paragraph; Open UX Question glyph → `antenna.radiowaves.left.and.right`;
      new "Sheet: Sensors"; §S10 "no mid-ride alert" wording points at the quiet badge
- [x] BLE.md §14.5 "surfaced on" adds S05; TCA.md §8 tree entry; `SensorHealthFeature` header comment ("records only")
- [x] Extracted `RideControlButton` (was a private func) and `SensorStatusBadge` (was `SensorStatusRow.statusControl`)
      so the new button and sheet share their styling; `Spacing.toolbarBadge`
- [x] Build (app + tests)
- [x] Brian: no overflow (UX.md §S05 says a future button revisits it), then "complete it"

**Toolbar overflow:** Brian chose none. With one button the widest row (paused + Sensors) leaves ~13 dots' room at
402 pt and no other toolbar item is planned; UX.md §S05 says a future button has to revisit it. No issue filed.

## Review

- [x] Recorded 14 snapshots (button: 1/2 missing, 1/2 low, missing + low; sheet: missing + low, two missing; light +
      dark). Opened them: the button's first recording had no glass disc offscreen, so it snapshots in the key window
      (`drawHierarchyInKeyWindow`). Both suites on CI's skip list
- [x] Targeted run: every ActiveRideFeature suite, SensorHealth/RideEnd/RideSensorsSheet/VoiceOver suites, StartSheet
      (+ snapshot, unchanged after the badge extraction), both new snapshot suites: 228/228, every new test present
- **Not snapshotted:** "none missing / none low". The button isn't drawn then; `neverFoundIsMissing`, `nothingPaired`
  and `lowBatteryComesAndGoes` pin the empty list that hides it.
- **Not run:** the full `CyclometerTests` locally (CI runs it).

### #496 review (`/code-review --fix`)

- [x] Fixed by the review: `.finishTapped` also closes the Sensors sheet, so auto-end's finish alert can show
      (`autoEndClosesSensorsSheet`); the badge doesn't take touches (`allowsHitTesting(false)`)
- Open, Brian's call: (3) the button can flicker on a level rebounding across 20%, which needs hysteresis or a latch;
  (4) before the first status replay every paired device reads missing, so possibly a flash at ride start; (5) one
  sheet enum for the dashboard; (6) device grouping and "Speed & Cadence" title duplicated with S10
- [x] Brian: (3) latch. Low is judged on the log's ride minimum (`SensorHealthLog.minBatteryPercent(peripheral:)`), and
      the per-role current-level map is gone. The sheet shows that minimum. Departs from #464's AC ("above it again
      hides the indicator"), on BLE.md §14.5's evidence. `lowBatteryLatches`, `lowThenDisconnected` (reconnects low)
- Brian: (4) leave it unless seen on a real ride; (5), (6) not done
- [x] Run after the latch: SensorHealth, RideEnd, RideSensorsSheet (incl. `autoEndClosesSensorsSheet`), VoiceOver,
      DashboardEdit and both Sensors snapshot suites: 52/52, the new tests present
- Not run: tests after the review's fixes (built only)

---

# #471 — Auto-dim brightness slider (S12)

Plan: `~/.claude/plans/wiggly-finding-phoenix.md`. Brian chose: the slider sets the dimmed brightness (0–50%,
default 10%, sun icons), and dragging previews it on the real backlight.

- [x] `AppPreferences.autoDimBrightness` (+ decode fallback 0.1, range, shared `dimmedBrightness(from:)` clamp)
- [x] `AppFeature` dims to the preference; `AppFeature.dimBrightness` removed; leaving the app ends a S12 preview
- [x] `SettingsFeature` preview: capture → clamped write per tick → restore on end; the read is cancelled if the drag
      ends first; the restore isn't cancellable (a fresh drag would otherwise capture the dim as the rider's level)
- [x] `SettingsView` slider row under the toggle (bare `if`), `onDisappear` backstop, "Auto-dim off" preview
- [x] Tests: SettingsFeature (4 new), AppScreenPower (`dimUsesChosenLevel`, backgrounding receives the preview end),
      AppPreferences (round-trip + legacy decode)
- [x] `UX.md` §S12 row + Auto-dim paragraph
- [x] Brian runs it on device (the simulator's brightness doesn't move): "works good on initial go"
- [x] Re-record `SettingsSnapshotTests` (General gains the row), compare against main, add `autoDimOff`

## Review

- [x] Targeted run: SettingsFeature, AppScreenPower, AppPreferences, LiveActivityFeature, CadenceZone: all green, every
      new test present
- [x] Snapshots: all 14 re-recorded + `autoDimOff` (light/dark). Pixel-compared with main: `autoDimOff` differs from
      main's `default` only in the Auto-dim switch; every other reference gains one 61 pt row (183 px), with the content
      below shifted by exactly that and the HR Zones header gap unchanged. The only other differences are glyph
      anti-aliasing inside unmoved text
- [x] Full `CyclometerTests` locally without `PersistenceClientTests` (MapKit deadlock): 2340 passed; then
      `PersistenceClientTests` alone: green

---

# #480 — PersistenceClientTests × MapKit deadlock

Root cause (from code + the issue's samples): `CoreDataStack.load` sets `automaticallyMergesChangesFromParent` and
`mergePolicy` on `viewContext`, a main-queue context. Set from any other thread, CoreData runs each setter through
`performBlockAndWait` on main. `makeLiveClient()` builds a stack per test on the cooperative pool, so every parallel
persistence test parks a pool thread on main. Nothing reads `viewContext` — every read and write goes through
`newBackgroundContext()` or batch requests, and `batchDeleteTrackPoints` documents that nothing merges into it — so
the configuration is dead code that only costs the hop. `.shared` pays it too, from whichever thread first resolves
`\.persistenceClient`.

- [x] Regression test first: a `@MainActor` test builds `CoreDataStack(inMemory: true)` on a separate thread while
      main waits on a semaphore. On main's code it failed at the timeout (5.008 s), so the build waits for main.
      With the fix it passed in 1.8 s alongside the other suites, so the timeout is now 30 s, as headroom against a
      spurious failure under load
- [x] `CoreDataStack`: drop the two `viewContext` setters and the unused `viewContext` accessor; `load` keeps
      `loadPersistentStores` and its `fatalError`, so `.shared`'s launch behaviour is unchanged. The fixed binary has
      no `setAutomaticallyMergesChangesFromParent:` reference; main's has one
- [x] Run the new test, `PersistenceClientTests`, `RoutePersistenceTests`, `TimeSeriesMigrationTests` (plus the other
      `CoreDataStack(inMemory:)` users: RideDataBuffer, RideDeletion, RideRename, RoutesImportIntegration,
      NavigationPipeline): 105 passed, 0 failed
- [x] Deadlock question: see Review
- [x] Three consecutive full `CyclometerTests` runs with no `-skip-testing`: all three completed; see Review
- [x] Update the `persistence-tests-mapkit-deadlock` memory and drop the skip advice

## Review

- **Reproducing it.** Six unloaded full runs on main's code (`test-without-building`, ~2.5 min each) never hung.
  With all 18 cores held by busy loops, the first run hung. Its sample had the issue's exact signature: main in
  `-[VKMapView dealloc]` → `MapEngine::~MapEngine` → `flushTileDecodeQueues` → `dispatch_sync` onto the tile-decode
  queue; that queue's task in `dispatch_semaphore_wait`; all 18 cooperative-pool threads (the pool is 18 wide here)
  in `makeLiveClient()` → `CoreDataStack.load:45` → `setAutomaticallyMergesChangesFromParent:` →
  `performBlockAndWait` on main. A second loaded run of main didn't hang: it's a race even under load.
- **Is it a true deadlock?** [Likely] yes. No thread was running whatever would signal the tile-decode semaphore, so
  its work was queued somewhere that couldn't run. The sample can't show where. It can't be main alone: then the hang
  wouldn't need the persistence tests, but every run recorded in this file that skipped only
  `PersistenceClientTests` (six, MapKit suites included) completed. So it's waiting on a worker thread that the 18 blocked pool threads keep from
  running, whether that's a Swift concurrency job or a GCD worker under the same thread limit.
- **The fix under the same load.** Three loaded full runs on the fix: none showed the signature (sampled each time
  the log went quiet). Two completed green (2,389 cases passed). The third was killed after an hour, with 2,388 cases
  passed: the one still in flight was `PermissionsClientTests/liveHealthStatus()`.
- **Found, not fixed (1): the load starves HealthKit.** `liveHealthStatus()` asks the simulator's HealthKit for a
  status. Unloaded it takes 2.7–5.6 s; with every core busy it took 351 s, 1,318 s, and over an hour. It hit main's
  second loaded run too, so it isn't from this change. It only shows under artificial load.
- **Plain full runs on the fix, back to back:** 1) 2,389 passed, 0 failed; 2) 2,388 passed, 1 failed; 3) 2,389
  passed, 0 failed (cases, counted across split log lines, as the 2340 above). None hung.
- **Found, not fixed (2): `LiveActivityFeatureTests/settingOffWhileStartingSendsNothingMore()` is flaky.** It
  failed once (plain run 2): "nothing after the start, got [start, end]". The test assumes the setting's `end` is
  recorded before the delayed `start` resumes, but its own comment says the recording client doesn't queue, so the
  order is a race. No CoreData involved; it passed in the other 11 full runs (6 on main).
- **Logs:** `Cyclometer/.build/480-*.log`; the deadlock sample is `Cyclometer/.build/480-hang-main-sample.txt`.
- [x] **(2) fixed, on Brian's call.** Cause: S12 "off" cancels `CancelID.start`, and the test's delayed start slept
      with `try? await clock.sleep(...)`. A cancelled `TestClock` sleep returns at once (swift-clocks: the stream
      ends on cancellation, then `checkCancellation()` throws), so the "late" answer was recorded right away and raced
      the setting's `end`. A probe showed it: the start was recorded with the clock never advanced. The test's start
      now waits on a gate outside the cancellation (`Task { for await … }`), as ActivityKit's request isn't cancelled
      with the effect, and the test releases it once the `end` is recorded, so the order is causal. Not a
      shielded clock sleep: one registered after `advance` would never fire. 200/200 iterations; mutation (drop the
      reducer's `.cancel(id: CancelID.start)`, own DerivedData) fails it; `LiveActivityFeatureTests` 25/25. The
      sibling `settingOffAndOnWhileStartingTakesTheSecondAnswer` uses the same sleep but its answer order is fixed
      (the first is released by the cancel, the second only by `advance`), so it's unchanged
