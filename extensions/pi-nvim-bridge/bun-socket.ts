// Bun WebSocket client adapter.
//
// omp runs on Bun. The npm `ws` library's *client* handshake relies on Node's
// `http` emitting the 'upgrade' event for a 101 response; Bun's node:http does
// not, so `ws` reports `Unexpected server response: 101` and never connects.
// Bun ships a native, browser-style global WebSocket that connects correctly and
// (non-standard) accepts a `{ headers }` option, so we use it under Bun and keep
// `ws` for Node (pi).
//
// NOTE on the `as any` casts below: this file targets both runtimes and the
// extension's tsconfig has no DOM lib and no `bun-types` dependency, so the
// global `WebSocket`/`MessageEvent`/`addEventListener` types aren't available.
// The casts are deliberate — do not "clean them up" by adding DOM/bun-types or
// the Node build breaks. The `{ headers }` option is a Bun extension (verified on
// Bun 1.3.14, omp's minimum `engines.bun`); browsers/Node ignore it, so this path
// must stay Bun-only.

import type { WebSocketLike } from "./bridge.ts";

/** True when running under the Bun runtime. */
export function isBun(): boolean {
  return (
    typeof (globalThis as any).Bun !== "undefined" ||
    (typeof process !== "undefined" && Boolean((process as any).versions?.bun))
  );
}

/**
 * Create a Bun-native WebSocket client adapted to the Node-style `WebSocketLike`
 * interface the bridge expects. Bun's WebSocket is browser-style
 * (addEventListener / MessageEvent.data), so we translate it to `.on(event, cb)`.
 */
export function createBunSocket(url: string, headers: Record<string, string>): WebSocketLike {
  const NativeWebSocket = (globalThis as any).WebSocket;
  const ws = new NativeWebSocket(url, { headers });
  return {
    get readyState(): number {
      return ws.readyState; // Bun OPEN === 1 === WS_OPEN
    },
    send(data: string): void {
      ws.send(data);
    },
    close(): void {
      ws.close();
    },
    on(event: string, cb: (...args: any[]) => void): void {
      if (event === "message") {
        ws.addEventListener("message", (ev: any) => cb(ev.data));
      } else if (event === "error") {
        // The bridge logs `err.message`; hand it a real Error, not a raw Event.
        ws.addEventListener("error", (ev: any) =>
          cb(ev instanceof Error ? ev : new Error(ev?.message ?? "websocket error")),
        );
      } else {
        // "open" | "close": the bridge's handlers take no arguments.
        ws.addEventListener(event, () => cb());
      }
    },
  };
}
