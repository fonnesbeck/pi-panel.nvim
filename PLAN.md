# pi-panel.nvim Implementation Plan

A Neovim plugin that deeply integrates the pi coding agent, providing a side panel interface with pi's TUI running inside Neovim and a WebSocket side channel for bidirectional tool communication.

**Minimum Neovim Version**: 0.10+ (required for `vim.uv` API; `vim.loop` is deprecated)

## Overview

**Goal**: Feature parity with claudecode.nvim, adapted for pi. The user types prompts into pi's TUI running in a Neovim panel. A pi extension connects to a WebSocket server running in Neovim, enabling pi to call back into the editor (open files, show diffs, access selections, etc.).

**Quantitative Success Criteria**:
- Panel toggle renders pi's TUI in < 200ms
- WebSocket connect + auth handshake completes in < 500ms
- Tool execution (LLM → extension → WebSocket → Neovim → response) completes in < 100ms wall time
- No connection drops during normal operation (8+ hour sessions)
- Reconnection after transient failure completes in < 5s

**Architecture**: 
- Pi runs with its full TUI inside a Neovim terminal panel (via snacks.nvim or native `termopen`)
- Neovim runs a WebSocket server on a random port
- A pi extension (`pi-nvim-bridge`) connects to the Neovim server on startup
- The extension registers tools (open_file, open_diff, get_selection, etc.) that delegate to Neovim over WebSocket
- Discovery works through a lock file and environment variables (same pattern as claudecode.nvim)

## How It Works

### Extension Distribution

The `pi-nvim-bridge` TypeScript extension ships as part of the Neovim plugin repository (in `extensions/pi-nvim-bridge/`).

