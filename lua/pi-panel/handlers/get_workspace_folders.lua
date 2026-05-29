-- get_workspace_folders: report the editor's workspace roots. Currently the
-- single Neovim cwd; multi-root support can extend the list later.

local M = {}

---@param _ table
---@param respond fun(result: table)
function M.handle(_, respond)
  vim.schedule(function()
    respond({ folders = { vim.fn.getcwd() } })
  end)
end

return M
