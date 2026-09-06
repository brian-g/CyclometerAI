---
name: gh-batch
description: This skill should be used when the user asks to batch-create GitHub issues from a milestone or spec section, file a set of issues for a wave of work, close out or relabel a group of issues, or move several issues between milestones. Triggers on phrases like "create issues for M10.7", "file issues for the weather section", "batch close these", or "move these to the next milestone". Encodes this repo's exact issue title/body/label conventions so batch-created issues match the existing ~150 issues rather than drifting from them.
---

# gh-batch

CyclometerAI (`brian-g/CyclometerAI`, **public**) tracks work almost entirely as milestone-scoped GitHub issues with a strict, consistent template — visible in issues #139–#155, all filed the same day for milestones M10.5/M10.6. Batch operations must match that template exactly, and because the repo is public and issue creation/editing is visible to others, always show the user the full drafted batch and get explicit confirmation before creating or mutating anything.

## The issue template

**Title:** `[M#] <Title>` or `[M#.#] <Title>` — the milestone code always leads, in brackets.

**Body**, four `##` sections in this order:

```markdown
## Summary

1–3 sentences: what's missing today and why this issue exists. Name the specific
files/types involved if any exist already.

## Scope

Bullet list of what this issue actually builds — concrete enough that "done" is
unambiguous. Explicitly name what's *excluded* if a naive reading of the title
would over-scope it (e.g. "W9 Directions excluded — depends on Navigation, which
doesn't exist until M8").

## Acceptance Criteria

- [ ] Checkbox list. Each line independently verifiable.

## References

Spec section codes (`UX.md §S07`), file paths, and `file:line` pointers to the
nearest existing pattern to follow. Real example: "UX.md §S05.4, §S07, §S08 ·
`Cyclometer/Cyclometer/Features/ActiveRide/RideDashboardView.swift:65-140`"
```

**Labels** — pick from the existing set, don't invent new ones: `feat` (new feature — the default for scope work), `bug`, `enhancement`, `design-system` (shared UI components), `test` (tests/QA/validation), `documentation`, `good first issue`, `help wanted`, `question`, `duplicate`, `invalid`, `wontfix`. Most milestone-scope issues are just `feat`.

**Milestone** — always assigned; never leave a scope issue unmilestoned.

## Batch-create flow

1. Resolve the milestone's **exact title**: `gh api repos/:owner/:repo/milestones -q '.[] | "\(.number)  \(.title)"'`.

   **`gh issue create --milestone` takes the milestone *title*, not its number** — passing a number fails with `could not add to milestone '8': '8' not found`, and it fails *before* creating the issue, so a bad batch aborts cleanly rather than leaving half-milestoned issues. Copy the title exactly, em dashes and all (`M8 — Navigation, Live Map & Routes`); the number is only useful for `gh api` calls that edit the milestone itself.

   **Run `gh` from inside the working copy**, or pass `--repo brian-g/CyclometerAI`. `gh issue create` shells out to git to infer the repo and dies with `failed to run git: fatal: not a git repository` if the working directory is elsewhere (a scratchpad, say) — even though `--body-file` happily takes an absolute path out of that scratchpad.

2. Draft every title + body against the template above **before creating anything**. Break the spec section or wave of work into one issue per independently-shippable unit — look at how M10.5's issues split (#139 data model, #140 three widgets together since they share a shape, #141 edit mode, #142 add-widget sheet, #143 the shared detail-sheet pattern before the four screens that use it) as a sizing reference: group only when pieces are trivial together, split when a "done" checkbox line would otherwise span unrelated files.

3. Show the user the drafted batch — every title, and at minimum the Summary/Scope of each body — and get explicit go-ahead on both content and count before creating anything. This is a public, visible, non-trivially-reversible action.

4. Create in a loop:
   ```bash
   gh issue create \
     --title "[M10.7] <Title>" \
     --body "$(cat <<'EOF'
   ## Summary
   ...
   EOF
   )" \
     --label feat \
     --milestone "<exact milestone title>"
   ```
   Capture the issue number `gh issue create` prints (last line of a URL) for each.

5. Verify the resulting set: `gh issue list --milestone "<milestone title>"` and confirm the count and titles match what was confirmed in step 3.

## Batch-edit flow (relabel / re-milestone / close)

Only operate over an **explicit, user-confirmed list of issue numbers** — never a list inferred from a fuzzy query without showing it to the user first (e.g. `gh issue list --search "..."` output must be shown and confirmed, not assumed correct).

```bash
for n in 139 140 141; do
  gh issue edit "$n" --add-label test --milestone "M11 — QA & TestFlight Beta"
done

for n in 139 140; do
  gh issue close "$n" --reason completed
done
```

Prefer `--reason completed` vs `--reason "not planned"` deliberately — it shows up in the issue list and history.
