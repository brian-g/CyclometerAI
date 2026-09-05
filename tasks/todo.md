# #188 — Ride-end failure paths

Branch: `fix/188-ride-end-failure-paths`

## Tasks

- [x] 1. `PendingRideEnd` model + `RideEndIntentClient` (file-backed, outside SwiftData)
- [x] 2. `ActiveRideFeature`: record intent before the writes; clear only on finalize success; log export failure
- [x] 3. `AppFeature`: at launch, close the ride out instead of resuming when intent matches
- [x] 4. `RideEndFailureTests` — all three paths + stale-marker guard
- [x] 5. Full suite green; fix proven load-bearing

## Review

**The defect.** `finalizeRide` is the only writer of `Ride.endedAt`, and `fetchResumableRide`
reads a nil `endedAt` as "still in progress". A swallowed failure therefore left a finished
ride matching the resumable predicate, so #175's crash recovery resumed a ride the rider had
already ended — restarting the recorder and reconnecting sensors, silently.

**The fix.** The durable fact "the rider ended this ride" cannot live in the store that just
failed, so it goes to a small JSON file behind `RideEndIntentClient`: written before the
ride-end writes, cleared only once `finalizeRide` actually succeeds. A marker still present
at launch means the previous finalize never landed, so `AppFeature` finalizes the ride
instead of resuming it. The marker carries the GPX URL too, so an export that succeeded
isn't orphaned on disk by a failed row write.

**Design note worth keeping.** The marker started as `@Shared(.pendingRideEnd)` in
`ActiveRideFeature.State`. That broke two exhaustive `TestStore` tests, because shared-state
mutations are state changes that every such test must assert — a permanent tax for a
persistence detail nothing renders. Moving the `@Shared` *into* the effect then failed
differently: writes made after an `await` never propagated, so the marker was recorded but
never updated or cleared. A dependency client solved both — it matches how
`persistenceClient` is already called directly from this reducer, keeps the marker out of
every exhaustive test's state contract, and is trivially controllable in tests. The two
previously-failing tests then passed **unchanged**, with no neighbouring edits.

Deliberately not folded into `PersistenceClient`: the whole point is to survive a
PersistenceClient failure.

**Verification.** Full `CyclometerTests`: **775 cases, 0 failures**. Removing the launch-time
recovery branch turns `finalizeFailureIsRecoveredAtLaunchRatherThanResumed` red while the
other three stay green.
