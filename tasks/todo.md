# tasks/todo.md — Xcode 27 + TCA 1.26.2

Branch: `chore/xcode-27` (off main, with Brian's 7816f55 "Xcode upgrade" cherry-picked) · Plan: `~/.claude/plans/tender-watching-cat.md`

Decisions (Brian, planning):
- CI moves to the `xcode-27` preview label.
- This lands as its own PR off main.
- "Complete install" means what this iPhone app can use, so no tvOS/visionOS runtimes.

Why it's needed: with TCA 1.25.5 the project doesn't build on Xcode 27.
- TCA's own `NavigationStack+Observation.swift:149` fails with "cannot form key path to main actor-isolated subscript".
- TCA 1.26.0 (#3931, "Xcode 27 Beta 1 Support") changed exactly that file.

## 1. Branch

- [x] Stash the Xcode-written `traits = ( );`, branch off `origin/main`, cherry-pick 7816f55, then pop

## 2. Xcode 27 install

- [x] iPhone 17 Pro on iOS 27.0 (`3200CB84`). Xcode had created 18 Pro/18 Pro Max there instead.
- [x] MetalToolchain component: 27A266a, `Status: installed` (839 MB)
- [x] `-runFirstLaunch -checkForNewerComponents`: "No new updates for 27A266a"

## 3. TCA 1.25.5 → 1.26.2

- [x] pbxproj `minimumVersion` set to 1.26.2
- [x] Resolve: swift-issue-reporting 2.1.0 replaces xctest-dynamic-overlay, and snapshot-testing stays at 1.19.2
  - A plain re-resolve fails with `multiple packages ('swift-issue-reporting', 'xctest-dynamic-overlay') declare targets
    with a conflicting name: 'IssueReporting'`. Xcode keeps the old transitive pins, which still point at the renamed repo.
  - Pruning `Package.resolved` alone didn't help either. The DerivedData package state from the failed resolve re-supplied
    the old versions.
  - Fix: prune to just the snapshot-testing pin, then resolve against clean package state. The result matches the
    no-pins probe exactly.

## 4. CI

- [x] `tests.yml`: `runs-on: xcode-27`

## 5. Docs and memory

- [x] CLAUDE.md: requires Xcode 27
- [x] Project memory: `xcode27-tca-toolchain.md`

## 5b. Minimum target → iOS 27.0 (Brian, mid-task)

- [x] `IPHONEOS_DEPLOYMENT_TARGET` 26.5 → 27.0, in all four configs
- [x] Docs that state the minimum:
  - CLAUDE.md
  - PRD.md: the header, Resolved Decisions (which records the raise) and §Platform
  - DataModel.md
  - UX.md §typography
  - Left as-is: UX.md's "requires iOS 26" API notes, which are still true, and BootstrapPlan.md, which is historical.
- [x] `recordingStatePredicateThrowsAtRuntime` renamed `recordingStatePredicateFiltersOnCapturedEnum`. It now pins iOS 27's fixed
  behaviour, comparing IDs with an active ride present.
- [x] Build at the 27 target: 248 files recompiled, 0 errors. Two warnings appear only at a 27 minimum, both in `AudioClient.swift`:
  `AVAudioPlayerNode.play()` at :319 and `AVAudioEngine.connect(_:to:format:)` at :347. That's the alert-tone path, left for a
  follow-up.
- [x] CI skip list: added `PaceWidgetSnapshotTests` and `SensorBatteryLabelSnapshotTests`, which had been missed.
  - The workflow's stated policy excludes snapshot suites.
  - CI's iOS 27.0 runtime comes from a beta Xcode, so it won't match pixels recorded locally.
- Found by the iOS 27 snapshots, and pre-existing: on Routes' **no-matches** screen, the "0 of 4" + chips row renders flush against
  x=0. `RoutesView.swift:49-53` stacks `filterChips` in a bare `VStack` with no horizontal inset, while the populated list gets its
  inset from its section header.
  - iOS 26's snapshot drew that area blank, so nobody saw it. It needs a follow-up; this change doesn't fix it.
- [x] Re-record snapshots on iOS 27.0, since an iOS 27-minimum app can't run on 26.5.
  - Looked at the biggest diffs before recording:
    - The toolbar and large title now render, where iOS 26 drew a blank band.
    - Inset-grouped lists sit about 10 pt higher.
    - `ContentUnavailableView` descriptions wrap onto a second line.
  - Recorded with `TEST_RUNNER_SNAPSHOT_TESTING_RECORD=failed`: 112 PNGs rewritten, 0 new files, and none blank (the smallest
    new/old size ratio is 0.97).
  - The verify run, with recording off: **1094/1094 passed**, 0 skipped, on the iPhone 17 Pro with iOS 27.0.
- Follow-up, not part of this change: AppView's Swift-side filter and RidePersistenceActor's `endedAt` proxies can become plain
  `recordingState` predicates, and their comments now describe a fault that no supported OS has.

## 6. Verify

- [x] Build: zero errors. The 43 unique project-source warnings are identical, file:line for file:line, to main's Xcode 26.6 /
  TCA 1.25.5 CI build (run 34883838666). The upgrade adds none and removes none.
- [x] Full suite on the iOS 26.5 iPhone 17 Pro (`42B5213B`): **1094/1094 passed**, 0 failed, 0 skipped
  - Swift Testing ran 1021 tests in 96 suites, exactly main's CI count.
  - XCTest ran the other 73: every snapshot test, across 14 suites.
  - Found along the way, and pre-existing: `PaceWidgetSnapshotTests` (4) and `SensorBatteryLabelSnapshotTests` (3) aren't in
    CI's skip list, so CI runs pixel snapshots too.
- [x] Full suite on the iOS 27.0 iPhone 17 Pro (the `name=iPhone 17 Pro` destination resolves to 27.0, 24A434):
  **1020/1094 passed**. The 74 failures are all 73 snapshot tests plus one Swift Testing test.
  - `PersistenceClientTests.recordingStatePredicateThrowsAtRuntime`: iOS 27's SwiftData **fixed** captured-enum
    `#Predicate`s. A throwaway probe (1 active + 1 ended ride), run on both OSes and then deleted, showed:
    - 26.5: `== .active`, `.ended` and `.paused` all throw `unsupportedPredicate`.
    - 27.0: they return `[active]`, `[ended]` and `[]`, all correct.
    - The Swift-side filter must stay while the deployment target is 26.5. The test's premise now holds only below iOS 27.
  - Snapshots: none of the 112 images is identical, and no sizes changed. Differing-pixel counts per image: 72 under 0.2%,
    22 at 0.2–1%, 10 at 1–5%, and 9 at 5% or more. The worst are `RoutesSnapshotTests.testNoMatchingRoutes` (25%), the
    StartSheet route rows (11–14%), and the Routes empty/populated and StartSheet picker states.
  - CI impact: `PaceWidgetSnapshotTests` and `SensorBatteryLabelSnapshotTests` (not in CI's skip list) and the predicate
    test all fail on iOS 27, so `runs-on: xcode-27` as it stands would be red.
- [x] Diff review. Only the intended files changed, and the throwaway probe was deleted: 0 untracked files.
- [x] Commit, push and PR: `c6cd2a2` on `chore/xcode-27`, PR #236

## 7. AudioClient iOS 27 APIs (follow-up 2, a separate commit on #236)

- [x] `engine.connect(_:to:format:)` → `try engine.connectNode(_:to:format:)`. Attach and connect are now checked separately,
  via `player.engine` and `outputConnectionPoints`, so a failed connect gets retried on the next call. Before, the guard would
  step over it and the player would stay silent.
- [x] `player.play()` → `try player.playAudio()`, moved to before `scheduleBuffer`.
  - A failed start then leaves no completion pending, and the catch resumes the continuation exactly once.
  - `sounding` is cleared after `stop()`, so a failed start doesn't leave turn tones yielding to a stopped Warning.
- [x] Throwaway live-audio probe on the iOS 27 simulator, since deleted:
  - Returns: Warning 0.567 s, Danger 0.640 s, turn-left 0.558 s, and All Clear 1.18 s (the first call, including engine setup).
    Each is its tone length plus output latency.
  - A Danger cut off by a Warning 100 ms later: both calls returned at 0.652 s.
  - Nothing in the `audio` log, so no call took the error path.
- [x] Warnings: 45 → 43. Exactly the two `AudioClient` deprecations are gone, and nothing is new.
- [x] Full suite on iOS 27.0: **1094/1094 passed**, with only `AudioClient.swift` recompiled
- [x] Commit, push to #236, and update the PR body

## Review

**Outcome.**
- Xcode 27.0 (27A266a) is fully installed, TCA is on 1.26.2, the minimum target is iOS 27.0, and CI runs on `xcode-27`.
- Locally, on the iPhone 17 Pro with iOS 27.0: **1094/1094 passed** with both commits, made up of 1021 Swift Testing tests in 96
  suites and 73 XCTest snapshot tests.
- No warnings were added. The two iOS 27 audio deprecations that the 27.0 target surfaced are fixed in §7.

**CI:** the first `xcode-27` run (34983789777, on `c6cd2a2`) passed on Xcode 27.0 beta 6 (27A5252f).
- Swift Testing ran 1021 tests in 96 suites, the same count as locally. So `recordingStatePredicateFiltersOnCapturedEnum` holds on the
  runner's beta iOS 27.0 runtime too.
- XCTest executed 0 tests, because all 14 snapshot suites are skipped. `main`'s CI had been running 7.

**Follow-ups, not part of this change:**
1. Routes' no-matches chips row sits flush against x=0 (`RoutesView.swift:49-53`). It's pre-existing, exposed by the iOS 27
   snapshots.
2. Done in §7: the `AudioClient` iOS 27 deprecations, as the second commit on #236.
3. AppView's Swift-side filter and RidePersistenceActor's `endedAt` proxies can become `recordingState` predicates. Their comments
   describe a fault that no supported OS has any more.
4. feat/199 (#235) is still on TCA 1.25.5, so it doesn't build on Xcode 27. Rebase it once this merges; the cherry-picked 7816f55
   drops out.
5. Optional: the iOS 26.3–26.5 simulator runtimes can no longer run this app.

**Caught along the way:**
- A plain re-resolve can't cross the xctest-dynamic-overlay → swift-issue-reporting rename. It needs pruned pins and clean package
  state. This is in memory as `xcode27-tca-toolchain`.
- I first called the snapshot drift sub-visual, from two eyeballed pairs and the *tail* of a worst-first list. The summary line
  showed a 25% diff. Read the worst rows before characterising a diff.
