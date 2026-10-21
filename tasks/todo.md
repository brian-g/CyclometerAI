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
