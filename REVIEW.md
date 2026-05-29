# Plan Review: pi-panel.nvim Implementation Plan (Revision 3)

**Plan type:** Software / Infrastructure (Neovim plugin)
**Overall risk:** Low
**Review date:** 2026-05-29

---

## Summary

This is a mature, implementation-ready plan. Every critical finding from the two prior reviews has been resolved: extension distribution via auto-symlink, the pure-Lua WebSocket server is split into three sub-phases with RFC test vectors, the risk register exists with six entries and mitigations, abort criteria are explicit, a two-week buffer is built in, and capability negotiation handles protocol versioning. The total timeline of 14 weeks (12 active + 2 buffer) is realistic. The seven findings below are all minor implementation details, not architectural blockers. The plan is ready to proceed.

---

## Architecture & Modularity

### 🟡 Warning — TypeScript compilation step must precede extension symlink creation

**Evidence:** The startup flow says the plugin "verifies/creates extension symlink in `~/.pi/extensions/`" during `setup()`. The `Makefile` defines a `build` target that compiles TypeScript via `tsc`. But `setup()` runs when the plugin loads at Neovim startup; there is no guarantee the TypeScript has been compiled yet. If the symlink points to `extensions/pi-nvim-bridge/` (the source directory), pi will try to load `.ts` files.

**Risk:** Pi extensions need runnable JavaScript (or a runtime that handles TypeScript). If the user installs the plugin from source without running `make build`, the symlink points to uncompiled TypeScript and pi's extension loader fails silently. The user sees "pi-panel.nvim" installed but pi has no tools.

**Recommendation:** Either (a) ship pre-compiled JavaScript in the repository alongside the TypeScript source, (b) have the symlink point to a `dist/` directory and document that `make build` is required before first use, or (c) run `npm install && npm run build` in the extension directory during `setup()` and symlink the `dist/` output. Option (c) is highest-friction on startup but lowest-friction for users. Clarify the expected workflow in the README.

**Why:** This is the packaging equivalent of the "extension distribution" gap from the last review, one level down. The distribution mechanism is now specified; the build step just needs to be wired in correctly.

---

### 🟢 Note — `package-lock.json` location conflicts with monorepo structure

**Evidence:** The project structure shows `package-lock.json` at the project root, but `package.json` is inside `extensions/pi-nvim-bridge/`. npm generates `package-lock.json` in the same directory as `package.json`.

**Recommendation:** Move `package-lock.json` into `extensions/pi-nvim-bridge/` or add a root `package.json` with a workspace configuration. The root-level `package-lock.json` should not exist unless there's a root `package.json`.

---

## Implementation Concerns

### 🟡 Warning — `open_diff` timeout pseudo-code has a race condition

**Evidence:** The handler code for `open_diff`:

```lua
handlers["open_diff"] = function(params, respond)
  local diff = require("pi-panel.diff")
  diff.open(params, function(result)
    respond({ content = {{ type = "text", text = result }} })
  end)
  
  vim.defer_fn(function()
    if not responded then
      respond({ error = { code = -32000, message = "Diff timeout (5 minutes)" } })
    end
  end, 300000)
end
```

The variable `responded` is referenced in the timeout closure but is never declared or assigned. If the user accepts/rejects the diff, the callback fires and calls `respond()`, but `responded` remains nil. If the timeout fires immediately afterward (race), `respond()` is called a second time.

**Risk:** Low severity since this is pseudo-code, not implementation. But if copied directly, double-invocation of `respond()` on a JSON-RPC handler could crash the Neovim server or send duplicate responses to the extension, which would break request ID tracking.

**Recommendation:** Declare `responded` as `false` at the top of the handler and set it to `true` before calling `respond()` in both the callback and timeout. Actual implementation should guard against double-response regardless.

**Why:** This is the kind of bug that manifests as an intermittent crash under load. Catching it in the plan prevents it from becoming a two-hour debugging session in Phase 4.

---

### 🟢 Note — `initialize` handler doesn't show version mismatch checking

**Evidence:** The `initialize` handler returns `{ protocolVersion = 1, ... }` but doesn't inspect the client's `protocolVersion` to decide whether to warn or reject the connection. The plan states "Both sides log warnings on version mismatch" but the handler code doesn't demonstrate this.

**Recommendation:** Add a version check to the handler pseudo-code: `if params.protocolVersion ~= 1 then vim.notify("Protocol version mismatch...", vim.log.levels.WARN) end`. This clarifies that the check happens on the Neovim side too, not just in the extension.

---

### 🟢 Note — `open_file` handler references undocumented parameters

**Evidence:** The `open_file` handler checks `params.startLine` to set the cursor, but the tool table lists only `filePath`. The tool description says "optionally select range" implying `startLine` and `endLine` exist.

**Recommendation:** Add `startLine` and `endLine` as optional parameters to the `nvim_open_file` tool entry in the table, or remove the `startLine` logic from the handler code. Either way, keep the plan self-consistent.

---

### 🟢 Note — Selection notifications may be lost during connection gaps

**Evidence:** Selection tracking sends `selection_changed` notifications over WebSocket. If the pi extension hasn't connected yet (pi is still starting up), or the connection has dropped and reconnection is in progress, these notifications are silently dropped.

**Recommendation:** Consider a small ring buffer (last 3-5 selection events) that replays to the extension after a successful (re)connection. Not blocking for v1, but worth noting as a future UX improvement.

**Why:** The most common selection-send scenario is: user selects text, toggles the pi panel, and expects pi to see the selection. If the panel wasn't open, pi is starting and may miss the initial selection notification. A replay buffer makes this reliable.

---

### 🟢 Note — Terminal buffer lifecycle when user closes the buffer manually

**Evidence:** The terminal section says "Auto-close on pi exit (configurable)" but doesn't describe the reverse: what happens when the user closes the terminal buffer (via `:bd` or `:q`) while pi is still running.

**Recommendation:** Document the expected behavior. Options: (a) close sends SIGHUP to pi, which exits; the lock file is cleaned up and the server remains running for reconnection, (b) the plugin prevents terminal buffer deletion while pi is running, or (c) the plugin restarts pi in a new terminal buffer. Pick one and document it.

**Why:** Neovim users close buffers reflexively. If closing the terminal sends a confusing error or silently kills pi without cleanup, it creates a bad first impression.

---

## Documentation & Communication

### 🟢 Note — `:PiReconnect` is listed but not described

**Evidence:** The command is in the commands table but the description column is empty. It's mentioned in the extension section as a "force reconnection" command but never explained in the Commands section.

**Recommendation:** Add a description: "Force WebSocket reconnection to pi extension after connection drop."

---
