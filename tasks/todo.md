# tasks/todo.md — #198 Turn tones: resolve OQA6 with distinct turn cues

Branch: `feat/198-turn-tones` · Milestone M8 · Plan: `~/.claude/plans/wild-exploring-swan.md`

Decisions (Brian, planning): a third, distinct U-turn tone; a turn cue is suppressed through L3 or while a Warning
sounds, and otherwise plays — including through a sustained L2.

## 1. Tones — `AudioClient.swift`

- [x] `ToneKind`: `.turnLeft` / `.turnRight` / `.uTurn` segments + volume; `init(turn:)`; `duration`; doc comments
- [x] `AudioClient.playTurn(Maneuver.Direction)`: live + test values; header comment

## 2. Reducers

- [x] `NavigationFeature`: `.delegate(.turnAnnounced(direction))`, sent with the announcement
- [x] `AlertOrchestratorFeature`: `.turnAnnounced` — held at L3 or within the Warning's duration of a caution
      dispatch; never touches state; `alerts` logger (`turn tone — <dir>` / `turn tone held — <reason>`). Default task
      priority, not the radar effects' `.userInteractive`: that is deprecated, and a turn has no 200 ms budget
- [x] `ActiveRideFeature`: navigation delegate → `.alertOrchestrator(.turnAnnounced)`

## 3. Tests

- [x] `AudioToneRendererTests`: durations; pairwise distinct; contour; pitch band + no shared radar pitch; `init(turn:)`
- [x] `AlertOrchestratorFeatureTests`: L0, L1, Warning window both sides, sustained L2, L3 + loop unaffected
- [x] `NavigationFeatureTests`: delegate carries the direction (left/right/U-turn); rejoin re-sends
- [x] `ActiveRideFeatureTests`: a turn reaches the speaker exactly once, level untouched; silent at L3

## 4. Specs

- [x] `Audio.md` v0.2: overview table, Turn Tones section, §3, §4, Turn Cues and Radar, ACs, OQA6 resolved
- [x] `PRD.md` §8.6 turn-notification line

## 5. Verify

- [x] Build clean — no warnings from changed files. First build: the one new warning was the turn tone's deprecated
      `.userInteractive`, since removed. The fresh drive build (`.build/198/dd-drive`) has only pre-existing ones: the
      radar effects' four `.userInteractive`, and the `fixedNow` warnings in `ActiveRideFeatureTests`, which stop at
      line 2457, before this branch's insert, and blame to `be13d330` on main
- [x] Targeted suites: **198 tests in 19 suites passed**; all 15 new test functions found by display name, the
      parameterized one with its 3 cases. With `-parallel-testing-enabled NO` the log carries Swift Testing's own
      `✔ Test "…"` lines, so a `^Test case '` count reads 0 — caught by the count check, not trusted
- [x] Revert checks (a)–(h), scripted (`scratchpad/revert-checks.sh`), each rebuilt in `.build/198/dd-revert` with
      caching off and run over the 5 turn-tone suites (61 tests). Every one failed exactly its predicted guards and
      nothing else; source diff hash `b39b4a28…` identical before and after:
      (a) no gate → held-through-L3, Warning window, parent L3;
      (b) Warning clause removed → Warning window only;
      (c) the issue's `< .caution` rule → Warning window only (its sustained-L2 half);
      (d) a turn sets the level → all three orchestrator tests + both parent tests;
      (e) no parent forward → both parent tests;
      (f) Turn Left given Turn Right's notes → distinctness, contour;
      (g) U-turn → left tone → the mapping test;
      (h) no delegate → both navigation tone tests + both parent tests
- [x] Ear check: 7 WAVs rendered by the real `ToneRenderer` at each tone's volume (sizes match 500 / 760 ms exactly),
      sent to Brian; throwaway test deleted. **Brian: good for now** (2026-09-14). Any later tuning changes `ToneKind`
      and Audio.md together
- [x] Sim drive (`.build/198/drive198.sh`, the #197 kit against a fresh `.build/198/dd-drive`, iPhone 17 Pro iOS 26.5,
      clean install, turn-by-turn on, 800 m N then right, `simctl location` at 10 m/s). UI test exit 0 after 227 s.
      The app's own log:
      - route loaded (1 turn over 1,200 m) → on route at 0 m
      - **turn 0 announced 95.6 m out (lead 100 m)**, then **`turn tone — right` 6 ms later**
      - calibration gate shut, then open 11 s later as the turn was made → route complete
      - zero `audio` log lines, so no session or engine setup failure
      - the only fault is onboarding's `ifLet` at `AppFeature.swift:294`, already recorded as pre-existing in #197
      The built app was checked for the new code first: `turn tone`, `radar at L3` and `Warning sounding` are in it.
      Both throwaway tests deleted before the final build
- Aside: the final build first failed to find its destination. `65732455` runs iOS 26.3 and `73EBBB62` 26.4, both
  below the app's 26.5 deployment target, so `42B5213B` is the only simulator that can run it
- [x] Full `CyclometerTests`, from the fresh throwaway-free build (`.build/198/dd-final`, caching off), parallel on,
      after uninstalling the drive's app. The xcresult summary: **1,093 / 1,093 passed**, 0 failed, 0 skipped. That is
      exactly #197's 1,078 plus the 15 new test functions. Every new test is in the log by name, and no throwaway ran.
      The log shows 1,092 distinct names; one line lost its prefix to interleaved clone output, as in #197
