# Issue #99 — Replace-or-cancel when a role is already occupied

Branch `feat/99-replace-or-cancel`, from `main` (#120 merged as `1e733c1`). Milestone M10, Wave 2.

`DeviceManagementFeature.apply(_:to:in:)` silently evicts the incumbent when a claimed role is already
held — `removeAll { $0.isCSC && ($0.peripheralID == id || roles.contains($0.role)) }`. BLE.md §5.0 step 4
says that decision belongs to the rider.

Spec: UX.md §S11 (One Sensor Per Role — Replace or Cancel), BLE.md §5.0 step 4, DataModel.md §3.7.
Note the "§1.3" in the M10 issue footers is a *document version number*, not a section.

## Decisions (user-approved plan)

- `AlertState` on a separate `.alert` modifier, not a second `ConfirmationDialogState` — a destructive
  binary confirm is alert-shaped, and a distinct modifier avoids the dialog→dialog double-presentation
  failure while the role sheet is still dismissing.
- Copy: single collision uses the spec string verbatim as the title, no message. Two colliding roles use a
  short title plus an itemised message, one line per displaced role. Title is "Replace two sensors?" unless
  one combo holds both, where it names that sensor instead.
- Incumbent names come from `AppPreferences.pairedSensor(for:)?.displayName`, not the live device list —
  an out-of-range incumbent appears on no discovery stream.
- No redundant incumbent `setRoles` call: `BLECSCClient.setRoles` already moves the role between both
  peripherals inside one lock.

## Tasks

- [x] 1. `collisionAlert` presentation slot + `CollisionChoice` action
- [x] 2. `commit(_:to:in:)` gate and `incumbents(of:excluding:in:)`
- [x] 3. `collisionAlert(for:roles:incumbents:)` copy builder
- [x] 4. Reducer wiring: both pairing paths through `commit`, folded dismiss, `.ifLet`
- [x] 5. `.alert` modifier in `DeviceManagementView`
- [x] 6. Update `roleMovesBetweenSensors` and `reassignmentPushesAssignmentsFirst`
- [x] 7. New tests — 11: the plan's 9, plus the one-combo title variant and the clobber regression
- [x] 8. `assets/BLE.md` §12 acceptance rows
- [x] 9. Build + full local suite green — **520 passed, 0 failed, 0 skipped**

## Review

**The client already did half the job.** `BLECSCClient.setRoles` (`BLECSCClient.swift:662`) subtracts the
claimed roles from every other slot inside one lock, keeps an incumbent that retains a role, and removes +
disconnects one left holding nothing. Acceptance criteria 3 and 4 were therefore already satisfied by shipped
code, and AC 6's "setRoles for both peripherals" is one call, not two — a second call naming the incumbent
would have been dead code. The genuine delta was the confirmation gate and the incumbent naming, both in the
feature. No client changes.

**Bug found and fixed during self-review, not by a failing test.** `pendingPairing` now has to survive into
the collision alert — it is the only thing that tells Cancel to release an in-flight peripheral. But
`.devicesUpdated` guards its interrogation branch on exactly that field, and the screen re-broadcasts every
10s via the sweep timer. So a few seconds after answering the role sheet, the rider's collision alert was
being replaced by the role sheet again. Fixed by also guarding on "no prompt currently presented";
`deviceUpdateDoesNotClobberTheConfirmation` is the regression test, and it was verified to fail with the
guard removed rather than merely assumed to cover it.

**Copy departures from the plan, both deliberate:**
- Nil-name fallback is "an unnamed sensor", not the role sheet's "This sensor". This copy always names the
  incumbent mid-clause — "Speed is already assigned to This sensor." is not a sentence.
- The two-role title has a second variant. "Replace two sensors?" is false when one combo holds both roles,
  so that case reads "Replace Wahoo RPM?" instead. Keyed on distinct `peripheralID`, not on name.

**One thing tests cannot prove.** The role sheet dismissing while the alert is raised is a SwiftUI
presentation race, and a `TestStore` only sees the state. Separate `.confirmationDialog` / `.alert` modifiers
are the mitigation; the combo path still wants a manual pass in the simulator.
