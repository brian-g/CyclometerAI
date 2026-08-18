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
