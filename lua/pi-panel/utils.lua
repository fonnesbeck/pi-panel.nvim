-- Shared utilities (path resolution, etc.). Distinct from server/utils.lua,
-- which holds the WebSocket crypto primitives (SHA-1, base64, uuid).

local M = {}

--- Absolute path to the plugin's repo root.
--- This file lives at <root>/lua/pi-panel/utils.lua, so the root is three
--- directory levels up from the script source.
---@return string
function M.plugin_root()
  local source = debug.getinfo(1, "S").source:sub(2) -- strip leading '@'
  return vim.fn.fnamemodify(source, ":h:h:h")
end

--- Absolute path to the committed pi-nvim-bridge esbuild bundle that pi loads
--- via `pi -e <path>`.
---@return string
function M.extension_path()
  return M.plugin_root() .. "/extensions/pi-nvim-bridge/dist/index.js"
end

return M
