# 1. TUI + WebSocket side channel (not RPC mode)

Status: accepted

## Context

pi can run headless in an RPC mode that replaces its TUI with JSON streams. We
want pi's full interactive TUI inside a Neovim panel *and* the ability for pi to
call back into the editor (open files, diffs, selections).

## Decision

Run pi with its normal TUI in a Neovim terminal panel, and add a separate
WebSocket side channel for editor tool calls — the same architecture as
claudecode.nvim. RPC mode is not used.

## Consequences

- Users get pi's real TUI, not a reimplementation.
- Tool delegation is independent of the TUI: a pi extension holds a persistent
  WebSocket connection to Neovim and registers tools that forward over it.
- Two transports coexist: the terminal (stdin/stdout, for the TUI and `:PiSend`
  via `chansend`) and the WebSocket (JSON-RPC, for tools).
