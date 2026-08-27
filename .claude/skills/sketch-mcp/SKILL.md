---
name: sketch-mcp
description: This skill should be used when the user asks to check, inspect, or compare against the Sketch design file — phrases like "check the Sketch file", "what does Design.sketch say about S07", "compare this screen to the design", "pull the real colors from Sketch", "does the layer tree match what we built", or "get a screenshot of the artboard for W7". Connects to Sketch's official local MCP server so Claude can query assets/design/Design.sketch directly instead of relying on colors.md or CLAUDE.md's typography table, which are hand-maintained snapshots of it.
---

# Sketch MCP

Sketch ships an **official** local MCP server (confirmed via sketch.com/docs/mcp-server and github.com/sketch-hq/sketch-mcp-bundle — this is not a third-party or community server). It runs inside the Sketch.app process itself and exposes the open document's structure, assets, and screenshots over local HTTP. It requires Sketch 2025.2.4+, macOS, and the direct-download build (not the Mac App Store version).

## Setup

**Check whether it's already reachable:**
```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:31126/mcp
```
`200` or `405` means the server is up (a plain unauthenticated GET against an MCP endpoint correctly returns 405 Method Not Allowed — that still confirms it's listening). Connection refused means Sketch isn't running or the toggle is off.

**If it's not running:** open Sketch.app, then either ⌘K → type "MCP" → "Start MCP Server", or Settings → General → MCP Server (toggle on). macOS will prompt for Local Network permission the first time — accept it.

**Register it with Claude Code**, if not already registered:
```bash
claude mcp add --transport http sketch http://localhost:31126/mcp -s local
```
Use `-s local` (not `project` or `user`) — the endpoint is `localhost`-only, so a project- or user-scoped entry would silently fail on any other machine or for any other contributor. No authentication is needed; it's a local-only server by design.

## Available tools

| Tool | Use it for |
|---|---|
| `get_document_info` | Orientation — page/artboard overview of `Design.sketch` before diving into a specific screen. |
| `get_layer_tree_summary` | The layer hierarchy of a specific artboard, as readable text — check this against the SwiftUI view hierarchy being built for the same screen. |
| `get_design_assets` | Enumerate symbols, text styles, layer styles, colors defined in the document. |
| `get_screenshot` | A visual capture of a layer or artboard — pixel reference when matching a SwiftUI layout to the design. |
| `get_libraries` | Linked shared libraries and their IDs — relevant when a Sketch symbol maps to a shared SwiftUI component (`HeroNumber`, `SensorListRowView`). |
| `get_symbol_overrides` | Per-instance overrides on a symbol — useful for understanding why two uses of "the same" component look different in the design. |
| `get_guide` | Sketch's own bundled reference docs, for questions about the MCP surface itself. |
| `run_code` | Arbitrary SketchAPI script execution — the **only tool in this set that can write/mutate the document.** |

`run_code` is different in kind from the other seven: it can change the shared `Design.sketch` file that the whole design system is built from. Treat it like any other hard-to-reverse, shared-state action — confirm with Brian before using it to modify anything, even something that looks trivially safe (renaming a layer, moving an artboard). The read-only tools need no such confirmation.

## Reconciling Sketch against the repo's own spec docs

`assets/design/colors.md` is `CLAUDE.md`'s declared canonical source for hex values, and the typography ramp table in `CLAUDE.md` is a hand-maintained snapshot of the D-DIN/GillSans sizes actually in the Sketch file. Both can drift from the live document — someone tweaks a color in Sketch and forgets to update `colors.md`, or vice versa. When `get_design_assets` or a screenshot disagrees with what `colors.md`/`CLAUDE.md` state:

- Don't silently trust either side. Surface the discrepancy the same way the `spec-first` skill does for PRD/UX vs. code — name both values and let Brian decide which one is stale.
- If Sketch is confirmed as the more current source, update `assets/design/colors.md` to match (it's the file `CLAUDE.md` tells implementers to reference) rather than leaving two disagreeing sources of truth in the repo.

## Typical workflow

Before implementing a new screen or widget (once `spec-first` has located the `S##`/`W##` spec coordinate): `get_document_info` to find the matching artboard → `get_layer_tree_summary` on it to see the actual layer structure → `get_screenshot` for pixel reference → `get_design_assets` to confirm colors/text styles against `assets/design/colors.md` before writing any SwiftUI.
