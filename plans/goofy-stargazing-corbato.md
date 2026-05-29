# Phase 5 — Remaining Tools + Polish (sequential local batches)

## Context

Phases 1–4 are merged to `main`: pure-Lua WebSocket server, terminal panel + pi
launch, the pi-nvim-bridge extension (connect/auth/reconnect + open_file,
get_selection, get_workspace_folders), and the blocking diff system. Phase 5 is
the final phase — it brings the plugin to feature parity with claudecode.nvim:
the remaining tool handlers, debounced selection tracking, and the UX/polish
layer (which-key, statusline, file-tree, docs, CI, integration tests).

**Execution model (user-chosen):** sequential local batches on a single branch
`phase-5-polish`, TDD throughout, local fast-forward merge to `main` like Phases
1–4. No parallel worktrees / PRs — this repo has **no git remote**, and the tool
and selection work share files (`handlers/init.lua`, `extensions/.../index.ts`,
`init.lua` `setup()`) that would conflict across worktrees. Checkpoint with the
user between batches.

## Conventions to follow (from the existing code)

- **Lua tool handler**: a module `lua/pi-panel/handlers/<name>.lua` exporting
  `M.handle(params, respond)` that does its vim work inside `vim.schedule(...)`
  and calls `respond(result)` (handlers run in the libuv callback context). The
  returned table becomes the JSON-RPC `result`; an `{ error = {...} }` table
  becomes a JSON-RPC error. Register it in the `M.registry` table literal in
  `lua/pi-panel/handlers/init.lua` (the `initialize` handler auto-derives
  `supportedTools` from registry keys, minus `initialize`/`cancel`).
- **Extension tool**: add the method name to `METHODS` in
  `extensions/pi-nvim-bridge/index.ts` and a `pi.registerTool({ name:"nvim_<x>",
  label, description, parameters: Type.Object({...}), execute:(_id,p,signal)=>
  call("<x>", p, signal) })` block. Keep `METHODS` and the Lua registry in sync.
- **Tests**: Lua specs `tests/spec/<name>_spec.lua` (auto-discovered), using the
  `call(method, params)` → `vim.wait(500, …)` pattern from `handlers_spec.lua`.
  JS specs `extensions/pi-nvim-bridge/test/*.test.ts` (`node:test`).
- Config fields already exist: `track_selection`, `visual_demotion_delay_ms`,
  `whichkey = { enabled, leader }`, `diff_opts` (`config.lua`).

## Batch 1 — Remaining JSON-RPC tools (6 handlers + extension tools)

New handler modules (each scheduled + `respond`):
1. `get_open_editors` → `{ editors = [{ filePath, name, active, dirty }] }` from
   `nvim_list_bufs` filtered to listed, named buffers.
2. `get_diagnostics` (opt `filePath`) → `{ diagnostics = [{ filePath, severity,
   message, line, col, source }] }` via `vim.diagnostic.get`, severities mapped
   to names.
3. `check_dirty` (opt `filePath`) → `{ filePath, isDirty }` via `vim.bo[buf].modified`.
4. `save_document` (`filePath`) → save the buffer; `{ filePath, saved }`.
5. `close_tab` (`filePath`) → delete the matching buffer; `{ closed }`.
6. `close_all_diff_tabs` → reject all active diffs (new `diff.close_all()` that
   `reject`s each active view so pending requests resolve) → `{ closed = N }`.

Shared edits: `handlers/init.lua` (+6 registry entries), `index.ts` (+6 METHODS,
+6 tool blocks). Tests: extend `handlers_spec.lua` (or a new `tools2_spec.lua`)
covering all six deterministically in headless nvim.

## Batch 2 — Selection tracking + UX integration

- **Server broadcast**: add `M.broadcast(method, params)` to
  `lua/pi-panel/server/init.lua` (iterate `state.server.clients`, send a JSON-RPC
  notification via the client's existing send method — verify the exact name in
  `server/client.lua`). Unit-test with a fake client.
