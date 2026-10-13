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
