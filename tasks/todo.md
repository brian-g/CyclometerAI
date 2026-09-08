# #212 — Radar flooded a persisted level while sensor telemetry sat on one that never persists

Branch: `fix/212-ble-log-levels`

## Diagnosis (done)
`os_log` writes `.notice` and above to the persisted store; `.info` and `.debug` live in a
memory ring buffer and are gone before anyone runs `log collect`. Every level in
`Clients/BLE/` was set against that grain.

Measured from the `.logarchive` collected after ride 2026-09-06 (untracked at the repo root),
subsystem `com.xavier.cyclometer`:

| | |
|---|---|
| Persisted entries | 4,330 |
| `VariaRadarClient` alert frames | 4,275 — 98.7%, a sustained 8.01 Hz with no gaps |
| …carrying no target | 3,710 (86% of the whole archive) |
| …carrying a target | 565, across 10 target-count transitions (5 vehicle passes) |
| Parse failures — the reason the frame log exists | 0 |
| Speed / cadence / HR samples | 0 / 0 / 0 |

`assets/BLE.md` §13.2 Q1 documented a background-execution check that reads a "continuous
stream of `speed`/`cadence`/`hr` lines" out of a collected archive. Those lines were `.info`.
The procedure could never have worked.

## What was NOT the reason
#211's cadence gap. That was a sentinel collision in the CoreData time-series store
(`mo.cadenceRPM == 0 ? nil : Int(...)`), downstream of `BLECSCClient`, and is already fixed by
`5bbed32`. The client was broadcasting `cadence 0` correctly throughout. A per-sample CSC log
would have shown a healthy stream and pointed *away* from the BLE path — useful, but not the
diagnosis the issue credits it with. This matters because it was the whole justification for
an early draft's gate bypass, which is now dropped (see below).

## Changes
- [x] `Clients/BLE/LogSampleGate.swift` — bucket-per-second gate + `Data.loggableHex`
- [x] Radar: empty frames → `.debug`; target frames and parse failures stay `.notice`
- [x] Radar: one raw frame per connection + a liveness summary a minute, replacing what the
      8 Hz stream used to prove for free
- [x] CSC: one gated `.notice` per measurement frame, merging speed and cadence, `—` for a
      role that produced no rate
- [x] HR: `bpm` raised to a gated `.notice`
- [x] All six remaining `logger.info` sites in `Clients/BLE/` raised to `.notice`
- [x] CI grep guard in `tests.yml` — the only mechanical enforcement available
- [x] `assets/BLE.md` §15 (level policy + entry budget), §13.2 Q1 correction, §12 rows, v1.4
- [x] `LogSampleGateTests` — 8 gate cases + 2 hex cases

## Dropped during implementation
A `force:` bypass on the gate, so a rate dropping out could never be the sample discarded.
`CSCCalculator.update` withholds a rate on five routine paths — priming, a stopped counter
below `zeroThreshold`, a zero time delta, re-priming after a stop, an over-cap spike — so the
emitted shape flips on every stop-and-go and the ≤1/s bound would not have held. AC4 asks for
a bounded count; the bypass would have removed the bound to solve a problem the 1 Hz gate
already solves within a second.

## Review
Full `CyclometerTests` suite green locally. No existing test observes a logger, and none
asserts a broadcast count, so the restructure is invisible to them — the speed →
wheelRevolutions → cadence broadcast order was preserved deliberately, since
`wheelRevolutionsPublished` and `cadenceOnlySensorPublishesNoRevolutions` would catch a
reordering.

Budget after the change: ~11,000 entries for a typical riding hour, ~40,000 worst case,
against ~29,000 of pure radar heartbeat and zero telemetry before it.
