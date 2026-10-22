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
