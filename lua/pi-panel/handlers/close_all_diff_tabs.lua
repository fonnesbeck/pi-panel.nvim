-- close_all_diff_tabs: tear down every open diff (rejecting each so any pending
-- open_diff request resolves), and report how many were closed.

local M = {}

---@param _ table
---@param respond fun(result: table)
function M.handle(_, respond)
  vim.schedule(function()
    local count = require("pi-panel.diff").close_all()
    respond({ closed = count })
  end)
end

return M
