# Lessons

Patterns to avoid repeating. Added after a correction from Brian.

---

## Don't grow scope into UI the issue didn't ask for (2026-08-17, #96)

**What happened.** Issue #96's title said "manual entry", so I proposed adding max/resting HR entry
fields to the S12 Settings screen. Brian: "Why is the scope increasing to include resting and max
heart rates into the UI? These are not needed now at all."

**Why I was wrong.** The issue body said "Blocks the S12 HR Zones section" and a separate issue
(#103) owned that section. "Manual entry" described where the *values come from* — manually sourced
rather than read from HealthKit — not a screen to build. Checking the specs would have settled it:
UX.md §S03, the only screen that ever collected these, is marked **Cut**, and §S12's actual controls
are steppers on zone boundaries, not HR fields.

**Rule.** Before proposing UI for a foundation issue, find the issue that owns the screen. If one
exists, the seam is already drawn — build to it, don't cross it. Read the phase/status line of any
UX screen before assuming it's a place to put things.

---

## Framework-owned data should be read, not copied (2026-08-17, #96)

**What happened.** I planned to persist resting HR, max HR and date of birth per the spec. Brian:
"My assumption is that none of these need to be stored by this app. They should only be read as
needed from HealthKit."

**Why he was right, and where it needed qualifying.** Resting HR and date of birth are genuine
HealthKit types, and resting HR is rewritten daily by an Apple Watch — an app-owned copy is stale by
construction. But **HealthKit has no max-heart-rate type**, so that one field genuinely needs local
storage. The answer was neither "store everything" nor "store nothing": store *overrides only*, and
resolve `override ?? framework ?? default` at read time.

Two things I should have caught before writing the plan: PRD §8.5 had said "app-stored values are
always considered overrides" since v0.2 — the DataModel entity shape had never matched its own PRD —
and I had already read `HealthKitClient.fetchMaxHeartRate` without asking what it would query.

**Rule.** When a spec says to persist something a system framework also owns, check what the
framework actually exposes *before* planning the schema — a stub named `fetchMaxHeartRate` is not
evidence the API exists. Then ask which side owns the truth. Prefer resolution at read time over a
synced copy. And when two specs disagree, the one describing *behaviour* (PRD) usually caught the
intent that the one describing *shape* (DataModel) lost.

---

## When a sweep test fails, fix the model, don't narrow the sweep (2026-08-17, #96)

**What happened.** A round-trip test over every valid HR profile failed at heart-rate reserves ≤ 7,
where the zone arithmetic collapses two boundaries onto one bpm. The easy fix was to restrict the
sweep. The right fix was a validation rule (`minimumHRReserve = 8`) making those profiles
unrepresentable, with the sweep then derived from what validation admits.

**Rule.** A property test failing at an edge is evidence about the model, not about the test. Fix the
model so the edge is unreachable, then tie the test's range to the model's own constraint — so
widening it later fails loudly instead of silently re-admitting the bug.

---

## A per-test deadline can't guard against the thing that trips it (2026-08-18, #98)

**What happened.** CI went red on #98 and Brian flagged it — "once again". It was not #98's fault:
`main` and `feat/97` were already failing the same way. Three runs, three *different* arbitrary tests
from `VariaRadarIntegrationTests`, each dying at exactly 60.000s — the `.timeLimit(.minutes(1))` that
#97 had added to the BLE integration suites a few hours earlier. The last green `main` predates that
merge.

**Why the obvious fix was wrong.** My first instinct was to raise the limit to 5 or 10 minutes. The
repo had already disproved that: #117 left a note in `PermissionsClientTests` recording a stalled CI
simulator clone where `isGranted()` — a pure enum switch with no I/O — took 90s once and **544s on a
passing run**. No threshold survives that. A deadline evaluated inside the run is subject to the exact
contention it is meant to guard against, so it kills tests that were merely delayed.

Worse, Swift Testing **aborts the whole run** when one case trips a `.timeLimit`, so every test
scheduled after it silently never runs. That bit me twice locally the same day: I read a green-looking
list that simply hadn't executed the tests I cared about, and nearly concluded a fix was verified when
its test hadn't run at all.

**Rules.**
- Don't bound a test with a deadline when the thing that could stall it is the runner, not the code.
  Put the bound where it has no coupling to the contention — a CI job `timeout-minutes`.
- A `.timeLimit` is only defensible when a hang can come *from the code alone*, and even then ask what
  it buys over a hang that is obvious locally in a second.
- Before trusting a green test list, check the tests you care about are actually *in* it. `grep` for
  them by name. An aborted run looks like a passing one if you only read the summary.
- Before reaching for a fix on a CI failure, check whether `main` is already red. Three commands —
  `gh run list`, then `--log-failed` on your branch and on `main` — separate "my regression" from
  "pre-existing" and stop you debugging your own diff for nothing.


---

## A blank snapshot reference is a test that can never fail (2026-08-19, #100 follow-on)

**What happened.** I added a full-screen snapshot suite for the Start sheet, recorded it, and the run
"succeeded" — six PNGs on disk, second run green. The references were solid white rectangles. Nothing was
being pinned, and the suite would have stayed green through any change to the screen.

**Why.** `StartSheetView`'s `.toolbar` renders blank inside a `UIHostingController`. A ladder settled it in
one run: a plain `NavigationStack` + `List` renders; adding the sheet's `.topBarLeading` /
`.topBarTrailing` items blanks the entire image. Not a bug in the change under test — a limit of the
harness. The fix was to snapshot the row that actually changed (`SensorStatusRow`, made internal) rather
than the screen around it.

**Rules.**
- After recording a new snapshot reference, **look at the image**. "It recorded and the second run passed"
  proves the render is *stable*, not that it rendered anything. A cheap programmatic guard is the count of
  distinct bytes in the decompressed IDAT — 1 means one flat colour.
- When a snapshot comes out empty, bisect the view with a ladder in a single run rather than theorising
  about the harness. Two or three `assertSnapshot` calls of progressively fuller views name the culprit
  immediately.
- Prefer snapshotting the component that changed over the screen that contains it. It renders more
  reliably, it fails for the right reason, and it matches how the rest of this repo's suites are built.


## `-only-testing` with a Swift Testing function name silently runs nothing (2026-08-19)

**What happened.** To prove a new regression test actually caught the bug, I reverted the fix and ran
`-only-testing:CyclometerTests/BLEHRIntegrationTests/batteryReadRefreshesTheDeviceList`. It exited **0** in
seconds. For a moment that read as "the test passes without the fix, so it proves nothing". The truth was
worse and better: the filter matched no test at all, `xcodebuild` ran zero cases, and zero failures is a
successful run. Filtering to the whole suite instead reproduced the hang immediately.

**Rules.**
- A filtered `xcodebuild test` that exits 0 proves nothing until you check the case *count*.
  `grep -cE '^Test case' <log>` — zero means the filter, not the code.
- Verify a regression test by reverting the fix, not by reasoning about it. Both directions need the same
  count check.

## Ask what a constraint costs before offering it as an option (2026-08-19)

**What happened.** The Start sheet showed no status for paired sensors. I found that nothing scans while the
sheet is open, and offered Brian three ways to word a badge that would therefore always read "not connected"
— with "make the sheet scan" as one option among them. He picked a wording, and the result was a screen that
said Disconnected on every row, every time. He was rightly unimpressed.

**Why I was wrong.** I treated "nothing scans here" as a fixed constraint and turned the consequence into a
copy question. It was never fixed: `beginPairingScan` is refcounted and independent of the ride's scan, S11
already holds one open, and the whole change was ten lines. The screen's stated purpose in UX.md §S05.1 is
"provide sensor status" — a status that is constant is not status, so two of the three options I offered
could not satisfy the screen's own spec.

**Rule.** When a finding makes a feature useless, fix the finding — do not offer the rider-visible symptom
as a menu. Before presenting options, check each one against what the screen is *for*; drop the ones that
cannot satisfy it rather than letting a choice ratify them.


## A `@Presents` child never sees its own `onDisappear` (2026-08-21, #100 review)

**What happened.** The Start sheet took a BLE pairing scan on `.task` and released it on `.onDisappear`,
mirroring what S11 does. S11 is a plain `Scope` behind a `NavigationLink`, so its state is never nil and the
action always lands. The Start sheet is a `@Presents` child, and **every** dismissal path — Cancel's
`dismiss()`, the parent nil-ing `startSheet` on ride start, a swipe — clears the presented state *before*
SwiftUI runs `onDisappear`. The action therefore arrived at an absent destination, TCA dropped it with a
runtime warning, and the scan was never balanced: a leaked reference on all three clients per sheet open,
with the radio left on for the rest of the process.

`StartSheetFeatureTests` could not see it. It drives the reducer directly, where sending `.onDisappear`
works fine — the bug lives entirely in the presentation wiring above it.

**The fix that looked right and wasn't.** Tying the release to the effect's own cancellation
(`try? await Task.never()` then release) does work, and keeps the concern inside the sheet. But it makes the
effect immortal, and `TestStore` requires every effect to finish — so it broke an unrelated test and would
have taxed every future one. The owner of the presentation takes and releases the scan instead: it is the
only thing that sees both ends of the lifetime.

**Rules.**
- `onDisappear` is only reliable for a child whose state outlives the view. For a `@Presents` child, put
  paired setup/teardown in the parent, around presentation.
- A reducer-level test cannot cover presentation wiring. When the bug is "the action never arrives", the test
  has to drive the parent.
- Weigh a fix against the test harness's constraints, not just correctness. An effect that never finishes is
  a fine runtime pattern and a bad `TestStore` citizen.