**Build: esbuild-bundle into a single committed `dist/index.js`.** Pi *can* load raw `.ts` via [jiti](https://github.com/unjs/jiti) and pi's `extensions/` loader accepts both `.ts` and `.js`, so no compile is needed for our own code. The reason to bundle is the one runtime dependency — the `ws` WebSocket client. The alternatives (vendoring `node_modules/`, running `npm install` at `setup()`, or hand-rolling an RFC 6455 client over `node:net`) are each worse: the first is ugly, the second adds startup friction, and the third duplicates frame/masking logic in a second language and is error-prone. Bundling produces one self-contained file with no `node_modules` and no per-user install.

esbuild config note (revised in Phase 3 against the real pi 0.77 loader): mark only the **type-only** pi packages as `--external` — `@earendil-works/pi-coding-agent`, `@earendil-works/pi-agent-core`, `@earendil-works/pi-ai`, `@earendil-works/pi-tui`. We import these with `import type` only, so esbuild erases them and the `--external` flags are just belt-and-suspenders. **`ws` and `typebox` are both inlined** into the bundle. Two findings forced inlining `typebox` (the original plan kept it external):
> - Pi loads `-e` extensions through jiti with `tryNative` enabled, which native-`import`s a pre-bundled `.js`. Native import bypasses jiti's peer-dep `alias` map, so a bare `import { Type } from "typebox"` is unresolvable for end users (who only get `dist/index.js`, no `node_modules`). Verified: it fails with `ERR_MODULE_NOT_FOUND`.
> - typebox 1.x emits **plain JSON Schema** objects (`{ "type": "object", ... }`) with no symbol/`Kind` markers, so there is no module-identity concern — pi's validator consumes our bundled-typebox schema identically.
>
> The ESM bundle also needs a `createRequire` banner (`import { createRequire } from 'node:module'; const require = createRequire(import.meta.url)`) so the inlined CJS `ws` can `require()` Node built-ins.

> Optional zero-build path: if the project pins **Node 22+**, use Node's global `WebSocket` instead of `ws`, drop the bundle, and ship plain `.ts`. Pi requires only Node 18+, so this is not the default.

**Discovery: launch with `-e`, do not symlink globally.** Pi's `-e`/`--extension <source>` flag loads an extension from a path (file or directory), is repeatable, and is exactly the right fit because the plugin controls every pi launch. Neovim starts pi with `-e <abs path>/extensions/pi-nvim-bridge/dist/index.js`. This scopes the extension to the launched process and avoids mutating a global `~/.pi/agent/extensions/` directory (an invasive, surprising side effect of installing a Neovim plugin). For users who want the extension always available outside this plugin, document the `settings.json` `extensions` array as an opt-in alternative; a global symlink is not used.

> **Note on discovery vs. the pi-side protocol below**: pi has no built-in "IDE integration" protocol, lock-file convention, or reserved `PI_IDE_*` environment variables. The lock file, env vars, and JSON-RPC side channel described in this plan are conventions *this project defines*, modeled on claudecode.nvim. Neovim sets the env vars when it launches pi in the terminal; the extension reads them via `process.env`. Nothing in pi reads or reserves these names.

### Startup Flow

```
1. Neovim starts pi-panel.nvim (via setup() or auto_start)
2. Plugin sweeps ~/.pi/ide/ and removes any lock files whose pid is dead
3. Plugin starts WebSocket server on random port (127.0.0.1 only)
4. Plugin writes lock file: ~/.pi/ide/[port].lock
   { pid, port, authToken, workspaceFolders, displayName }
5. Plugin opens terminal panel, launches pi with the extension and env vars:
   pi -e <plugin>/extensions/pi-nvim-bridge/dist/index.js
   PI_IDE_PORT=[port]
   PI_IDE_AUTH=[authToken]
   PI_IDE_LOCKFILE=~/.pi/ide/[port].lock
6. Pi starts normally with its TUI
7. pi-nvim-bridge extension reads env vars on session_start
8. Extension connects to Neovim WebSocket server with auth token
9. Extension sends initialize message with protocol version and tool list
10. Neovim responds with its protocol version and supported tools
11. Extension registers tools that delegate to Neovim
12. User interacts with pi's TUI; pi calls tools that execute in Neovim
```

### Tool Execution Flow

```
1. LLM decides to call open_file tool
2. pi-nvim-bridge extension's tool handler fires
3. Extension sends JSON-RPC request over WebSocket to Neovim:
   { jsonrpc: "2.0", id: "req-1", method: "open_file", params: { filePath: "/path/to/file" } }
4. Neovim receives request, executes vim.cmd("edit /path/to/file")
5. Neovim sends JSON-RPC response:
   { jsonrpc: "2.0", id: "req-1", result: { content: [{ type: "text", text: "Opened" }] } }
6. Extension receives response, returns tool result to pi
7. pi shows result to LLM
```

### Blocking Tool Flow (open_diff)

```
1. LLM calls open_diff with old/new file content
2. Extension sends request to Neovim
3. Neovim opens diff view (original file + temp file with new content)
4. Extension's tool handler is blocked (waiting for WebSocket response)
5. User reviews diff, presses accept or reject
6. Neovim sends response: FILE_SAVED or DIFF_REJECTED
7. Extension returns result to pi
8. pi continues with next action

Cancellation: pi passes an AbortSignal as the 3rd arg to the tool's execute().
If the user presses Esc in pi, the signal fires; the extension rejects the
pending request and sends a `cancel` notification so Neovim closes the diff.

Timeout: If no response after 5 minutes, auto-reject and return DIFF_TIMEOUT error
```

## Core Components

### 1. WebSocket Server (`lua/pi-panel/server/`)

A WebSocket server in pure Lua using `vim.uv`, following claudecode.nvim's implementation.

**Modules**:
- `tcp.lua` — TCP server using `vim.uv.new_tcp()`, binds to 127.0.0.1
- `handshake.lua` — HTTP upgrade handling, validates auth token header
- `frame.lua` — RFC 6455 WebSocket frame parser (text, binary, close, ping, pong)
- `client.lua` — Connection management, state tracking, ping/pong keepalive
- `utils.lua` — Pure Lua SHA-1, base64 encoding
- `init.lua` — Server lifecycle (start, stop, broadcast)

**Protocol**: JSON-RPC 2.0 over WebSocket with capability negotiation

```json
// Initialize handshake (first message after WebSocket connect)
{ "jsonrpc": "2.0", "id": "init-1", "method": "initialize", "params": { "protocolVersion": 1, "supportedTools": ["open_file", "open_diff", ...] } }
{ "jsonrpc": "2.0", "id": "init-1", "result": { "protocolVersion": 1, "supportedTools": ["open_file", "open_diff", ...] } }

// Request from pi extension to Neovim
{ "jsonrpc": "2.0", "id": "req-1", "method": "open_file", "params": { "filePath": "/path/to/file" } }

// Response from Neovim to pi extension
{ "jsonrpc": "2.0", "id": "req-1", "result": { "content": [{ "type": "text", text: "Opened" }] } }

// Notification from Neovim to pi extension (no id, no response expected)
{ "jsonrpc": "2.0", "method": "selection_changed", "params": { "text": "...", "filePath": "..." } }
```

**Capability Negotiation**: After WebSocket connect, both sides exchange an `initialize` message declaring protocol version and supported tool list. Both sides log warnings on version mismatch. This prevents silent breakage as the protocol evolves.

**Reconnection Logic**: The extension implements exponential backoff reconnection (1s, 2s, 4s, max 30s) when the WebSocket connection drops. In-flight requests are tracked and rejected with a clear error if the connection closes before a response arrives. Users can force reconnection with `:PiReconnect`.

**Security**: Localhost only. Auth token validated on WebSocket handshake via custom header.

### 2. Lock File System (`lua/pi-panel/lockfile.lua`)

Discovery mechanism for the pi extension.

```lua
-- ~/.pi/ide/[port].lock
{
  pid = vim.fn.getpid(),
  port = 12345,
  authToken = "uuid-v4",
  workspaceFolders = { "/path/to/project" },
  displayName = "project-name",  -- cwd basename for multi-instance identification
  ideName = "Neovim"
}
```

**Lifecycle**:
- Written atomically (write to .tmp, then rename) when server starts
- Removed on `VimLeavePre` autocmd
- Extension reads on `session_start` event

**Stale lock handling** (a hard crash means `VimLeavePre` never runs, so locks leak):
- On startup, the plugin sweeps `~/.pi/ide/`, parses each lock's `pid`, and deletes any whose process is dead (`vim.uv.kill(pid, 0)` returns an error for a nonexistent pid). This keeps the directory clean across crashes.
- Before the extension connects via a *discovered* lock (i.e. not via the authoritative env vars), it verifies liveness with `process.kill(pid, 0)` — a 0-signal probe that throws `ESRCH` if the pid is gone — and skips dead entries. Note: in the normal launch path the env vars (`PI_IDE_PORT`/`PI_IDE_AUTH`) are authoritative and the server is inherently alive (Neovim is the parent running pi), so the pid probe is the safety net for the lock-discovery path and for pid reuse, with the auth token guarding against connecting to the wrong server.

**Multi-Instance Support**: The `displayName` field (cwd basename) helps users identify which pi instance is connected to which Neovim instance when running multiple sessions.

### 3. Terminal Management (`lua/pi-panel/terminal.lua`)

Manages the pi process inside a Neovim terminal panel.

**Providers**:
- **snacks.nvim** (default): Rich floating/split terminal via `Snacks.terminal`
- **native**: `vim.fn.termopen()` fallback
- **external**: tmux, kitty, wezterm (future)

**Features**:
- Toggle panel visibility (simple toggle, smart focus toggle)
- Launch pi with correct environment variables for WebSocket discovery
- Track terminal buffer and process state
- Handle terminal resize and window management
- Auto-close on pi exit (configurable)

**Environment Variables Set** (project-defined names, read only by `pi-nvim-bridge` via `process.env` — pi itself does not reserve or read these):
```lua
PI_IDE_PORT = tostring(port)
PI_IDE_AUTH = auth_token
PI_IDE_LOCKFILE = lock_path
```

**Configuration**:
```lua
terminal = {
  provider = "auto",
  split_side = "right",
  split_width_percentage = 0.30,
  auto_close = true,
}
```

### 4. Pi Extension: pi-nvim-bridge (`extensions/pi-nvim-bridge.ts`)

A TypeScript pi extension that runs inside pi's process and bridges tool calls to Neovim.

**Responsibilities**:
- Connect to Neovim's WebSocket server on `session_start`
- Disconnect and clean up on `session_shutdown`
- Register tools that delegate to Neovim via JSON-RPC over WebSocket
- Handle blocking tools (open_diff) using async/await on WebSocket responses, with the per-turn `AbortSignal` (5th `execute` arg is `ctx`; 3rd is `signal`) propagated so an Esc in pi cancels the pending request
- Signal tool failures by **throwing** from `execute` (a returned `{ error }` object does not set `isError`); JSON-RPC error responses from Neovim are converted to thrown errors in the message handler
- Optionally surface connection state inside pi's own TUI via `ctx.ui.setStatus(...)` / `ctx.ui.setWidget(...)`
- Forward Neovim notifications (selection changes) to pi context
- Implement reconnection with exponential backoff on connection drops

**Tools Registered**:

| Tool | Description | Blocking? |
|------|-------------|-----------|
| `nvim_open_file` | Open file in editor, optionally select range | No |
| `nvim_open_diff` | Show diff view for proposed changes | Yes |
| `nvim_get_selection` | Get current text selection | No |
| `nvim_get_latest_selection` | Get most recent selection (even if not active) | No |
| `nvim_get_open_editors` | List open buffers | No |
| `nvim_get_diagnostics` | Get LSP diagnostics | No |
| `nvim_get_workspace_folders` | Get workspace root | No |
| `nvim_check_dirty` | Check if buffer has unsaved changes | No |
| `nvim_save_document` | Save a buffer | No |
| `nvim_close_tab` | Close a buffer | No |
| `nvim_close_all_diff_tabs` | Close all diff buffers | No |

**Connection Lifecycle**:
```typescript
export default function (pi: ExtensionAPI) {
  let ws: WebSocket | null = null;
  let requestId = 0;
  const pending = new Map<string, { resolve, reject }>();
  let reconnectAttempts = 0;
  const maxReconnectDelay = 30000;

  function connect() {
    const port = process.env.PI_IDE_PORT;
    const auth = process.env.PI_IDE_AUTH;
    if (!port || !auth) return;

    ws = new WebSocket(`ws://127.0.0.1:${port}`, {
      headers: { "x-pi-ide-authorization": auth }
    });

    ws.on("open", () => {
      reconnectAttempts = 0;
      // Send initialize message
      const initId = `init-${Date.now()}`;
      pending.set(initId, { 
        resolve: () => {}, 
        reject: () => {} 
      });
      ws!.send(JSON.stringify({
        jsonrpc: "2.0",
        id: initId,
        method: "initialize",
        params: { protocolVersion: 1, supportedTools: ["open_file", "open_diff", ...] }
      }));
    });

    ws.on("message", (data) => {
      const msg = JSON.parse(data.toString());
      if (msg.id && pending.has(msg.id)) {
        const { resolve, reject } = pending.get(msg.id);
        pending.delete(msg.id);
        // JSON-RPC error → reject, so execute() throws. Pi signals tool
        // failure by a thrown error from execute(); returning an object with
        // an `error` field does NOT set isError.
        if (msg.error) reject(new Error(msg.error.message ?? "Neovim error"));
        else resolve(msg.result);
      }
    });

    ws.on("close", () => {
      // Reject all pending requests
      for (const [id, { reject }] of pending) {
        reject(new Error("WebSocket connection closed"));
      }
      pending.clear();
      
      // Attempt reconnection with exponential backoff
      const delay = Math.min(1000 * Math.pow(2, reconnectAttempts), maxReconnectDelay);
      reconnectAttempts++;
      setTimeout(connect, delay);
    });

    ws.on("error", (err) => {
      console.error("WebSocket error:", err);
      ws?.close();
    });
  }

  pi.on("session_start", async () => {
    connect();
  });

  pi.on("session_shutdown", async () => {
    ws?.close();
    ws = null;
  });

  // signal is pi's per-turn AbortSignal: when the user hits Esc in pi, the
  // pending request rejects so blocking tools (open_diff) tear down cleanly.
  function callNvim(method: string, params: object, signal?: AbortSignal): Promise<any> {
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      return Promise.reject(new Error("WebSocket not connected"));
    }
    if (signal?.aborted) return Promise.reject(new Error("Aborted"));
    const id = `req-${++requestId}`;
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      if (signal) {
        signal.addEventListener("abort", () => {
          if (pending.delete(id)) {
            // Tell Neovim to cancel any blocking UI (e.g. close the diff)
            ws?.send(JSON.stringify({ jsonrpc: "2.0", method: "cancel", params: { id } }));
            reject(new Error("Aborted"));
          }
        }, { once: true });
      }
      ws!.send(JSON.stringify({ jsonrpc: "2.0", id, method, params }));
    });
  }

  pi.registerTool({
    name: "nvim_open_file",
    label: "Open File",                          // required by pi's tool definition
    description: "Open a file in the Neovim editor, optionally selecting a line range",
    parameters: Type.Object({
      filePath: Type.String(),
      startLine: Type.Optional(Type.Number()),
      endLine: Type.Optional(Type.Number()),
    }),
    // Real pi signature: execute(toolCallId, params, signal, onUpdate, ctx)
    async execute(_toolCallId, params, signal) {
      const result = await callNvim("open_file", params, signal);
      return {
        content: [{ type: "text", text: JSON.stringify(result) }],
        details: {},
      };
    },
  });
  // ... more tools
}
```

### 5. Neovim Tool Handlers (`lua/pi-panel/handlers/`)

Lua modules that handle incoming JSON-RPC requests from the pi extension.

**Module**: `lua/pi-panel/handlers/init.lua`

```lua
local handlers = {}
-- request id -> cancel fn, for blocking tools (populated by the dispatch layer,
-- which passes the JSON-RPC request id to handlers as params._requestId)
local cancellations = {}

