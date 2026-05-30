# 4. JSON-RPC 2.0 protocol and blocking diff review

Status: accepted

## Context

The side channel needs request/response semantics, notifications, and a way to
model a blocking interaction (the user reviewing a proposed diff).

## Decision

Use JSON-RPC 2.0 over the WebSocket. Both sides exchange an `initialize`
message declaring `protocolVersion` and `supportedTools` (mismatches warn, not
reject, so the protocol can evolve). Requests carry an `id`; notifications
(e.g. `selection_changed`, `cancel`) omit it.

`open_diff` is a blocking tool: Neovim opens a native diff and does **not**
respond until the user accepts (`FILE_SAVED`), rejects (`DIFF_REJECTED`), the
request is cancelled, or a timeout fires. All paths funnel through a
`respond_once` guard so exactly one response is sent and the timeout timer is
always cleared.

## Consequences

- Cancellation: pi passes an `AbortSignal` to a tool's `execute`. On Esc the
  extension rejects its pending promise and sends a `cancel` notification
  carrying the request id; Neovim closes the diff. The dispatch layer injects
  the request id into handler params so the cancellation can be keyed correctly.
- Tool failure is signalled by a JSON-RPC error, which the extension converts
  into a thrown error from `execute` (pi's required failure convention).
- Reconnection: the extension reconnects with exponential backoff (1s/2s/4s,
  cap 30s) and rejects in-flight requests when the socket drops.
