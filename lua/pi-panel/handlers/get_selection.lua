-- get_selection: return the active buffer's current visual selection. The read
-- logic lives in pi-panel.selection (shared with tracking + get_latest_selection).

local M = {}

---@param _ table
---@param respond fun(result: table)
function M.handle(_, respond)
  vim.schedule(function()
    respond(require("pi-panel.selection").current())
  end)
end

return M
