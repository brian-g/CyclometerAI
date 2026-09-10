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


## Verify the bug report's *mechanism* against the raw data before designing the filter (2026-09-07, #210)

**What happened.** #210 described four "GPS spikes" — 12–20 m one-second position jumps against a sane speed
channel — and the approved plan filtered them by implied speed: reject a fix whose jump contradicts the active
speed source. Replaying the ride's own 566 points killed the design. The jumps are not bad positions. Each is
the *end* of a stretch where the reported position crawled (0.3–0.8 m/s against a reported 3.1 m/s for six
seconds) and then caught up. Over a window either side, haversine and the speed integral agree to a few metres,
and the bearings through the snap are constant — the rider genuinely covered that ground.

The jump filter therefore rejected the one honest fix in each window, held the stale position three more
seconds, then re-seeded and drew the same line anyway: 3259.2 m filtered vs 3259.9 m unfiltered. It changed
when the snap appeared and nothing else.

**What the data was asked, and answered.** Three cheap checks, all before writing tests:
- Sum haversine *and* the speed integral over a window spanning the artefact. Equal ⇒ no position error, only
  latency.
- Look at bearings through the jump. Constant ⇒ a straight line, not an excursion.
- Look at the seconds *before* the jump, not just the jump. The stall is the defect; the jump is its shadow.

**Rules.**
- A bug report's numbers can be right and its mechanism wrong. Reproduce the mechanism from raw data before
  committing to a filter shape — an issue's "Scope" bullets are a hypothesis, not a spec.
- When a filter's job is to remove bad data, measure what it removes *and* what the output looks like after.
  "Rejects all four listed timestamps" was true of a design that improved nothing.
- Prefer filtering on a measurement the app already makes (`horizontalAccuracy`, cross-checked against a log
  archive) over a derived heuristic with a threshold tuned to one ride.
- Stop and re-ask when the finding invalidates an approved plan, even mid-implementation. The earlier answer
  was given under the wrong model of the defect.

---

# "It passes locally" is not evidence for an async test

**The correction.** CI failures in `CyclometerTests` were framed as flaky tests that
might need turning off. They were real tests catching real races. The tell was in the
numbers, not the code: the suite executes in **8 seconds**, but CI runs took 16 minutes.
All of that gap is build and simulator boot. A suite that cheap has no business being
parallelised across simulator clones, and the clones were causing two of the four bugs.

**What made the diagnosis hard, and what fixed it.** `xcodebuild`'s console output for a
failing cloned-destination run is the test's *name* and nothing else — no assertion text,
no line number. The failing run's log had 14,279 lines and not one word about why three
tests failed. That is not a logging inconvenience; it is the reason the problem recurred,
because a genuine bug and a simulator flake were indistinguishable. The `.xcresult` bundle
had the full message the whole time.

**Rules.**
- Before theorising about a flaky test, get the actual assertion message. If the harness
  is not printing one, fixing *that* comes first — everything after it is guesswork.
- Green on an idle machine proves nothing about a test that awaits async state. Run it
  under CPU contention, repeatedly, or do not claim it passes. Six consecutive green runs
  preceded a reproduction on the seventh, under load.
- A state stream is a sync point for the **state**, not for whatever the producer does on
  its next line. Awaiting `connectionState == .connected` does not order the
  `discoverServices` call the handler makes immediately afterwards.
- A wait predicate must be unsatisfiable by earlier history. "The last call is a
  `startScanning`" was already true from the *opening* scan, so the wait returned
  instantly and the test asserted against a state that had not happened yet. Prefer
  counting occurrences over inspecting `.last`.
- Fixing a race can convert a sibling flake into a hard failure. That is progress —
  it means a second bug was hiding behind the first, not that the fix broke something.
- Real deadlines (`TestStore.finish(timeout:)`, `.timeLimit`) count wall-clock time and
  so couple to machine load. Wait for an observable condition where one exists; where a
  deadline is unavoidable, make it generous, since a long deadline can only delay
  reporting a hang, never mask one.
- Do not rewrite tests you could not reproduce failing. Say plainly which ones those are
  and what would diagnose them next time.

**Also.** Repeated `xcodebuild test` leaves a booted simulator and its whole daemon set
behind. Eight iterations reached 221 simulator processes and the OS killed the run for
memory pressure. `xcrun simctl shutdown all` between iterations.

