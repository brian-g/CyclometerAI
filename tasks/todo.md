# PR #59 — address review comments + code-review findings

Base: local `feat/speed-widget-w1` @ dbca127 (coherent, passing). Remote tip is a
broken merge (old tests + new widget). Plan: finish all items locally, then
**force-push** to overwrite remote (user-approved).

## Decisions (user-confirmed)
- Units: Foundation `Measurement` + `Locale` default (no hardcoded factors).
- HeroNumber: extend it (baseline-clean + optional chevron accessory) and use it
  for AVG/MAX/Distance/Time; delete `statCell`.
- speedHistory: last-hour time-based window, downsampled (~60 buckets) for chart.
- unitSystem stays in State for now, default `.system` (locale), with TCA note.

## Tasks
- [ ] 1. UnitSystem → Measurement + Locale `.system`; iOS-provided symbols.
- [ ] 2. ActiveRideFeature: avg/maxSpeedMPS via Measurement (kill magic 3.6); unitSystem default `.system` + TCA comment.
- [ ] 3. Title-case labels: "Speed", "Avg", "Max" (textCase handles display).
- [ ] 4. Tokenize: opacity token (+UX.md), heroFontSize 136/200 constants, chevron rotation constant.
- [ ] 5. Format-string helper for `.fractionLength(1)` (no copy/pasta).
- [ ] 6. @ViewBuilder consistency on the layout fns.
- [ ] 7. Layout bug: Distance must never truncate; expand and push Time right (testTwoByTwoNoSignalDark).
- [ ] 8. HeroNumber: optional chevron accessory + baseline-clean; AVG/MAX/Distance/Time use it; delete statCell.
- [ ] 9. speedHistory: last-hour time window + downsample for watermark.
- [ ] 10. Rebuild, re-record snapshots, run full suite.
- [ ] 11. Commit + force-push; reply to PR threads.

## Review (done)
All 11 tasks complete; full suite green (except pre-existing
HeroNumberSnapshotTests.testCustomColor, unrelated).
- Units: UnitSystem now uses Foundation Measurement + UnitSpeed/UnitLength
  symbols; `.system` default from Locale.measurementSystem. No hardcoded factors.
- ActiveRideFeature: averageSpeedMPS/maxSpeedMPS via Measurement; unitSystem
  defaults to `.system` with a TCA note (preference → @Shared/dependency later).
- Widget: title-case labels; HeroNumber used for Avg/Max/Distance/Time (chevron
  via new `heroAccessory`); statCell deleted; Distance no longer truncates
  (fixedSize + layoutPriority pushes Time right); tokenized opacity
  (Opacity.watermark) + heroFont/chevron constants; shared oneDecimal formatter;
  dropped needless @ViewBuilder on speedHero.
- speedHistory → timestamped SpeedSample, 1-hour window, downsampled to ≤60
  watermark points. SpeedFeature gains @Dependency(\.date). Tests updated to
  pin date; added prune + downsample tests.
- UX.md: documented Opacity tokens. HeroNumber: optional baseline-aligned accessory.
- Snapshots re-recorded (9/9 pass).
