# SwiftData migration crash (#186 regression) — fix + regression test

Branch: `fix/swiftdata-migration-defaults`

## Diagnosis (done)
Launch crash on device: `SwiftDataStack.swift:37` fatalError.
CoreData 134110 — `entity=Ride, attribute=cadenceSampleCount, reason=Validation
error missing attribute values on mandatory destination attribute`.
The five attributes added in #175 (`isAutoPaused`, `zeroSpeedSeconds`,
`speedSampleCount`, `hrSampleCount`, `cadenceSampleCount`) are non-optional and
initialized only in `init`, so SwiftData emits them as mandatory-with-no-default
and lightweight migration refuses any store written before #186.

## Plan
- [x] Add declaration-site defaults to the five #175 attributes on `Ride`
- [x] Hoist `Schema([Ride.self, VehiclePassEvent.self])` to `SwiftDataStack.schema`
      so the test asserts against the same schema production loads
- [x] Regression test: write a store with the pre-#175 `Ride` shape, reopen it
      with the current schema, assert it loads and backfills the new attributes
- [x] Build + run the full CyclometerTests suite

## Review

**Changed**
- `Models/Ride.swift` — declaration-site defaults on the five #175 attributes
  (`= false` / `= 0`), plus a type-level note explaining why they can't be left
  to `init` alone.
- `Clients/Persistence/SwiftDataStack.swift` — `Schema([Ride.self,
  VehiclePassEvent.self])` hoisted to `static let schema`, so the test opens a
  store against the same schema production loads instead of a copy that drifts.
- `CyclometerTests/Models/RideSchemaMigrationTests.swift` — new. Holds the
  pre-#175 `Ride` as a test-only `@Model` (readable/diffable, unlike a
  checked-in binary `.store`), writes a store with it, then cold-opens that
  store with the current schema and asserts old data survives and the new
  attributes are backfilled. A second test proves the migrated store is
  writable, not just readable.

**Verification**
- Both new tests fail without the fix, with `SwiftDataError.loadIssueModelContainer` —
  the same error the device crash logged. Confirmed by reverting the defaults,
  re-running, and restoring.
- Full `CyclometerTests`: 777 passed, 0 failed, 0 skipped (iPhone 17 Pro, iOS 26.5).

**Guard against recurrence**
The migration test pins the oldest supported on-disk shape, so *any* future
non-optional attribute added to `Ride` without a declaration-site default fails
CI — not just the original five.

**Not done (flagged, needs its own issue)**
`SwiftDataStack.swift:37` and `CoreDataStack.swift:34` still `fatalError` on
store-load failure. Fine pre-release; post-ship a bad migration bricks the app
with no recovery path and no way to salvage ride data.