**`skipInFlightEffects` cancels, it does not drain.** The Ride suites used it as "wait
for the fire-and-forget pipeline", with a comment saying so. It cancels. On an idle
machine the pipeline won the race and the tests passed for months; on a loaded CI runner
the cancel landed first and the ride was left half-ended. Wait for the work's own
observable end state, then tear the store down — never the other way round. Corollary:
when a test's teardown can cancel the thing it is asserting about, a longer timeout is
treating a symptom.

---

## `try?` around an encode is a silent data-loss path (2026-09-08, #191 review)

**What happened.** `Route.init` stored its polyline with
`polylineData = try? JSONEncoder().encode(imported.coordinates)`, copied from the
`Ride.weatherData` / `Ride.syncRecords` pattern. A code review pointed out that
`JSONEncoder`'s default `nonConformingFloatEncodingStrategy` is `.throw` — so a single
non-finite coordinate makes the encode throw, `try?` turns that into `nil`, and the route
saves with `coordinateCount = 5000` beside an empty polyline. The import reports success.
Verified: `Double("nan")` returns `.nan` and `Double("1e999")` returns `.infinity`, so a
GPX only has to *contain* those strings — nothing was validating them.

The same NaN also poisoned everything derived: `Swift.min(.nan, 5.0)` is `.nan`, so one bad
point makes NaN of all four stored bounding-box columns, and a NaN column compares false
against every `#Predicate` viewport test — the route simply stops existing on the map.

**Rules.**
- Copying a `try?` accessor pattern copies its failure mode too. Before reusing one, ask what
  the encoder actually rejects. JSON rejects NaN and infinity by default.
- Validate at the parse boundary, not at the store boundary. The fix was a `isFinite` +
  range guard in `GPXRouteImporter`, which fixed every downstream consumer at once; guarding
  in `Route.init` would have left the same trap for the next reader of the parsed value.
- A getter that coalesces to `[]` and a setter that swallows an error will make corrupt data
  look like absent data. Prefer get-only when nothing legitimately writes.

---

## A framework's reference implementation can still be the wrong choice (2026-09-08, #191)

**What happened.** `RouteGeometry.distanceMeters` used `CLLocation.distance(from:)`, chosen
because it is the ellipsoidal reference and "there is no formula to get wrong." A test
asserting that two code paths agree on the same input then failed: the same polyline
measured 5709.9076 m and 5709.8369 m in one test process. A 200-call loop in the simulator
found only one value, and macOS was stable — so it is intermittent, ~1.2e-5 relative, the
signature of a spherical model standing in until something in CoreLocation finishes loading.

**Why that mattered more than accuracy.** The value is *stored*, shown to the rider, and
filtered on. Two routes with identical geometry getting different distances depending on
when they were imported is not a rounding difference, and no caller can defend against it.
Replaced with the local-radius-of-curvature formula on the WGS84 ellipsoid: pure arithmetic,
matching `CLLocation` to 0.04 m over a 100 km route and hitting the published 110,574.4 m
meridian-degree figure exactly.

**Rules.**
- For a value you persist, reproducibility is a hard requirement, ranking above provenance.
  Ask "will this give the same answer next month" before "is this the reference".
- A test that asserts *two independent paths agree* catches what neither path's own tests
  can — both were self-consistent and both matched their own expectations.
- When a numeric test fails by a suspiciously small relative amount, get the two values
  before theorising. 1.2e-5 named the cause (sphere vs ellipsoid); "flaky test" would not have.

---

## A fixture that cannot express the failure is not evidence (2026-09-08, #192)

**What happened.** The geometry half of `TurnDerivation` was planned as a windowed bearing delta —
compare the heading 20 m before a point with the heading 20 m after, call the difference the turn
angle — and I validated it by simulating every acceptance criterion before writing the plan. All
seven passed, with measured numbers. The plan was approved on that evidence.

Every one of those fixtures used a **sharp vertex**: two straight legs meeting at a point. A sharp
vertex is precisely the one case where "curvature over a window" and "turn angle" give the same
answer. Real exporters round their corners. On an arc the two diverge completely: the same 90° corner
measured 85° at a 5 m drawn radius, 43° at 28 m, and **nothing at 30 m or wider**, where it fell
under the 40° threshold and vanished. The suite would have stayed green while the feature missed most
real corners, with the answer depending on which planning tool wrote the file.

A second defect the fixtures could not see: candidates were grouped by *array index adjacency*, which
is only road adjacency if the file is densely sampled. Every fixture used 5 m spacing. At the 150–200
m spacing real decimated GPX uses, two corners 200 m apart landed on consecutive indices and merged.

