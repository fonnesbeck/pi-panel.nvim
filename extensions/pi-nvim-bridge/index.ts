// pi-nvim-bridge — pi extension that bridges LLM tool calls to a Neovim editor
// over a WebSocket side channel (pi-panel.nvim, Phase 3).
//
// pi-panel.nvim launches pi with `pi -e <this bundle>` and injects PI_IDE_PORT
// / PI_IDE_AUTH into the environment. On session start we open a WebSocket to
// the Neovim-hosted JSON-RPC server and register tools whose execute() simply
// delegates to Neovim and awaits the response.
//
// Bundling note (see esbuild config in package.json): `ws` is inlined; the
// pi-provided packages (typebox, @earendil-works/pi-*) stay external so we use
// pi's own module instances at runtime.

import WebSocket from "ws";
import { Type } from "typebox";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { AgentToolResult } from "@earendil-works/pi-agent-core";
import { NvimBridge, type WebSocketLike } from "./bridge.ts";

// JSON-RPC method names this extension can call on Neovim (advertised in the
// initialize handshake; they map 1:1 to the nvim_* tools below).
const METHODS = ["open_file", "get_selection", "get_workspace_folders"];

function log(message: string): void {
  console.error(`[pi-nvim-bridge] ${message}`);
}

export default function (pi: ExtensionAPI): void {
  let bridge: NvimBridge | null = null;

  pi.on("session_start", () => {
    const port = process.env.PI_IDE_PORT;
    const auth = process.env.PI_IDE_AUTH;
    if (!port || !auth) {
      log("PI_IDE_PORT/PI_IDE_AUTH not set; this pi was not launched by pi-panel.nvim");
      return;
    }
    bridge = new NvimBridge({
      port,
      auth,
      supportedTools: METHODS,
      createSocket: (url, headers) =>
        new WebSocket(url, { headers }) as unknown as WebSocketLike,
      log,
    });
    bridge.connect();
    log(`connecting to Neovim on 127.0.0.1:${port}`);
  });

  pi.on("session_shutdown", () => {
    bridge?.close();
    bridge = null;
  });

  // Delegate a tool call to Neovim and wrap the JSON-RPC result as a pi tool
  // result. Throwing on failure is how pi marks a tool errored.
  async function call(
    method: string,
    params: object,
    signal?: AbortSignal,
  ): Promise<AgentToolResult<unknown>> {
    if (!bridge) {
      throw new Error("pi-nvim-bridge: not connected to Neovim");
    }
    const result = await bridge.callNvim(method, params, signal);
    const message = (result as { message?: unknown })?.message;
    const text = typeof message === "string" ? message : JSON.stringify(result);
    return { content: [{ type: "text", text }], details: result };
  }

  pi.registerTool({
    name: "nvim_open_file",
    label: "Open File in Neovim",
    description: "Open a file in the connected Neovim editor, optionally selecting a line range.",
    parameters: Type.Object({
      filePath: Type.String({ description: "Absolute path of the file to open" }),
      startLine: Type.Optional(
        Type.Number({ description: "1-indexed line to place the cursor / start the selection" }),
      ),
      endLine: Type.Optional(
        Type.Number({ description: "1-indexed end line of the selection" }),
      ),
    }),
    execute: (_id, params, signal) => call("open_file", params, signal),
  });

  pi.registerTool({
    name: "nvim_get_selection",
    label: "Get Neovim Selection",
    description: "Get the current visual selection in the connected Neovim editor.",
    parameters: Type.Object({}),
    execute: (_id, _params, signal) => call("get_selection", {}, signal),
  });

  pi.registerTool({
    name: "nvim_get_workspace_folders",
    label: "Get Neovim Workspace Folders",
    description: "Get the workspace root folders of the connected Neovim editor.",
    parameters: Type.Object({}),
    execute: (_id, _params, signal) => call("get_workspace_folders", {}, signal),
  });
}
