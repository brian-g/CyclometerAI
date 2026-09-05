# #176 — M7 wrap-up tests: recording, GPX export, vehicle pass detection

Branch: `feat/176-m7-wrapup-tests`

## Context

AC #1 (full ride state machine) is **already satisfied** by `RideRecordingTests` shipped with
#174/#175. The real gaps are the seams between subsystems: no vehicle pass has ever reached a
GPX file in any test, and no test parses GPX output back (everything is `xml.contains`).

## Tasks

- [x] 1. `CyclometerTests/Export/GPXParsing.swift` — `ParsedGPX` + `XMLParser` delegate
- [x] 2. Round-trip test in `GPXExporterTests` (counts, per-point field presence/absence)
- [x] 3. Metadata/`<ele>`/`<time>` assertions (free once parsing exists)
- [x] 4. Pin `writeCreatesFileWithConventionalName`'s expectation formatter to en_US_POSIX + Gregorian
- [x] 5. Three-way agreement test in `RideRecordingTests` (TrackPoints ↔ VehiclePassEvents ↔ GPX)
- [x] 6. Full suite green; verify each new test can fail (revert-the-fix check)

## Review

All six tasks done. **Test-only change** — `git diff` against `Cyclometer/Cyclometer/` is empty.

**What was actually missing.** AC #1 (full ride state machine, incl. crash recovery) was already
green from #174/#175, so it was not rebuilt. The real gaps were the seams:

- No vehicle pass had ever reached a GPX file in any test. The detector was covered as a pure
  function, persistence via mocks, the exporter with hand-built DTOs — nothing joined them.
- No GPX round-trip. Every content assertion was `xml.contains(...)`; the two `XMLParser` uses
  were well-formedness only (one read just the root attributes, the other passed no delegate).

**Added:** `GPXParsing.swift` (context-aware `XMLParser` delegate — `<name>`/`<time>` each appear
in three containers, so an element stack supplies the context), a round-trip test asserting
counts and per-point field presence, metadata/`<ele>`/`<time>` coverage, an empty-ride case, and
the three-way agreement test driving
`radarTargetsUpdated → VehiclePassDetector → appendVehiclePassEvents → GPXExporter → <wpt>`.

**Constraint worth remembering:** `VehiclePassDetector` needs the vehicle tracked >= 2s *and*
absent >= 2s, both measured off `date.now`. Under this suite's usual `$0.date = .constant(...)`
a pass can never fire. The new test mutates `store.dependencies.date.now` between sends, matching
`ActiveRideFeatureVehiclePassPersistenceTests.sendOvertake`.

**Also fixed:** `writeCreatesFileWithConventionalName` built its expected filename with an
unpinned `DateFormatter`, so it would drift in lockstep with the code under a non-Gregorian
device calendar — it could not fail for the reason it existed. Now pinned to en_US_POSIX +
Gregorian, matching `GPXExporter.filenameStem`'s own pinning.

**Verification.** Full `CyclometerTests`: **771 cases, 0 failures**, snapshot suites included.
Each new test was proven capable of failing via three production mutations, then reverted:
1. emit `<gpxtpx:hr>0</gpxtpx:hr>` instead of omitting → round-trip test red.
2. never emit `<wpt>` elements → agreement test red, and the three pre-existing
   `RideRecordingTests` stayed **green** — direct evidence the gap was real.
3. disable the majority-approaching rule → agreement test red (guards overtake-vs-turn-off
   through the wiring, not just in the pure detector).

Re-confirmed the `lessons.md` trap live: `-only-testing:` with a Swift Testing *function* name
matched 0 cases and exited 0. Verified through suite-level filters instead.
