import { test } from "node:test";
import assert from "node:assert/strict";
import { createBunSocket, isBun } from "../bun-socket.ts";

// A stand-in for Bun's native (browser-style) WebSocket: records the constructor
// args and addEventListener handlers, and lets the test dispatch events.
class FakeNativeWebSocket {
  static last: FakeNativeWebSocket | null = null;
  url: string;
  options: any;
  readyState = 0;
  sent: string[] = [];
  closed = false;
  private listeners: Record<string, ((ev: any) => void)[]> = {};

  constructor(url: string, options?: any) {
    this.url = url;
    this.options = options;
    FakeNativeWebSocket.last = this;
  }
  addEventListener(type: string, cb: (ev: any) => void): void {
    (this.listeners[type] ||= []).push(cb);
  }
  dispatch(type: string, ev?: any): void {
    (this.listeners[type] || []).forEach((cb) => cb(ev));
  }
  send(data: string): void {
    this.sent.push(data);
  }
  close(): void {
    this.closed = true;
  }
}

// Install the fake as the global WebSocket for the duration of `fn`, then restore.
function withFakeGlobal(fn: () => void): void {
  const saved = (globalThis as any).WebSocket;
  (globalThis as any).WebSocket = FakeNativeWebSocket;
  try {
    fn();
  } finally {
    (globalThis as any).WebSocket = saved;
  }
}

test("isBun() is false under Node (the test runtime)", () => {
  assert.equal(isBun(), false);
});

test("createBunSocket passes url + { headers } to the native WebSocket", () => {
  withFakeGlobal(() => {
    createBunSocket("ws://127.0.0.1:1234", { "x-pi-ide-authorization": "tok" });
    const ws = FakeNativeWebSocket.last!;
    assert.equal(ws.url, "ws://127.0.0.1:1234");
    assert.deepEqual(ws.options, { headers: { "x-pi-ide-authorization": "tok" } });
  });
});

test("readyState passes through and send/close delegate", () => {
  withFakeGlobal(() => {
    const sock = createBunSocket("ws://x", {});
    const ws = FakeNativeWebSocket.last!;
    ws.readyState = 1;
    assert.equal(sock.readyState, 1, "readyState reflects the live socket");
    sock.send("hello");
    assert.deepEqual(ws.sent, ["hello"], "send delegates");
    sock.close();
    assert.equal(ws.closed, true, "close delegates");
  });
});

test("open/close translate to zero-arg Node-style callbacks", () => {
  withFakeGlobal(() => {
    const sock = createBunSocket("ws://x", {});
    const ws = FakeNativeWebSocket.last!;
    let openArgs: unknown[] | null = null;
    let closeArgs: unknown[] | null = null;
    sock.on("open", (...a: unknown[]) => (openArgs = a));
    sock.on("close", (...a: unknown[]) => (closeArgs = a));
    ws.dispatch("open", { type: "open" });
    ws.dispatch("close", { type: "close", code: 1000 });
    assert.deepEqual(openArgs, [], "open callback gets no args");
    assert.deepEqual(closeArgs, [], "close callback gets no args");
  });
});

test("message translates MessageEvent.data to the raw payload", () => {
  withFakeGlobal(() => {
    const sock = createBunSocket("ws://x", {});
    const ws = FakeNativeWebSocket.last!;
    let received: unknown = null;
    sock.on("message", (data: unknown) => (received = data));
    ws.dispatch("message", { data: '{"jsonrpc":"2.0"}' });
    assert.equal(received, '{"jsonrpc":"2.0"}', "callback receives ev.data, not the MessageEvent");
  });
});

test("error translates to an Error (never a raw Event) with the event message", () => {
  withFakeGlobal(() => {
    const sock = createBunSocket("ws://x", {});
    const ws = FakeNativeWebSocket.last!;
    let err: unknown = null;
    sock.on("error", (e: unknown) => (err = e));
    ws.dispatch("error", { message: "boom" });
    assert.ok(err instanceof Error, "error callback receives an Error");
    assert.equal((err as Error).message, "boom");
  });
});

test("error without a message still yields an Error", () => {
  withFakeGlobal(() => {
    const sock = createBunSocket("ws://x", {});
    const ws = FakeNativeWebSocket.last!;
    let err: unknown = null;
    sock.on("error", (e: unknown) => (err = e));
    ws.dispatch("error", {}); // raw Event-like, no message
    assert.ok(err instanceof Error);
    assert.equal((err as Error).message, "websocket error");
  });
});