**Rules.**
- Simulating the ACs is not the same as testing the design. Ask what the fixture *cannot* express,
  and build one that can, before treating a green run as evidence. Here the missing fixture was
  one parameter wide: a constant-radius arc.
- When a measurement is a proxy for the quantity you actually want, name the difference out loud and
  test across the axis that separates them. "Curvature over a window" is not "turn angle", and the
  axis that separates them is drawn corner radius.
- A quantity worth reporting should not also be the gate. Splitting "how far does the road turn"
  (accumulated sum) from "sharply enough to matter" (span/radius) made both testable and removed the
  exporter-dependence entirely.
- Sampling-density independence is a property worth asserting directly. Two of the defects here were
  really one bug — reasoning about array indices as if they were distances — and a test that runs the
  same corner at 0.5 m through 100 m spacing catches that whole class in one line.

---

## Deleting state because a snapshot was blank (2026-09-09, #193 review)

**What happened.** Two snapshot references came out blank. The cause was that a snapshot
captures after `.task` *sends* but before its effect lands, so `isLoading` was true and the
`ContentUnavailableView` branch never rendered. I concluded the field was unnecessary for a
local SwiftData read and deleted it, and reported that as a simplification.

It was not. The flag was set at the wrong *time*, not for the wrong *reason*. Removing it
collapsed three distinct screens into one: "not read yet", "read came back empty", and "the
read failed" all became `routes.isEmpty`. The last is the damaging one — after a failed read
the rider saw "No Routes / Import a route from the Files app" sitting behind a "Couldn't Load
Routes" alert, telling them their saved routes were gone when the store was untouched. A code
review caught it. The fix was `hasLoaded`, set only on success: one field, three screens.

**Rules.**
- A test symptom tells you *when* state is wrong, not *whether* it should exist. Before
  deleting a field to make a test pass, enumerate the screens it distinguishes and check each
  one still has a distinct rendering without it.
- "Simplification" that removes a distinction is a behaviour change. Say which cases collapse
  into which, and if one of them is an error path, that is the one to check first.
- A loading flag around a *failed* read is not about latency. Even when the read is instant,
  empty-because-nothing-is-saved and empty-because-the-read-failed must not render the same.

**Also, from the same review.** Two more of the same shape: I trusted a `?? .xml` fallback
that could never fire (`UTType(filenameExtension:)` returns non-nil even when it resolves to
a useless dynamic type), and validated a cache with `polylines.count != routes.count` when
the loader deliberately omits failures — so a count could match while holding entirely the
wrong keys. **Compare identities, not cardinalities**, and check that a fallback's guard can
actually be reached before writing the comment that says it recovers.

**And.** `concurrentImportIsRefused` passed alone and failed under suite load: it raced two
sends against a 200 ms sleep in a mock. Assert the *guard* (seed `isImporting = true`, send,
expect nothing), not the race that motivates it — same class as the `skipInFlightEffects`
entry above.

---

## Use the framework's navigation, not a workaround for the issue's wording (2026-09-10, #195)

**What happened.** #195 said to follow the S11 pattern: "a plain `Scope` behind a `NavigationLink`". S11 works
because Sensors is a single screen. S20 is a different screen for each route, and a plain link can't tell a
reducer which route was tapped. I didn't say that and reach for TCA's stack navigation. Instead I offered three
ways to bend the design around the issue's wording:
- `Button` rows with a hand-drawn chevron, driving `navigationDestination(isPresented:)`
- `@Presents`
- the literal link, with a stale first frame

I followed those with a view-owned `@State` Store modelled on the Rides tab. Brian: "Those options seemed to be
horrible", then "Let's use correct TCA patterns to do the navigation, and not try to work around it. This means
that the scope will probably have to increase for this issue."

**Why I was wrong.**
- The prescription existed to protect one thing: state that outlives the view (the `@Presents`/`onDisappear`
  entry above). I treated its *mechanism* as the constraint instead.
- The Rides tab I cited as precedent is prototype code. It has no reducer, calls `@Query` and
  `modelContext.delete` in the view, and shows fabricated detail data. Its shape was not evidence of a pattern.

**Rules.**
- When an issue's prescribed pattern doesn't fit, say so and use the framework's idiomatic tool. For a TCA
  drill-down that is `StackState` + `NavigationLink(state:)` + delegate actions. State the scope it adds rather
  than offering a menu of contortions.
- Before following a prescription to the letter, check what it is *for*, and satisfy that.
- Code that bypasses the architecture is not precedent. Before citing a sibling as "how we do it here", check
  that it is built the way the codebase's own rules say.
