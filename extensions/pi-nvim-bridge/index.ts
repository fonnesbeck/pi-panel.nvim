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
const METHODS = [
  "open_file",
  "open_diff",
  "get_selection",
  "get_latest_selection",
  "get_workspace_folders",
  "get_open_editors",
  "get_diagnostics",
  "check_dirty",
  "save_document",
  "close_tab",
  "close_all_diff_tabs",
];

function log(message: string): void {
  console.error(`[pi-nvim-bridge] ${message}`);
}

export default function (pi: ExtensionAPI): void {
  let bridge: NvimBridge | null = null;
  // Latest selection pushed by Neovim's selection tracking (informational; the
  // nvim_get_latest_selection tool reads the authoritative copy from Neovim).
  let latestSelection: unknown = null;

  pi.on("session_start", () => {
    const port = process.env.PI_IDE_PORT;
    const auth = process.env.PI_IDE_AUTH;
    if (!port || !auth) {
      log("PI_IDE_PORT/PI_IDE_AUTH not set; this pi was not launched by pi-panel.nvim");
      return;
    }
    const maxReconnectDelay = Number(process.env.PI_IDE_RECONNECT_MAX_DELAY);
    bridge = new NvimBridge({
      port,
      auth,
      supportedTools: METHODS,
      maxReconnectDelay: Number.isFinite(maxReconnectDelay) && maxReconnectDelay > 0
        ? maxReconnectDelay
        : undefined,
      createSocket: (url, headers) =>
        new WebSocket(url, { headers }) as unknown as WebSocketLike,
      log,
      onNotification: (method, params) => {
        if (method === "selection_changed") {
          latestSelection = params;
        }
      },
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
    name: "nvim_open_diff",
    label: "Open Diff in Neovim",
    description:
      "Show proposed changes to a file as a diff in Neovim and BLOCK until the " +
      "user accepts (FILE_SAVED) or rejects (DIFF_REJECTED) them. Use this to let " +
      "the user review edits before they are written to disk.",
    parameters: Type.Object({
      filePath: Type.String({ description: "Absolute path of the file being changed" }),
      newContents: Type.String({ description: "Full proposed contents of the file" }),
      oldContents: Type.Optional(
        Type.String({ description: "Original contents for the left side (defaults to the file on disk)" }),
      ),
    }),
    execute: (_id, params, signal) => call("open_diff", params, signal),
  });

  pi.registerTool({
    name: "nvim_get_selection",
    label: "Get Neovim Selection",
    description: "Get the current visual selection in the connected Neovim editor.",
    parameters: Type.Object({}),
    execute: (_id, _params, signal) => call("get_selection", {}, signal),
  });

  pi.registerTool({
    name: "nvim_get_latest_selection",
    label: "Get Latest Neovim Selection",
    description:
      "Get the most recent selection tracked in Neovim, even if the user is no longer selecting.",
    parameters: Type.Object({}),
    execute: (_id, _params, signal) => call("get_latest_selection", {}, signal),
  });

  pi.registerTool({
    name: "nvim_get_workspace_folders",
    label: "Get Neovim Workspace Folders",
    description: "Get the workspace root folders of the connected Neovim editor.",
    parameters: Type.Object({}),
    execute: (_id, _params, signal) => call("get_workspace_folders", {}, signal),
  });

  pi.registerTool({
    name: "nvim_get_open_editors",
    label: "Get Open Editors",
    description: "List the files currently open in the connected Neovim editor.",
    parameters: Type.Object({}),
    execute: (_id, _params, signal) => call("get_open_editors", {}, signal),
  });

  pi.registerTool({
    name: "nvim_get_diagnostics",
    label: "Get Diagnostics",
    description:
      "Get LSP diagnostics from Neovim, for one file (filePath) or all open buffers.",
    parameters: Type.Object({
      filePath: Type.Optional(Type.String({ description: "Limit to this file (absolute path)" })),
    }),
    execute: (_id, params, signal) => call("get_diagnostics", params, signal),
  });

  pi.registerTool({
    name: "nvim_check_dirty",
    label: "Check Unsaved Changes",
    description: "Check whether a file has unsaved changes in Neovim.",
    parameters: Type.Object({
      filePath: Type.Optional(Type.String({ description: "File to check (defaults to the active buffer)" })),
    }),
    execute: (_id, params, signal) => call("check_dirty", params, signal),
  });

  pi.registerTool({
    name: "nvim_save_document",
    label: "Save Document",
    description: "Save a file's buffer to disk in Neovim.",
    parameters: Type.Object({
      filePath: Type.String({ description: "Absolute path of the file to save" }),
    }),
    execute: (_id, params, signal) => call("save_document", params, signal),
  });

  pi.registerTool({
    name: "nvim_close_tab",
    label: "Close Tab",
    description: "Close the buffer/tab for a file in Neovim.",
    parameters: Type.Object({
      filePath: Type.String({ description: "Absolute path of the file to close" }),
    }),
    execute: (_id, params, signal) => call("close_tab", params, signal),
  });

  pi.registerTool({
    name: "nvim_close_all_diff_tabs",
    label: "Close All Diff Tabs",
    description: "Close every open diff view in Neovim (rejecting any pending review).",
    parameters: Type.Object({}),
    execute: (_id, _params, signal) => call("close_all_diff_tabs", {}, signal),
  });
}