- **`lua/pi-panel/selection.lua`**: one reusable `vim.uv` timer created in
  `setup(cfg)`, reset (`timer:start`/`again`) on `CursorMoved`/`CursorMovedI`/
  `ModeChanged` in normal (non-terminal) buffers; after `visual_demotion_delay_ms`
  it computes the current visual selection (reuse the `'</'>` logic from
  `handlers/get_selection.lua` — factor a shared helper) and, if changed,
  `server.broadcast("selection_changed", …)`. Maintains a **latest-selection
  cache**.
- **`get_latest_selection`** handler + `nvim_get_latest_selection` tool: returns
  the cached selection (even when not currently in visual mode).
- **Commands**: `:PiSend` (`M.send_selection` → force-broadcast current
  selection) and `:PiAdd [file]` (`M.add_file` → broadcast an
  at-mention/selection for the file or `%`). Add to `commands.lua` + `init.lua`.
- **`lua/pi-panel/whichkey.lua`**: `register(cfg.whichkey)` registering the
  `<leader>p` group (pp/pf/ps/pa/pr/pb/px) iff `which-key` is `pcall`-available.
  Wire into `setup()`.
- **`lua/pi-panel/status.lua`**: `M.statusline()` → `"pi: off|waiting|connected"`
  from `server.is_running()`/`has_client()`. Standalone (user wires it in).
- **`lua/pi-panel/filetree.lua`** (lightest): helper returning the path under the
  cursor for nvim-tree/neo-tree/oil, used by `:PiAdd` when invoked from a tree
  buffer. Plugin-dependent, so kept thin and guarded; documented as best-effort.
- Extension: extend the bridge's message handler so inbound notifications
  (`selection_changed`) are dispatched to an optional `onNotification` callback
  instead of silently dropped; the extension stores the latest selection. Keep it
  non-intrusive (no automatic pi.sendMessage spam). Add a bridge unit test for
  notification dispatch.

## Batch 3 — Docs, CI, integration tests

- `README.md` (overview, lazy.nvim install, config table, commands/keymaps,
  architecture), `doc/pi-panel.txt` (Neovim help format with tags), `docs/adr/`
  (extract 3–5 ADRs from `DECISION_LOG.md`/`PLAN.md`: TUI+side-channel, Neovim
  server, JSON-RPC, lock-file discovery, bundle strategy), `CHANGELOG.md`.
  `LICENSE`: needs your license choice (MIT assumed unless you say otherwise) —
  will confirm at the Batch 3 checkpoint.
- `.github/workflows/test.yml`: on push/PR, set up Neovim + Node, run `make test`
  and `npm audit` (valid for when a remote is later added).
- Integration tests: extend `tests/support/ws_client.js` to call an arbitrary
  method, and add `tests/spec/` integration cases that drive the new tools
  through the full server (`server.start` + ws_client) end-to-end.

## Verification recipe (run per batch)

1. **Lua unit**: `nvim --headless -l tests/run.lua` → "N passed, 0 failed".
2. **JS unit + types + bundle**: `cd extensions/pi-nvim-bridge && npm test &&
   npm run typecheck && npm run build`.
3. **End-to-end (tools/selection)**: the documented cross-language harness — a
   headless nvim running `require("pi-panel.server").start()` plus either the
   real `NvimBridge` (via `node --experimental-strip-types`) or
   `tests/support/ws_client.js` — call the new method / await the
   `selection_changed` notification and assert the response. (See the
   `pi-bundle-verification` project memory for the harness + the PTY trick for
   the real `pi` binary.)
4. **Full suite green** on `main` after each local fast-forward merge.

## Out of scope / notes

- True file **deletion** diffs remain unhandled (Phase 4 note) — not added here.
- File-tree integration is best-effort (depends on external plugins; not unit-
  tested headlessly).