handlers["initialize"] = function(params)
  -- Capability negotiation happens on both sides: warn (don't reject) on mismatch
  if params.protocolVersion ~= 1 then
    vim.notify(
      ("pi-panel: protocol version mismatch (extension=%s, neovim=1)"):format(
        tostring(params.protocolVersion)),
      vim.log.levels.WARN)
  end
  return {
    protocolVersion = 1,
    supportedTools = { "open_file", "open_diff", "get_selection", ... }
  }
end

handlers["open_file"] = function(params)
  vim.schedule(function()
    vim.cmd("edit " .. vim.fn.fnameescape(params.filePath))
    if params.startLine then
      vim.api.nvim_win_set_cursor(0, { params.startLine, 0 })
    end
  end)
  return { content = {{ type = "text", text = "Opened " .. params.filePath }} }
end

handlers["open_diff"] = function(params, respond)
  local responded = false
  local timer  -- forward declaration so respond_once can stop it
  local function respond_once(result)
    if responded then return end
    responded = true
    if timer then timer:stop(); timer:close() end  -- don't leak the 5-min timer
    cancellations[params._requestId] = nil          -- drop the cancel registration
    respond(result)
  end

  -- Blocking: respond is called when user accepts or rejects
  local diff = require("pi-panel.diff")
  local view = diff.open(params, function(result)
    respond_once({ content = {{ type = "text", text = result }} })
  end)

  -- Register cancellation so an Esc in pi (which sends a `cancel` notification
  -- for this request id) closes the diff and unblocks the extension promise.
  cancellations[params._requestId] = function()
    view:close()
    respond_once({ error = { code = -32001, message = "Diff cancelled" } })
  end

  -- 5-minute timeout, stopped+closed by respond_once on early accept/reject/cancel
  timer = vim.defer_fn(function()
    respond_once({ error = { code = -32000, message = "Diff timeout (5 minutes)" } })
  end, 300000)
end

-- The dispatch layer routes a `cancel` notification (no id, params.id = the
-- cancelled request) to any registered cancellation for that request id.
handlers["cancel"] = function(params)
  local fn = cancellations[params.id]
  if fn then fn() end
end

-- ... more handlers
```

> Dispatch convention: a handler return with a `content` field becomes the JSON-RPC `result`; a return with an `error` field becomes the JSON-RPC `error`. The extension's message handler rejects the pending promise on `error`, so `execute()` throws — pi's required way to signal tool failure.

### 6. Diff Management (`lua/pi-panel/diff.lua`)

Native Neovim diff view for reviewing proposed changes.

**Features**:
- Side-by-side or inline diff (configurable)
- Accept changes (`:w` or `<leader>pa`)
- Reject changes (`:q` or `<leader>pr`)
- Edit before accepting
- Handles new files (empty buffer on left side)

**Blocking Behavior**:
- `open_diff` handler does not respond immediately
- Diff view opens with custom keymaps
- On accept: save the file, respond with `FILE_SAVED`
- On reject: close diff buffers, respond with `DIFF_REJECTED`
- On cancel (`cancel` notification from extension when pi's AbortSignal fires): close diff buffers, respond with `Diff cancelled` error
- On timeout (5 minutes): auto-reject and respond with `DIFF_TIMEOUT`
- All paths guarded by `respond_once` so the JSON-RPC response is sent exactly once

### 7. Selection Tracking (`lua/pi-panel/selection.lua`)

Automatically send selection context to pi via WebSocket notifications.

**Features**:
- Track visual mode selections with 50ms debounce using `vim.uv.new_timer()` with `timer:again()` (avoids allocating new libuv handle per keystroke)
- Send `selection_changed` notifications to pi extension
- Support `at_mentioned` events for explicit sends (`:PiSend`)
- Preserve selection context when switching to terminal

**Implementation**: Single timer created on plugin setup, reset on each `CursorMoved`/`CursorMovedI` event. Timer callback sends selection update after 50ms of inactivity.

### 8. Status & Progress (`lua/pi-panel/status.lua`)

Statusline integration showing pi connection state.

**Statusline Component**:
```lua
function M.statusline()
  if not server.is_running() then return "pi: off" end
  if not server.has_client() then return "pi: waiting" end
  return "pi: connected"
end
```

### 9. Commands (`lua/pi-panel/commands.lua`)

User-facing commands.

| Command | Description |
|---------|-------------|
| `:Pi` | Toggle pi panel |
| `:PiFocus` | Smart focus toggle |
| `:PiSend` | Send visual selection to pi (uses `vim.fn.chansend()` to write to terminal stdin) |
| `:PiAdd <file>` | Add file to pi context |
| `:PiAccept` | Accept current diff |
| `:PiReject` | Reject current diff |
| `:PiStart` | Start WebSocket server and launch pi |
| `:PiStop` | Stop server and close pi |
| `:PiStatus` | Show connection status, workspace, and pi instance info |
| `:PiReconnect` | Force reconnection to pi extension |

### 10. Which-Key Integration (`lua/pi-panel/whichkey.lua`)

Registers a `<leader>p` group with discoverable keymaps.

**Keymaps**:

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>pp` | `:Pi` | Toggle panel |
| `<leader>pf` | `:PiFocus` | Focus panel |
| `<leader>ps` | `:PiSend` | Send selection (visual) |
| `<leader>pa` | `:PiAccept` | Accept diff |
| `<leader>pr` | `:PiReject` | Reject diff |
| `<leader>pb` | `:PiAdd %` | Add current buffer |
| `<leader>px` | `:PiStop` | Stop pi |

## Project Structure

```
pi-panel.nvim/
├── lua/
│   └── pi-panel/
│       ├── init.lua              # Plugin entry point, setup()
│       ├── config.lua            # Configuration management
│       ├── server/               # WebSocket server
│       │   ├── init.lua          # Server lifecycle
│       │   ├── tcp.lua           # TCP server (vim.uv)
│       │   ├── handshake.lua     # HTTP upgrade + auth
│       │   ├── frame.lua         # RFC 6455 frame parser
│       │   ├── client.lua        # Connection management
│       │   └── utils.lua         # SHA-1, base64
│       ├── handlers/             # JSON-RPC request handlers
│       │   ├── init.lua          # Handler registry
│       │   ├── open_file.lua
│       │   ├── open_diff.lua
│       │   ├── get_selection.lua
│       │   ├── get_diagnostics.lua
│       │   └── ...
│       ├── terminal/             # Terminal providers
│       │   ├── init.lua          # Provider abstraction
│       │   ├── snacks.lua
│       │   ├── native.lua
│       │   └── external.lua
│       ├── lockfile.lua          # Discovery lock file
│       ├── diff.lua              # Diff view management
│       ├── selection.lua         # Selection tracking
│       ├── status.lua            # Statusline integration
│       ├── commands.lua          # User commands
│       ├── whichkey.lua          # Which-key registration
│       └── utils.lua             # Shared utilities
├── extensions/
│   └── pi-nvim-bridge/
│       ├── index.ts              # Pi extension entry point (source)
│       ├── ws-client.ts          # WebSocket client (uses `ws`)
│       ├── tools/                # Tool implementations
│       │   ├── open-file.ts
│       │   ├── open-diff.ts
│       │   ├── get-selection.ts
│       │   └── ...
│       ├── package.json          # deps: ws; peerDeps: typebox + @earendil-works/pi-*
│       ├── package-lock.json
│       └── dist/
│           └── index.js          # esbuild bundle (committed); ws + typebox inlined, type-only pi pkgs external
│                                 # launched via `pi -e .../dist/index.js`
├── plugin/
│   └── pi-panel.lua              # Auto-loaded commands
├── doc/
│   └── pi-panel.txt              # Help documentation
├── docs/
│   └── adr/                      # Architecture Decision Records
│       ├── 001-tui-side-channel.md
│       ├── 002-neovim-server.md
│       └── ...
├── tests/
│   ├── unit/                     # Busted unit tests
│   └── integration/              # End-to-end tests
├── .github/
│   └── workflows/
│       └── test.yml              # CI pipeline
├── README.md
├── CHANGELOG.md
├── LICENSE
└── Makefile
```

> `package.json`/`package-lock.json` live inside `extensions/pi-nvim-bridge/` (next to the code that imports the deps), not at the repo root. A root-level lock file with no root `package.json` should not exist.

## Configuration

```lua
require("pi-panel").setup({
  -- Auto-start WebSocket server and pi on Neovim launch
  auto_start = true,

  -- Port range for WebSocket server
  port_range = { min = 10000, max = 65535 },

  -- Pi binary path (nil = use "pi" from PATH)
  pi_cmd = nil,

  -- Custom environment variables for pi process
  env = {},

  -- Terminal settings
  terminal = {
    provider = "auto",  -- "auto" | "snacks" | "native" | "external"
    split_side = "right",
    split_width_percentage = 0.30,
    auto_close = true,
    snacks_win_opts = {},
  },

  -- Selection tracking
  track_selection = true,
  visual_demotion_delay_ms = 50,

  -- Connection settings
  connection_timeout = 10000,  -- ms to wait for pi to connect
  reconnect_max_delay = 30000, -- ms max delay between reconnection attempts

  -- Diff settings
  diff_opts = {
    layout = "vertical",       -- "vertical" | "horizontal"
    open_in_new_tab = false,
    keep_terminal_focus = false,
    timeout = 300,             -- seconds before auto-reject
  },

  -- Logging
  log_level = "info",  -- "trace" | "debug" | "info" | "warn" | "error"

  -- Which-key integration
  whichkey = {
    enabled = true,
    leader = "p",
  },
})
```

## Example Usage

```lua
-- lazy.nvim
{
  "user/pi-panel.nvim",
  dependencies = { 
    "folke/snacks.nvim",
    version = ">=2.0",
  },
  config = true,
}

-- With custom configuration
{
  "user/pi-panel.nvim",
  dependencies = { 
    "folke/snacks.nvim",
    version = ">=2.0",
  },
  opts = {
    terminal = {
      provider = "snacks",
      split_width_percentage = 0.35,
    },
    diff_opts = {
      layout = "vertical",
    },
  },
}
```

## Implementation Phases

### Phase 1: WebSocket Server + Lock File (3 weeks)
**Goal**: Neovim can accept WebSocket connections from pi

**Sub-phases**:

**1a. TCP + HTTP Upgrade (1 week)**:
- Implement TCP server binding to 127.0.0.1
- Parse HTTP upgrade request
- Validate headers and compute `Sec-WebSocket-Accept`
- Implement pure Lua SHA-1 and base64
- **Test**: Verify against RFC 6455 test vector: `dGhlIHNhbXBsZSBub25jZQ==` → `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=`
- **Deliverable**: TCP server completes handshake with Node.js `ws` client

**1b. Frame Parser (1 week)**:
- Parse text frames with fragmentation support
- Unmask client frames (XOR with masking key)
- Handle close/ping/pong control frames
- Handle extended payload lengths (126/127)
- **Test**: Known-good byte sequences, edge cases (zero-length, max-length)
- **Deliverable**: Server echoes messages back to client correctly

**1c. JSON-RPC Dispatch (1 week)**:
- Route incoming messages to handlers
- Format JSON-RPC 2.0 responses
- Handle notification vs request semantics
- Implement capability negotiation (`initialize` method)
- **Test**: Send `open_file` request, verify valid JSON-RPC response
- **Deliverable**: Server exchanges JSON-RPC messages with test client

**Lock File**:
- Implement atomic lock file creation (write to .tmp, rename)
- Include `workspaceFolders` and `displayName` (cwd basename) for multi-instance support
- Implement cleanup on `VimLeavePre`
- **Deliverable**: Lock file written with correct format, cleaned up on exit

**Auth Token**:
- Generate UUID v4 token
- Validate on WebSocket handshake via custom header
- **Deliverable**: Connections rejected without valid token

**Abort Criteria**: If Phase 1 exceeds 3 weeks, defer Phase 5 features (file tree integration, statusline integration) to maintain timeline.

### Phase 2: Terminal Panel + pi Launch (2 weeks)
**Goal**: pi runs in a Neovim panel with correct environment

1. Implement terminal provider abstraction
2. Implement snacks.nvim provider
3. Implement native provider (fallback)
4. Launch pi with `-e <abs>/extensions/pi-nvim-bridge/dist/index.js` and the `PI_IDE_PORT`, `PI_IDE_AUTH`, `PI_IDE_LOCKFILE` env vars
5. Toggle/focus commands
6. Auto-close on pi exit
7. esbuild bundle step (`make build`) producing the committed `dist/index.js`

**Deliverable**: `:Pi` toggles a panel with pi's TUI running inside it.

### Phase 3: pi-nvim-bridge Extension (2 weeks)
**Goal**: pi connects to Neovim and can call basic tools

1. Write `pi-nvim-bridge` TypeScript extension
2. WebSocket client connection with auth
3. Implement reconnection logic with exponential backoff (1s, 2s, 4s, max 30s)
4. Track in-flight requests and reject on disconnect
5. Implement `nvim_open_file` tool
6. Implement `nvim_get_selection` tool
7. Implement `nvim_get_workspace_folders` tool
8. Test end-to-end: pi calls tool, Neovim executes, result returns to pi

**Deliverable**: pi can open files and read selections in Neovim. Connection survives transient failures.

### Phase 4: Diff System (2 weeks)
**Goal**: Code review workflow with native Neovim diff

1. Implement `open_diff` handler (blocking)
2. Build diff view with native Neovim diff
3. Accept/reject keymaps and commands
4. Handle new files and deletions
5. Implement `:PiAccept`, `:PiReject`
6. Add 5-minute timeout with auto-reject

**Deliverable**: pi can propose changes, user reviews in diff view, result returns to pi.

### Phase 5: Remaining Tools + Polish (3 weeks)
**Goal**: Full feature parity

1. Implement remaining tool handlers (get_open_editors, get_diagnostics, check_dirty, save, close_tab)
2. Selection tracking with debounced notifications
3. File tree integration (nvim-tree, neo-tree, oil.nvim)
4. Which-key integration
5. Statusline integration
6. Native terminal provider
7. Comprehensive documentation
8. Integration test suite

**Deliverable**: Feature parity with claudecode.nvim. Ready for release.

**Buffer**: 2 weeks reserved after Phase 5 for debugging and polish.

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Pure Lua SHA-1 has bugs | Medium | High | Required because Neovim exposes `vim.fn.sha256()` but no SHA-1, while RFC 6455's `Sec-WebSocket-Accept` mandates SHA-1. Verify with RFC 6234 test vectors; matches claudecode.nvim's proven impl; shelling out to `sha1sum`/`openssl` is a fallback (avoided for the per-connection process cost) |
| RFC 6455 frame fragmentation edge cases | Medium | High | Test with autobahn-testsuite or Node.js test client sending fragmented messages |
| Pi's extension API changes | Low | High | Pin a known-compatible pi version for development; monitor pi changelog |
| Stale lock file after Neovim crash | Medium | Low | `VimLeavePre` is skipped on hard crash, leaking the lock. Sweep dead-pid locks in `~/.pi/ide/` on startup; extension probes `process.kill(pid, 0)` before any lock-discovered connect; auth token guards against pid reuse |
| Bundled `ws` drifts / vuln | Low | Low | `npm audit` in CI; `dist/index.js` regenerated by `make build` on dep bumps; pi-provided pkgs kept external so only `ws` is inlined |
| snacks.nvim terminal API breaks | Low | Medium | Native terminal provider always works as fallback |
| WebSocket connection drops in production | Medium | Medium | Exponential backoff reconnection; clear error messages; `:PiReconnect` command |
| Blocking diff tools hang indefinitely | Low | Medium | 5-minute timeout (timer stopped on early accept/reject/cancel to avoid leak) + AbortSignal-driven cancel; clear timeout error message |

## Key Design Decisions

### 1. TUI + Side Channel (not RPC mode)
**Decision**: Pi runs with its full TUI; a WebSocket side channel handles tool delegation.

**Rationale**: RPC mode is headless (replaces the TUI with JSON streams). The user wants pi's interactive TUI in the panel. The side channel approach (same as claudecode.nvim) gives both the TUI and bidirectional tool communication.

### 2. Neovim Runs the Server
**Decision**: Neovim owns the WebSocket server lifecycle.

**Rationale**: When Neovim closes, the server stops and the lock file is cleaned up. The pi extension is the client that connects on startup. This matches claudecode.nvim's architecture and is simpler to reason about.

### 3. JSON-RPC 2.0 Over WebSocket
**Decision**: Use JSON-RPC 2.0 for tool requests/responses.

**Rationale**: Same protocol as claudecode.nvim. Well-defined request/response/notification semantics. Supports blocking tools (open_diff) via request IDs.

### 4. Lock File + Environment Variables
**Decision**: Discovery via `~/.pi/ide/[port].lock` and `PI_IDE_PORT`/`PI_IDE_AUTH` env vars.

**Rationale**: Proven pattern from claudecode.nvim. Pi extensions have full Node.js access, so reading env vars and files is trivial.

### 5. Pi Extension (not SDK bridge)
**Decision**: Use a pi extension written in TypeScript, not a separate Node.js process.

**Rationale**: Extensions run inside pi's process with full Node.js access (`node:*` built-ins, `fetch`, npm deps), so a persistent WebSocket client is straightforward — **confirmed against pi's extension docs**, not assumed. The extension registers tools directly via `pi.registerTool()`, and `execute` is an awaited async function, so blocking tools (`open_diff`) work by awaiting the WebSocket response. No separate bridge process is needed; the extension is esbuild-bundled to a single `dist/index.js` for zero-install distribution and loaded with pi's `-e` flag. This resolves the two "medium-confidence" assumptions in the decision log (persistent connections; Promise-blocking returns); both hold.

## Testing Strategy

### Unit Tests (busted)
- WebSocket frame parser (RFC 6455 test vectors)
- Handshake and auth validation
- Lock file creation/removal
- Configuration validation
- Selection tracking debounce logic

**Coverage Target**: 80% for `server/` module (highest-risk code)

### Integration Tests
- Launch pi in terminal, verify WebSocket connection
- Send tool request from pi, verify Neovim executes it
- Test diff accept/reject flow end-to-end
- Test multiple Neovim instances (each with own server)
- Test reconnection after connection drop

### Manual Testing
- Fixtures directory with different Neovim configs
- Test with various file tree plugins
- Test with different terminal providers

### CI Pipeline
- GitHub Actions workflow on push
- Run `make test` (busted + npm test)
- Run `npm audit` for dependency vulnerability scanning
- Coverage report for `server/` module

## Build & Development

### Makefile Targets

```makefile
deps:        # npm install in extensions/pi-nvim-bridge/
build:       # esbuild bundle -> dist/index.js (ws + typebox inlined; type-only pi pkgs external)
test:        # Run busted + npm test
lint:        # Run stylua + eslint
typecheck:   # tsc --noEmit (type-check only; bundling is esbuild's job)
clean:       # Remove dist/ and test artifacts
```

> No global install step: the plugin launches pi with `-e <abs>/dist/index.js`, so there is nothing to symlink into `~/.pi/agent/extensions/`. The committed `dist/index.js` bundle means end users need no build; `make build` is a contributor step, run when the extension source changes.

### Toolchain Requirements
- Node.js 18+ (matches pi's baseline; the committed bundle removes any user-side dependency on `ws`)
- npm (for `ws` and esbuild as devDependencies, contributor-side only)
- esbuild (bundles the extension + `ws` into `dist/index.js`)
- luarocks (for busted test runner)
- stylua (for Lua formatting)
- eslint (for TypeScript linting)

## Connection Lifecycle Edge Cases

**Pi exits but Neovim stays open**:
- Server detects WebSocket close frame
- Updates statusline to "pi: disconnected"
- Clears pending requests with error
- User can restart with `:Pi`

**Neovim receives request after client disconnects**:
- Server checks if client is still connected before dispatching
- Logs warning if request arrives from disconnected client
- No response sent (client is gone)

**In-flight open_diff when either side crashes**:
- If Neovim crashes: pi extension's pending promise rejects with connection error
- If pi crashes: diff buffers remain open in Neovim; user can manually close or accept/reject
- 5-minute timeout ensures diff doesn't hang indefinitely

**Two requests arrive before first completes**:
- Handlers are reentrant and can execute in any order
- Each request has unique ID for response correlation
- Blocking tools (open_diff) use separate response callbacks
- No serialization required; concurrent execution is safe

## Comparison with claudecode.nvim

| Aspect | claudecode.nvim | pi-panel.nvim |
|--------|----------------|---------------|
| Agent CLI | Claude Code | pi |
| Protocol | WebSocket + MCP | WebSocket + JSON-RPC 2.0 |
| Server | Neovim (pure Lua) | Neovim (pure Lua) |
| Client | Claude Code CLI | pi extension (TypeScript) |
| Discovery | Lock file + env vars | Lock file + env vars |
| Tools | 12 MCP tools | ~12 JSON-RPC tools |
| Diff | Native Neovim | Native Neovim |
| Selection | Debounced tracking | Debounced tracking |
| Terminal | snacks + native | snacks + native + external |
| TUI | Claude's TUI in panel | pi's TUI in panel |
| Reconnection | Not documented | Exponential backoff |
| Protocol Versioning | Not documented | Capability negotiation |

## Security Considerations

- **Localhost only**: WebSocket server binds to 127.0.0.1
- **Auth token**: Random UUID validated on every connection
- **Lock file cleanup**: Removed on `VimLeavePre`
- **No network exposure**: All communication is local
- **Dependency scanning**: `npm audit` in CI pipeline

## Resources

- [Pi Extensions API](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md)
- [Pi RPC Protocol](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/rpc.md) (pi's own programmatic/RPC mode and extension-UI sub-protocol — **not** an editor-integration protocol)
- [Pi extension type definitions](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/src/core/extensions/types.ts)
- [claudecode.nvim Source](https://github.com/coder/claudecode.nvim)
- [claudecode.nvim Protocol](https://github.com/coder/claudecode.nvim/blob/main/PROTOCOL.md)
- [claudecode.nvim Architecture](https://github.com/coder/claudecode.nvim/blob/main/ARCHITECTURE.md)
- [RFC 6455 - WebSocket Protocol](https://tools.ietf.org/html/rfc6455)
- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
