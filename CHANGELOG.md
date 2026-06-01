# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed

- The `variant = "omp"` (oh-my-pi) path couldn't connect: omp runs on Bun, whose
  `node:http` breaks the bundled `ws` client handshake (`Unexpected server
  response: 101`). The bridge now uses Bun's native WebSocket under Bun and keeps
  `ws` for Node (pi). The omp integration check (`make test-omp`) now asserts a
  completed handshake (the server received the `initialize` frame) instead of mere
  TCP accept, which was a false positive.

### Changed

- `:PiReconnect` restarts the server + pi to recover a wedged connection.
- `reconnect_max_delay`, `connection_timeout`, and `diff_opts.keep_terminal_focus`
  are now wired (previously declared but unused). `reconnect_max_delay` is passed
  to the extension via `PI_IDE_RECONNECT_MAX_DELAY`.
- Removed the unused `port_range` and `log_level` config fields, and dropped the
  not-yet-implemented `external` terminal provider from accepted values (it now
  fails validation at `setup()` instead of crashing on open).
- Makefile gained an `audit` target and a guarded `eslint` lint step.

### Added

- Pure-Lua WebSocket server (`vim.uv`, RFC 6455) bound to localhost, with an
  auth token validated on the upgrade handshake, and a `~/.pi/ide/[port].lock`
  discovery lock file with stale-lock sweeping. (Phase 1)
- Terminal panel that launches pi with the bundled extension and `PI_IDE_*`
  discovery env vars; snacks.nvim and native terminal providers; `:Pi`,
  `:PiFocus`, `:PiStart`, `:PiStop`, `:PiStatus`. (Phase 2)
- `pi-nvim-bridge` extension: WebSocket client with auth, capability
  negotiation, exponential-backoff reconnection, and in-flight request
  tracking. Tools `nvim_open_file`, `nvim_get_selection`,
  `nvim_get_workspace_folders`. (Phase 3)
- Blocking diff review: `nvim_open_diff`, native side-by-side diff, accept/reject
  via `:PiAccept`/`:PiReject`/`<leader>pa`/`<leader>pr`/`:w`, AbortSignal-driven
  cancel, and a configurable auto-reject timeout. (Phase 4)
- Remaining tools: `nvim_get_open_editors`, `nvim_get_diagnostics`,
  `nvim_check_dirty`, `nvim_save_document`, `nvim_close_tab`,
  `nvim_close_all_diff_tabs`. (Phase 5)
- Debounced selection tracking with `selection_changed` notifications,
  `nvim_get_latest_selection`, and `:PiSend` / `:PiAdd`. (Phase 5)
- which-key `<leader>p` group, statusline component, best-effort file-tree
  integration (nvim-tree / oil / neo-tree). (Phase 5)
- Documentation (README, `:help pi-panel`, ADRs), CI workflow, and an
  end-to-end integration test suite. (Phase 5)
- `variant` config option (`"pi"` | `"omp"`, default `"pi"`) to drive oh-my-pi
  (`omp`) instead of pi: selects the binary and its `~/.<variant>/ide` lock dir,
  and names the active agent in status/statusline messages. `pi_cmd` overrides the
  binary. Gated `make test-omp` integration check.
