-- Statusline integration. Users wire M.statusline() into their statusline, e.g.
--   lualine: { function() return require("pi-panel.status").statusline() end }

local M = {}

--- A short connection-state string, prefixed with the active agent name:
--- "pi: off" | "pi: waiting" | "pi: connected" (or "omp: …" under variant "omp").
---@return string
function M.statusline()
  local server = require("pi-panel.server")
  local name = require("pi-panel.config").get().display or "pi"
  if not server.is_running() then
    return name .. ": off"
  end
  if not server.has_client() then
    return name .. ": waiting"
  end
  return name .. ": connected"
end

return M
