-- get_latest_selection: return the most recently tracked selection, even if the
-- user is no longer in visual mode (the cache is maintained by pi-panel.selection).

local M = {}

---@param _ table
---@param respond fun(result: table)
function M.handle(_, respond)
  vim.schedule(function()
    respond(require("pi-panel.selection").latest())
  end)
end

return M
