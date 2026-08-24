# Issue #108 — [M10] Unit and snapshot tests

Branch `test/108-m10-unit-and-snapshot-tests`, from `main`. Milestone M10, Wave 5 — "strictly last."

Spec: TCA.md §Testing.

## Finding: most of the stated scope was already done

Every feature issue #108 depends on (#93–#107) landed before it, and several of those PRs pulled
the tests #108's issue body describes forward rather than deferring them:

- **`DeviceManagementFeature`'s full behavioural matrix** (discovery merge, pair, unpair, role
  reassignment, replace-or-cancel incl. partial-collision and zero-role) — `DeviceManagementFeatureTests.swift`,
  ~57 `@Test`s, landed with #100.
- **Write-ordering on a single interleaved call log** — same file, the `ClientCall`/`ScanCall`
  `LockIsolated` pattern, with explicit ordering assertions.
- **Onboarding gating** (fresh install, mid-flow relaunch, completed, permission revoked after
  completion) — all four named explicitly in `AppOnboardingTests.swift`.
- **S11 and S02 snapshots** — `DeviceManagementSnapshotTests.swift` and `SensorPairingSnapshotTests.swift`
  already exist at 402×874pt, light+dark.

Two real gaps remained: `AppPreferencesTests.jsonRoundTrip` didn't exercise `hasCompletedOnboarding`/
`hasCompletedWelcomeStep` (added by #105, after that test was last touched — both stayed at their
shared `false` default on both sides of the round-trip), and no snapshot suite existed for S01
(`WelcomeView`) or S12 (`SettingsView`).

**`shouldSetDoNotDisturb` criterion dropped, deliberately (Brian's call).** The issue text asks for
"rejection of a document carrying `shouldSetDoNotDisturb`." That field never reached `AppPreferences`
— it lived only in ephemeral `SettingsFeature` UI state, deleted 2026-08-14 before ever being wired to
persistence. DataModel.md §9 documents decoding as lenient by design, and a prior commit (`6b0b2f3`)
explicitly rejected a "strict decode" as a footgun: one stray key, including one written by a newer
build after a downgrade, would wipe the whole preferences document. `RiderProfileTests` already has
the equivalent test asserting the opposite of "rejection" (`unrecognisedKeyIsIgnored`). Given the
criterion contradicts the shipped design, it was skipped rather than worked around.

## Tasks

- [x] 1. `AppPreferencesTests.jsonRoundTrip` — set `hasCompletedOnboarding`/`hasCompletedWelcomeStep`
      away from default alongside every other field
- [x] 2. `WelcomeSnapshotTests.swift` (S01) — needs-permissions, all-granted, denied-blocks-next
      (the third case is new: neither existing `WelcomeView` `#Preview` exercises
      `PermissionStatusOval`'s red-X branch)
- [x] 3. `SettingsSnapshotTests.swift` (S12) — default state, custom wheel circumference (exercises
      the conditional manual-entry field and a nonzero Sensors count)
- [x] 4. CI skip-list entries for both new suites in `.github/workflows/tests.yml`
- [x] 5. Record references, inspect them (not blank), verify a second run is stable
- [x] 6. Full local suite green with all nine snapshot suites skipped, matching CI's exact invocation

## Review

**Scope was almost entirely test-debt cleanup, not new coverage.** The issue's five bullets read as
though #108 owns the whole M10 behavioural surface; in practice four of the five were already
satisfied by the time this branch was cut, because the feature PRs that landed them (#98, #99, #100,
#105) wrote the matrix as they went rather than leaving it for the "strictly last" wave. What remained
was two round-trip fields nobody had gone back to touch, and two screens without a snapshot suite.

**A latent locale dependency in the new S12 fixtures.** `SettingsView` renders `preferredUnit`, and
the state builder didn't pin it — leaving it on `AppPreferences.preferredUnit`'s `.system` fallback,
which reads `Locale.current` with no seam to stub (the same gap `AppPreferencesTests` works around by
comparing against `UnitSystem.system` rather than a literal). For a *logic* assertion that's fine; for
a *pixel* reference it isn't — a machine with a different locale would record a different image, which
is exactly the class of thing #108's own acceptance criterion ("no test depends on the host machine's
locale") rules out. Caught before committing by asking what would change if this ran on a non-US
machine, not by a failure. Fixed by pinning `preferredUnit = .imperial` in the fixture, same as the
wheel circumference and paired sensors are already pinned. Re-recorded; the reference PNGs came out
byte-identical to the un-pinned first pass, confirming the fix changes what's guaranteed, not what's
rendered on this machine.

**`WelcomeFeature.State`'s plain memberwise init made the snapshot harness simpler than the reducer
tests' own pattern might suggest.** Rather than mocking `permissionsClient` and letting `.task`'s
`AsyncStream` subscription populate `permissionStates` before capture — a race between an async
effect and a synchronous `UIHostingController` render, the exact shape of bug `lessons.md` already
flags for a different suite — `WelcomeFeature.State(permissionStates:)` is constructed directly with
the desired values, same bypass `DeviceManagementFeature.State(sources:)` already uses. The mock's
`initial` values still match what's seeded, so the view's live `.task` is a no-op rather than a
liability.

**Verification.** Recorded all 10 new reference images and looked at four of them directly (light and
dark for one `WelcomeSnapshotTests` case, both `SettingsSnapshotTests` cases) — none blank, all render
the intended state. Second run of the three touched suites green. Full local `CyclometerTests` run,
matching CI's `-only-testing`/`-skip-testing` invocation exactly (including the two new skip entries):
**584 passed, 0 failed.**
