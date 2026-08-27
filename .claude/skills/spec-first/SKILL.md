---
name: spec-first
description: This skill should be used when the user asks to implement, build, or wire up a feature, screen, or widget in CyclometerAI — including phrases like "implement S05", "build the W7 radar widget", "start on issue 148", "add the M10.6 weather stuff", or any request that references a milestone code (M#), screen code (S##), widget code (W##), or Open Question (OQ##). Also use it when a GitHub issue number is given without further context. Reconciles what the specs say against what the codebase actually does before any code is written.
---

# Spec-First

Cyclometer's specs (`PRD.md`, `UX.md`, `TCA.md`, `assets/design/colors.md`) describe design intent. `CLAUDE.md` says plainly: **the codebase is the source of truth for what is actually built** — the specs may already be stale. `TCA.md` §8 is a documented example: `CLAUDE.md` explicitly overrides its file layout. So the job before writing code is never "read the spec and follow it" — it's reconciliation: find what the spec says, find what the code already does, and when they disagree, surface the disagreement instead of silently picking one side.

## Steps

1. **Identify the spec coordinate.** Pull out any milestone (`M#` or `M#.#`), screen code (`S##`), widget code (`W##`), or Open Question (`OQ##`) the request maps to. If a GitHub issue number is given or discoverable, that's the sharpest source — go there first.

2. **Read the issue, if one exists.** `gh issue view <#>` and treat its `## Summary` / `## Scope` / `## Acceptance Criteria` as the authoritative *scoped* ask — narrower than the PRD/UX prose, and usually more current. If the issue and the PRD/UX text disagree about what's in scope, the issue wins for this piece of work, but name the disagreement rather than letting it pass silently — a spec sometimes ships a screen as "Cut" or moves a field between screens after the PRD prose was written (see the `tasks/lessons.md` entry on issue #96: `UX.md §S03` was marked Cut, but the PRD language alone would have implied otherwise).

3. **Grep the governing spec sections.**
   - `PRD.md` and `UX.md` for the `S##`/`W##`/`OQ##` code — these describe rider-facing behavior and layout.
   - `TCA.md` §4 (Feature Specifications) *only* for the reducer's state/action/effect shape if a comparable feature is being modeled — not for file paths (§8 is known stale) or exact folder nesting.
   - `assets/design/colors.md` for any new color token; never hardcode a hex value.

4. **Check the codebase's nearest existing analog before trusting spec prose.** Find a sibling feature that already does something structurally similar (e.g. another `@Reducer` with a BLE reconnect grace window, another widget at the same grid size) and treat its actual shape as the template. When code and spec disagree on a low-level shape (a field name, whether something is stored vs. read live), the code usually reflects a decision made after the spec prose was last touched — confirm by checking git history or asking, don't assume the spec's older text is current.

5. **Write a short before-code plan.** For any TCA reducer work, sketch the state fields, new actions, and effects being added or changed — this is the input to Plan Mode, not a replacement for it. Keep it short: a bullet list mapping each acceptance-criteria line to the state/action/effect that satisfies it.

6. **Flag any touched Open Question explicitly.** `CLAUDE.md`'s "Open Questions" section lists OQ2 (Garmin SDK vs. raw CoreBluetooth for Varia BLE), OQ7 (minimum Varia RTL515/RCT715 firmware for BLE characteristics), OQ11 (whether Varia exposes radar signal amplitude), and OQ12 (MVP navigation: `MKDirections` vs. GPX-import-only) — grep for others added since. If the request depends on one being resolved, say so up front rather than quietly picking an answer.

## What this skill is not

It doesn't replace Plan Mode or `AskUserQuestion` — it's the research step that feeds them. It also doesn't apply to trivial one-line fixes (a typo, an off-by-one, a renamed variable) — those don't need a spec coordinate at all.

For the actual reducer/view/test scaffolding once the "what" is settled, see the `tca-feature` skill.
