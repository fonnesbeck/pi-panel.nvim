# 2. Neovim hosts the WebSocket server

Status: accepted

## Context

Either side could own the WebSocket server. We need a clear lifecycle owner and
a discovery mechanism.

## Decision

Neovim hosts the server (pure Lua over `vim.uv`, bound to 127.0.0.1 on a random
port) and is the source of truth for its lifecycle. The pi extension is the
client that connects on session start. Discovery is a lock file at
`~/.pi/ide/[port].lock` plus `PI_IDE_PORT` / `PI_IDE_AUTH` env vars that Neovim
sets when launching pi.

## Consequences

- When Neovim exits, the server stops and the lock file is removed
  (`VimLeavePre`); stale locks from crashes are swept on startup by checking the
  recorded pid.
- A pure-Lua RFC 6455 implementation is required (SHA-1, base64, framing), since
  Neovim exposes no native WebSocket. This is the highest-risk code and is the
  most heavily unit-tested.
- Security: localhost-only bind + an auth token validated on the WebSocket
  upgrade handshake.
