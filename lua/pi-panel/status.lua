-- Statusline integration. Users wire M.statusline() into their statusline, e.g.
--   lualine: { function() return require("pi-panel.status").statusline() end }

local M = {}

--- A short connection-state string: "pi: off" | "pi: waiting" | "pi: connected".
---@return string
function M.statusline()
  local server = require("pi-panel.server")
  if not server.is_running() then
    return "pi: off"
  end
  if not server.has_client() then
    return "pi: waiting"
  end
  return "pi: connected"
end

return M