- [x] Commit + PR: `8725bb6`, #233
- [ ] #202 comment on Brian's go-ahead

## 6. Review fix — `/code-review` on #233

A turn tone's `play()` and a radar tone's reach the engine's lock in whatever order their setup finishes. A turn
announced a moment before an L3 jump could stop the first Danger burst (the next then came 0.8 s late), or leave
Danger at the turn's 0.8 volume.

- [x] `ToneKind.yields(to:)`: a turn tone gives way to a sounding Warning or Danger; nothing else gives way
- [x] `AudioEngineState`: a `sounding` deadline; the check and `player.volume` inside the lock; a held tone is logged
- [x] `turnTone` doc comment; Audio.md "Turn Cues and Radar"; PRD §8.6's Audio.md section name
- [x] Pair test in `ToneKindTurnTests` passes: tone suites 25 tests in 3 suites, the new one by name
- [x] Fresh build (`.build/233/dd`, caching off), no new warnings. Touched files carry only the radar effects' four
      pre-existing `.userInteractive` deprecations, 3 lines lower for the longer doc comment
- [x] Throwaway live test (`ThrowawayTurnYieldLiveTests`) 3 / 3, each run in its own process on the live engine:
      1. Danger, a turn 100 ms in: the turn is held after 4–9 ms; Danger plays through, 640–642 ms
      2. A turn, Danger 100 ms in: the turn is cut off at 104–109 ms; Danger plays through, 641–646 ms
      3. A Warning to its end (539–544 ms), then a turn: the turn plays through, 555–567 ms
- [x] Throwaway deleted: moved to the scratchpad, never committed
- [x] Revert checks (`scratchpad/revert-233.sh`), each built fresh into its own derived data, over the tone suites and
      the live test:
      (i) no engine check → only live case 1 fails: the turn plays through (564 ms) and cuts Danger off at 110 ms;
      (j) turns give way only to Danger → only the pair test fails, once per turn tone.
      `AudioClient.swift` is byte-identical to both pre-mutation copies. The script's "HASH DIFFERS" is this file,
      edited mid-run 8 s after the "before" hash
- [x] Full `CyclometerTests` from a fresh, throwaway-free build (`.build/233/dd-final`, caching off):
      - CI-equivalent (serial, CI's 12 snapshot skips): **1,021 tests in 96 suites passed**, CI's 1,020 plus the pair
        test; xcresult 1,028 / 1,028, 0 failed, 0 skipped
      - parallel, 2 workers: xcresult **1,094 / 1,094 passed**, #198's 1,093 plus the pair test
      - the pair test is in both logs by name, and the throwaway in neither
      - The first attempt was killed for low memory 217 tests in, with none failed. The leftover `flake-repro`
        simulator was shut down, and both runs repeated on the same build
- [x] Commit + push to #233: `36a98ca`, CI green (1,021 tests in 96 suites); PR description gained a "Review fix"
      section

## Review

**Built.** Each turn announcement now sounds a tone: Turn Left, Turn Right or U-turn. All three step through the
same three notes, the C6 augmented triad; rising means right and falling means left, and the U-turn goes up and back.
- **Where the tone comes from.** Navigation sends a delegate with each announcement, and the orchestrator plays the
  tone.
- **Radar keeps the speaker.** The tone is held throughout L3, and for the Warning's 480 ms after an L2 alert fires.
  Otherwise it plays, through a sustained L2 as well.
- **The alert level is never touched.** The tone can't change the level, so the radar sidebar and calibration
  suspension are unaffected.
- **Specs.** Audio.md v0.2 resolves OQA6.

**Verified.**
- Targeted run: 198 tests in 19 suites passed.
- Revert checks: 8 scripted mutations, each failing exactly its predicted guards, with the source restored
  byte-for-byte.
- Sim drive: the tone logged 6 ms after the turn was announced, 95.6 m out.
- Full suite: 1,093 / 1,093 passed.
- Ear check: Brian says the tones are good for now.

**Deviations from the approved plan.**
- **"Turn tone", not "turn cue".** The log lines use Audio.md's section name, "Turn Tones".
- **Default task priority.** The turn tone's effect doesn't use `.userInteractive`: that API is deprecated, and a turn
  has no 200 ms budget. The radar effects keep theirs.
- **A separate overview table for the turn tones.** They don't get rows in Audio.md's radar table, because that
  table's columns are per alert level.
- **An eighth revert check, (h).** It removes the delegate; the plan had only (a)–(g).

**Review fix (`/code-review`).** A turn tone could cut off a radar tone that started at the same moment, because both
`play()` calls reach the engine's lock in whatever order their setup finishes.
- The engine now holds a turn tone while a Warning or Danger is sounding, and sets the volume under the lock.
- The fix was tested against the live engine: 3 / 3 passed, and the test fails with the check removed.
- Full suite passes, CI-style and in parallel.

**For Brian.**
- **Ear check.** Good for now. Any later tuning changes `ToneKind` and Audio.md together.
- **Flag: the All Clear interval.** Audio.md and `ToneKind` both call All Clear's A5 → D5 a minor third. It's a
  perfect fifth. Not fixed.
- **Flag: no S12 tone toggles.** None exist anywhere yet. Audio.md §4 describes them, and UX.md §S12 has no rows for
  them. Outside #198.
- **Only one simulator can run the app.** `42B5213B` (iOS 26.5) is the only iPhone 17 Pro at or above the 26.5
  deployment target; the 26.3 and 26.4 ones can't run it.
