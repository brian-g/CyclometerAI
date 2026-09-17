# tasks/todo.md — #202 [M8] Spec reconciliation — navigation and routes

Branch: `docs/202-spec-reconciliation-navigation-routes` (off `main`)

Docs-only. No Swift changes, no build impact.

## Findings that change the issue's scope

- **CLAUDE.md has no Open Questions section at all** (`grep OQ1[0-9]` → no match in `CLAUDE.md` or
  `README.md`). That AC is already satisfied; nothing to edit. Recorded here so the AC can be ticked.
- **The M8 milestone description is already correct** — it was retitled "M8 — Navigation, Live Map &
  Routes" and already drops tribos.studio and names the Routes tab. That AC is already satisfied.
- **UX.md §S05.1's route row** — per the issue's own first comment, PR #229 already covered it, and the
  row now opens the S05.2 picker rather than being read-only. Dropped, as the comment says.
- **The issue's second comment describes `turnBanner`; the code has `turnInstruction`**, and the built
  snapping has two rules the comment omits (continuity weighting, and loop handling via `lapStartMeters`).
  TCA.md §4.14 will document what `NavigationFeature.swift` actually does, not the comment.

## Edits

### assets/PRD.md
- [x] §6 MVP bullet: "or tribos.studio integration" → GPX file import from the Files app only
- [x] §6 MVP list: add the Routes tab (S19, S20)
- [x] §6 Phase 2 list: delete the "Routes tab (S19, S20)…" bullet
- [x] §7 screen inventory: S19 and S20 `Phase 2` → `MVP`
- [x] §8.6 route-source table: `.gpx` or `.fit` → `.gpx`; `.fit` added to §15 Out of Scope
- [x] §8.6 AC: "tribos.studio route browsing and import functional" → drop (it is a Phase 2 line in an
      MVP AC list; §8.6's own 2026-08-14 note already says so)
- [x] §12 client comment: `NavigationClient // GPX import, tribos.studio routes, turn calc` → drop tribos
- [x] §12 feature tree: `NavigationFeature ← GPX import, tribos.studio, turn alerts` → drop tribos;
      `RouteFeature ← Phase 2` → `RoutesFeature ← Routes tab (S19 list/map, S20 detail)`, MVP
- [x] §12 tab table: Routes `Phase 2` → `MVP`; delete the "hidden or shows a 'Coming in a future update'
      placeholder" sentence
- [x] §13 M8 row: drop the tribos parenthetical, add the Routes tab; §13 Phase 2 paragraph: drop the
      Routes tab sentence
- [x] §15: add a `.fit` import row (out of scope — GPX only)
- [x] §2 revision history: new row 0.5.1, 2026-09-17, for this pass

### assets/TCA.md
- [x] §3 tree: `RoutesTabFeature (S19/S20 — Phase 2; "Coming Soon" in MVP)` → the built shape
      (`RoutesFeature` S19 → `RouteDetailFeature` S20, MVP)
- [x] New §4.14 `NavigationFeature` — as built: scoping into `ActiveRideFeature`, state, the four
      snapping rules, loop handling, turn timing, off-route hysteresis, `isTurnAlertActive`
- [x] §8 file layout: `Routes/ // Phase 2` → the flat built layout (`RoutesFeature`, `RoutesView`,
      `RouteDetailFeature`, `RouteDetailView`, `RouteFilter`, `RouteLibrary`, `RoutesMapCamera`)
- [x] §9: `RouteStub … Phase 2` note → "Replaced by the `Route` @Model in M8"
- [x] §10 coverage table: add `NavigationFeature` row (the ±10 m sweep across fix phases, out-and-back
      both ways, early turnaround, loops, off-route hysteresis, route end, no route, resume from
      checkpoint) and a `NavigationPipelineTests` end-to-end row
- [x] Footer version bump

### assets/DataModel.md
- [x] §2 ERD key relationships: "Phase 2: Ride gains a route: Route?" → Route is MVP, linked by
      `Ride.routeId` (FK by id, as TrackPoint/VehiclePassEvent do); the `@Relationship` stays deferred
- [x] §3.1 Ride: `routeId: UUID?`, `routeName: String?` (comment rewritten), `routeProgressMeters: Double?`
- [x] §3.1 OQDM1 callout: rewrite to the revised status
- [x] New §3.10 `Route` entity, matching `Route.swift` (scalars + `polylineData`/`cuePointsData` external
      storage, bounding-box columns, `RouteSummary`/`RouteDetail`/`RouteReference` boundary types)
- [x] §6/§3.1 note on `RideSummaryUpdate.route` (read back only; the route is written once by `createRide`)
- [x] §7 "Previous Rides for Route (S20, Phase 2)" → MVP, filtering on `Ride.routeId == routeId`
- [x] §9 schema table: `1.1 (Phase 2 — Routes)` → `1.1 (MVP — Routes, M8)`, describing what shipped
- [x] §11 OQDM1 row: partly resolved — `Route` @Model in MVP, `Ride.route: Route?` superseded by `routeId`
- [x] Footer version bump

### assets/UX.md
- [x] §S04 line 125: delete the "Coming Soon placeholder until Phase 2" sentence
- [x] §S19 purpose: rewrite so the service imports read as deferred rather than MVP sources
- [x] §S19 open question on tribos.studio sectioning: mark as Phase 2

### GitHub
- [x] Confirm the M8 milestone description needs no change (verify, then tick the AC)
- [x] PR against `main` referencing #202

## Verification
- [x] `grep -rn "tribos\|Coming Soon\|\.fit" assets/*.md README.md` — every surviving hit is
      explicitly Phase 2 / out of scope
- [x] `grep -rn "S19\|S20\|Routes tab" assets/*.md` — no remaining "Phase 2"
- [x] Walk each of the 8 ACs against the diff
- [x] Spot-check §4.14 and §3.10 line by line against `NavigationFeature.swift` / `Route.swift`

## Review

Docs only — four `.md` files, no Swift touched, nothing to build or test.

**PRD.md (14 edits).** The Routes tab, S19 and S20 are MVP in §6, the §7 screen inventory, §12's
feature tree and tab table, and §13's M8 row; the "Coming in a future update" sentence is gone.
§6's MVP bullet no longer offers tribos.studio. §8.6's Files row reads `.gpx` only and points at
§15, which gains a `.fit` row. §8.6's AC list loses its one Phase 2 line. §13's Phase 2 heading is
now "Companion & History" — no ToC anchor pointed at the old one. Revision 0.5.1.

**TCA.md (7 edits).** New §4.14 `NavigationFeature`, written from `NavigationFeature.swift` rather
than from the issue comment — see the discrepancies below. §3's tree and §8's file layout match the
built `Features/Routes/`. §9's `RouteStub` row is marked done. §10 gains three rows. v1.3.

**DataModel.md (11 edits).** New §3.10 `Route`, plus `Route` in the §2 ERD linked by `routeId` with
no `@Relationship`. §3.1 gains `routeId` and `routeProgressMeters`, and its OQDM1 callout is
rewritten with a second note on `RideSummaryUpdate.route`. §7's S20 query is the real
`RidePersistenceActor.fetchRides(routeId:)`, id-based and excluding rides still in progress. §9's
v1.1 row is MVP/M8. §11's OQDM1 is partly resolved. v1.5.

**UX.md (6 edits).** §S04's placeholder sentence gone; S19's purpose and its two answered open
questions no longer read as though the service imports are MVP. v0.8.1.

**Three ACs needed no edit, and were verified rather than assumed:**
- CLAUDE.md has no Open Questions section — `grep -n "OQ1[0-9]\|Open Question" CLAUDE.md README.md`
  is empty, so there is no stale OQ12 to fix.
- The M8 milestone description already drops tribos.studio, already names the Routes tab, and the
  milestone is already retitled "M8 — Navigation, Live Map & Routes".
- UX.md §S05.1's route row was covered by PR #229, as the issue's own first comment says.

**Where the issue's second comment disagreed with the code, the code won.**
- It names `State.turnBanner`; the built property is `turnInstruction`, and it holds a `Maneuver`
  rather than text, so the overlay can draw the arrow.
- It lists three snapping rules. There are four: the missing one is **continuity weighting**
  (`continuityWeight = 0.1`), which is what stops a stopped rider's GPS scatter moving the match onto
  a later pass of the same road, past turns they would then never be told about.
- It does not mention **loops** at all — `lapStartMeters`, `loopClosureMeters`, and the
  half-the-loop rule that decides when a loop is actually finished. §4.14 documents it.
- It says both searches are in `RouteGeometry`. The searches are (`candidates`, `passes`); the
  constants and the continuity scoring are on `NavigationFeature`. §4.14 says so.

**Left alone, deliberately.**
- `README.md:47` "Tribos.studio: Pull routes" — an unphased product wishlist, not an MVP claim, so
  it contradicts nothing.
- `DataModel.md` §3.1's `Ride` listing is stale beyond routes (no `isAutoPaused`, sample counts,
  `recordingState`, `RideSyncRecord`). Out of scope for #202; worth its own issue.
- `PRD.md` §12's feature tree still says `SpeedCadenceFeature`, which split into `SpeedFeature` and
  `CadenceFeature` long ago. Same reason.

**Verification.**
- `grep -rni "tribos\|coming soon\|\.fit"` over the four specs and CLAUDE.md: every surviving hit is
  a revision-history entry, an explicit Phase 2 row, the `ExternalService` enum case, an
  external-planning-tool mention in OQ12/§15, or the new out-of-scope row.
- `grep -rn "S19\|S20\|Routes tab" assets/*.md | grep -i "phase 2"`: only revision history and the
  two genuinely-Phase-2 sub-items (S20's weather and Strava segments).
- §4.14's ten constants, both `RouteGeometry` function names, `fetchResumableRide`,
  `RidePersistenceActor.apply`, and §3.10's every field checked line by line against the source.
- Code fences balanced in all four files; the two ASCII diagrams re-aligned to their existing
  column grid.
