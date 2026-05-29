// NvimBridge: the WebSocket client half of pi-panel.nvim. It connects to the
// Neovim-hosted JSON-RPC server, performs the auth + initialize handshake,
// correlates requests/responses, reconnects with exponential backoff, and
// rejects in-flight requests when the connection drops.
//
// The socket and timer are injected (createSocket / schedule) so the logic is
// unit-testable without a real network or wall-clock delays.

/** The subset of the `ws` WebSocket API this bridge depends on. */
export interface WebSocketLike {
  readyState: number;
  send(data: string): void;
  close(): void;
  on(event: string, cb: (...args: any[]) => void): void;
}

/** ws WebSocket.OPEN. */
export const WS_OPEN = 1;

const PROTOCOL_VERSION = 1;
const AUTH_HEADER = "x-pi-ide-authorization";

/** Exponential backoff: 1s, 2s, 4s, … capped at maxDelay. */
export function backoffDelay(attempt: number, maxDelay: number): number {
  return Math.min(1000 * Math.pow(2, attempt), maxDelay);
}

type Pending = { resolve: (value: any) => void; reject: (error: Error) => void };

export interface BridgeOptions {
  port: string;
  auth: string;
  supportedTools: string[];
  maxReconnectDelay?: number;
  createSocket: (url: string, headers: Record<string, string>) => WebSocketLike;
  /** Defaults to setTimeout; injected in tests to capture reconnect scheduling. */
  schedule?: (fn: () => void, ms: number) => void;
  log?: (message: string) => void;
}

export class NvimBridge {
  private ws: WebSocketLike | null = null;
  private readonly pending = new Map<string, Pending>();
  private requestId = 0;
  private reconnectAttempts = 0;
  private userClosed = false;

  private readonly opts: BridgeOptions;
  private readonly maxReconnectDelay: number;
  private readonly schedule: (fn: () => void, ms: number) => void;
  private readonly log: (message: string) => void;

  constructor(opts: BridgeOptions) {
    this.opts = opts;
    this.maxReconnectDelay = opts.maxReconnectDelay ?? 30000;
    this.schedule = opts.schedule ?? ((fn, ms) => void setTimeout(fn, ms));
    this.log = opts.log ?? (() => {});
  }

  isConnected(): boolean {
    return this.ws !== null && this.ws.readyState === WS_OPEN;
  }

  /** Test/inspection helper. */
  pendingCount(): number {
    return this.pending.size;
  }

  connect(): void {
    this.userClosed = false;
    const url = `ws://127.0.0.1:${this.opts.port}`;
    const ws = this.opts.createSocket(url, { [AUTH_HEADER]: this.opts.auth });
    this.ws = ws;

    ws.on("open", () => this.onOpen());
    ws.on("message", (data: unknown) => this.onMessage(String(data)));
    ws.on("close", () => this.onClose());
    ws.on("error", (err: unknown) => {
      this.log(`WebSocket error: ${err instanceof Error ? err.message : String(err)}`);
      this.ws?.close();
    });
  }

  /** Close intentionally; suppresses the reconnect loop. */
  close(): void {
    this.userClosed = true;
    this.ws?.close();
    this.ws = null;
  }

  private onOpen(): void {
    this.reconnectAttempts = 0;
    const id = `init-${++this.requestId}`;
    // Resolve the negotiation locally; warn on a protocol mismatch.
    this.pending.set(id, {
      resolve: (result: { protocolVersion?: number }) => {
        if (result?.protocolVersion !== PROTOCOL_VERSION) {
          this.log(
            `protocol version mismatch (neovim=${result?.protocolVersion}, extension=${PROTOCOL_VERSION})`,
          );
        }
      },
      reject: () => {},
    });
    this.send({
      jsonrpc: "2.0",
      id,
      method: "initialize",
      params: { protocolVersion: PROTOCOL_VERSION, supportedTools: this.opts.supportedTools },
    });
  }

  private onMessage(raw: string): void {
    let msg: any;
    try {
      msg = JSON.parse(raw);
    } catch {
      this.log(`dropping unparseable message: ${raw}`);
      return;
    }
    if (msg.id == null) return; // notification from Neovim (handled in Phase 5)
    const entry = this.pending.get(msg.id);
    if (!entry) return;
    this.pending.delete(msg.id);
    // Pi signals tool failure via a thrown error from execute(), so a JSON-RPC
    // error must reject (not resolve with an { error } object).
    if (msg.error) {
      entry.reject(new Error(msg.error.message ?? "Neovim error"));
    } else {
      entry.resolve(msg.result);
    }
  }

  private onClose(): void {
    this.ws = null;
    const err = new Error("WebSocket connection closed");
    for (const { reject } of this.pending.values()) reject(err);
    this.pending.clear();

    if (this.userClosed) return;
    const delay = backoffDelay(this.reconnectAttempts, this.maxReconnectDelay);
    this.reconnectAttempts++;
    this.schedule(() => this.connect(), delay);
  }

  /**
   * Send a JSON-RPC request to Neovim and resolve with its result. `signal` is
   * pi's per-turn AbortSignal: an Esc in pi rejects the promise and tells
   * Neovim to tear down any blocking UI (e.g. the diff) via a cancel notice.
   */
  callNvim(method: string, params: object, signal?: AbortSignal): Promise<any> {
    if (!this.isConnected()) {
      return Promise.reject(new Error("WebSocket not connected"));
    }
    if (signal?.aborted) {
      return Promise.reject(new Error("Aborted"));
    }
    const id = `req-${++this.requestId}`;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      if (signal) {
        signal.addEventListener(
          "abort",
          () => {
            if (this.pending.delete(id)) {
              this.send({ jsonrpc: "2.0", method: "cancel", params: { id } });
              reject(new Error("Aborted"));
            }
          },
          { once: true },
        );
      }
      this.send({ jsonrpc: "2.0", id, method, params });
    });
  }

  private send(message: object): void {
    this.ws?.send(JSON.stringify(message));
  }
}
