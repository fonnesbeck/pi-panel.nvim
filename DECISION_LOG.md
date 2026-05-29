# Socratic Review Decision Log

## Goal Restatement
Build a Neovim plugin (pi-panel.nvim) that gives pi users the same UX as claudecode.nvim gives Claude Code users: pi's TUI running in a Neovim side panel with a WebSocket side channel enabling pi to open files, show diffs, access selections, and call back into the editor.

## Key Assumptions
| Assumption | Confidence | Basis |
|------------|-----------|-------|
| Feature parity with claudecode.nvim is the right target | high | User has used claudecode.nvim in real work and wants the same UX for pi |
| Pi's TUI must run in the panel (not RPC mode) | high | User explicitly rejected headless RPC approach |
| Pi extensions can maintain persistent WebSocket connections | medium | Doom-overlay and subagent examples show persistent state and child process management, but no example shows long-lived network connections |
| Pi's tool `execute` can return a Promise that blocks until WebSocket response arrives | medium | Tool execute is async, but blocking behavior hasn't been validated against pi's tool execution pipeline |
| claudecode.nvim's pure Lua WebSocket server can be adapted for pi-panel.nvim | high | Proven in production with Claude Code CLI |
| Neovim's `vim.loop` event loop handles WebSocket I/O without blocking the UI | medium | claudecode.nvim works in production, but pi's tool call patterns may differ |
| Lock file + env var discovery works for pi extensions | high | Pi extensions have full Node.js access (fs, process.env) |

## Dependencies Mapped
| Dependency | Blocker? | Mitigation |
|------------|----------|------------|
| Pi extension system supports persistent WebSocket connections | yes | Validate in Phase 1; fall back to RPC subprocess bridge if it doesn't work |
| Pi tool execute supports blocking (Promise-based) returns | yes | Validate in Phase 1; use callback pattern if Promises don't block |
| snacks.nvim availability for terminal provider | no | Native `termopen` fallback always available |
| which-key availability for keymap registration | no | Auto-detect; skip registration if not installed |
| `ws` npm package for pi extension WebSocket client | no | Can use Node.js built-in `net` module with manual framing |

## Risks Identified
- Risk: Pi extension cannot maintain persistent WebSocket connections across tool calls
  - Likelihood: low
  - Impact: high
  - Mitigation: Validate in Phase 1 with a minimal proof-of-concept extension. If it fails, pivot to an RPC subprocess bridge where a separate Node.js process maintains the WebSocket and pi communicates with it via stdin/stdout.

- Risk: Pi's tool execution model doesn't support blocking returns (Promise that waits for WebSocket response)
  - Likelihood: low
  - Impact: high
  - Mitigation: Test in Phase 1. If blocking doesn't work, use pi's `pi.sendMessage()` to deliver tool results asynchronously instead of blocking the tool return.

- Risk: WebSocket server in pure Lua causes Neovim UI lag under rapid tool calls
  - Likelihood: low
  - Impact: medium
  - Mitigation: claudecode.nvim works in production. Use `vim.schedule()` for all Neovim API calls from async contexts. Profile during Phase 1 testing.

- Risk: Scope creep from "and more" features beyond claudecode.nvim parity
  - Likelihood: medium
  - Impact: medium
  - Mitigation: User explicitly confirmed feature parity only. No extra features for v1. Plan documents exactly 12 tools matching claudecode.nvim.

## Open Questions Remaining
- [ ] Can a pi extension maintain a persistent WebSocket connection for the entire session lifecycle? (Validate in Phase 1)
- [ ] Does pi's tool `execute` function support blocking returns via Promises? (Validate in Phase 1)
- [ ] How does pi's parallel tool execution interact with WebSocket request/response correlation? (Test in Phase 3)

## Branch Resolution Status
| Branch | Status | Notes |
|--------|--------|-------|
| Goal and scope | resolved | Feature parity with claudecode.nvim. No extra features for v1. User has used claudecode.nvim and wants the same UX for pi. |
| TUI vs RPC mode | resolved | Pi's TUI must run in the panel. RPC mode rejected because it's headless (no interactive TUI). |
| Architecture | resolved | TUI in terminal panel + WebSocket side channel. Neovim runs server, pi extension connects as client. JSON-RPC 2.0 protocol. |
| Protocol | resolved | WebSocket (RFC 6455) with JSON-RPC 2.0 messages. Same as claudecode.nvim. |
| Server location | resolved | Neovim runs the WebSocket server. Pi extension connects as client. Neovim owns lifecycle. |
| Discovery | resolved | Lock file at `~/.pi/ide/[port].lock` with auth token. Environment variables `PI_IDE_PORT`, `PI_IDE_AUTH`, `PI_IDE_LOCKFILE`. |
| Multiple instances | resolved | One pi per Neovim instance. Each Neovim runs its own server on a unique port. |
| Error handling | resolved | Follow claudecode.nvim: 30s ping/pong keepalive, deferred responses cleared on server stop, diff buffers survive pi exit, request ID correlation for parallel calls. |
| Tool scope and prioritization | resolved | Phased approach: Phase 3 = core tools (3), Phase 4 = diff system, Phase 5 = remaining tools (8). All 12 tools for v1. |
| Blocking tools | resolved | open_diff uses deferred response pattern from claudecode.nvim (coroutines in Lua, Promises in TypeScript). Validate pi supports this in Phase 1. |
| Which-key integration | resolved | Auto-register `<leader>p` group if which-key is available. 7 keymaps organized by function. |
| Terminal providers | resolved | snacks.nvim (default), native `termopen` (fallback), external (future). Provider pattern for extensibility. |
| Testing strategy | resolved | Unit tests (busted) for frame parser, handshake, config. Integration tests for end-to-end tool flow. Manual testing with fixtures. |
