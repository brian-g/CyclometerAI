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
