import { test } from "node:test";
import assert from "node:assert/strict";
import { NvimBridge, backoffDelay, WS_OPEN, type WebSocketLike } from "../bridge.ts";

// A controllable stand-in for the `ws` WebSocket: records sent frames and lets
// the test drive open/message/close/error events.
class FakeSocket implements WebSocketLike {
  readyState = WS_OPEN;
  sent: string[] = [];
  headers: Record<string, string>;
  private handlers: Record<string, ((...a: unknown[]) => void)[]> = {};

  constructor(headers: Record<string, string> = {}) {
    this.headers = headers;
  }
  send(data: string): void {
    this.sent.push(data);
  }
  close(): void {
    this.readyState = 3;
    this.emit("close");
  }
  on(event: string, cb: (...a: unknown[]) => void): void {
    (this.handlers[event] ||= []).push(cb);
  }
  emit(event: string, ...args: unknown[]): void {
    (this.handlers[event] || []).forEach((h) => h(...args));
  }
  lastSent(): any {
    return JSON.parse(this.sent[this.sent.length - 1]);
  }
}

function makeBridge() {
  let socket: FakeSocket | null = null;
  const scheduled: { fn: () => void; ms: number }[] = [];
  const bridge = new NvimBridge({
    port: "4321",
    auth: "tok",
    supportedTools: ["open_file"],
    createSocket: (_url, headers) => {
      socket = new FakeSocket(headers);
      return socket;
    },
    schedule: (fn, ms) => {
      scheduled.push({ fn, ms });
    },
  });
  return {
    bridge,
    scheduled,
    get socket() {
      return socket as FakeSocket;
    },
  };
}

test("backoffDelay grows exponentially and caps at maxDelay", () => {
  assert.equal(backoffDelay(0, 30000), 1000);
  assert.equal(backoffDelay(1, 30000), 2000);
  assert.equal(backoffDelay(2, 30000), 4000);
  assert.equal(backoffDelay(10, 30000), 30000);
});

test("sends an initialize handshake on open", () => {
  const h = makeBridge();
  h.bridge.connect();
  h.socket.emit("open");
  const msg = h.socket.lastSent();
  assert.equal(msg.method, "initialize");
  assert.equal(msg.params.protocolVersion, 1);
  assert.deepEqual(msg.params.supportedTools, ["open_file"]);
});

test("passes the auth header to the socket", () => {
  const h = makeBridge();
  h.bridge.connect();
  assert.equal(h.socket.headers["x-pi-ide-authorization"], "tok");
});

test("callNvim resolves with the matching JSON-RPC result", async () => {
  const h = makeBridge();
  h.bridge.connect();
  h.socket.emit("open");
  const p = h.bridge.callNvim("get_workspace_folders", {});
  const req = h.socket.lastSent();
  assert.equal(req.method, "get_workspace_folders");
  h.socket.emit("message", JSON.stringify({ jsonrpc: "2.0", id: req.id, result: { folders: ["/x"] } }));
  assert.deepEqual(await p, { folders: ["/x"] });
});

test("callNvim rejects when Neovim returns a JSON-RPC error", async () => {
  const h = makeBridge();
  h.bridge.connect();
  h.socket.emit("open");
  const p = h.bridge.callNvim("open_file", { filePath: "/nope" });
  const req = h.socket.lastSent();
  h.socket.emit(
    "message",
    JSON.stringify({ jsonrpc: "2.0", id: req.id, error: { code: -32000, message: "boom" } }),
  );
  await assert.rejects(p, /boom/);
});

test("callNvim rejects immediately when the socket is not open", async () => {
  const h = makeBridge();
  h.bridge.connect();
  h.socket.readyState = 0; // CONNECTING
  await assert.rejects(h.bridge.callNvim("open_file", {}), /not connected/i);
});

test("closing rejects in-flight requests and schedules a reconnect", async () => {
  const h = makeBridge();
  h.bridge.connect();
  h.socket.emit("open");
  const p = h.bridge.callNvim("open_file", {});
  h.socket.emit("close");
  await assert.rejects(p, /closed/i);
  assert.equal(h.scheduled.length, 1, "one reconnect scheduled");
  assert.equal(h.scheduled[0].ms, 1000, "first reconnect after 1s");
});

test("a user-initiated close does not schedule a reconnect", () => {
  const h = makeBridge();
  h.bridge.connect();
  h.socket.emit("open");
  h.bridge.close();
  assert.equal(h.scheduled.length, 0);
});

test("aborting a request sends a cancel notification and rejects", async () => {
  const h = makeBridge();
  h.bridge.connect();
  h.socket.emit("open");
  const ac = new AbortController();
  const p = h.bridge.callNvim("open_diff", {}, ac.signal);
  const req = h.socket.lastSent();
  ac.abort();
  const cancel = h.socket.lastSent();
  assert.equal(cancel.method, "cancel");
  assert.equal(cancel.params.id, req.id);
  await assert.rejects(p, /abort/i);
});
