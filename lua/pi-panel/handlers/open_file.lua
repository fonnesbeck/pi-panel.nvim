-- open_file: edit a file in Neovim, optionally positioning the cursor and
-- selecting a line range. Non-blocking — responds once the edit is done.
--
-- Handlers run from the WebSocket (libuv) callback context, where direct vim
-- API use is unsafe, so the work is wrapped in vim.schedule and the result is
-- delivered via the async `respond` callback.

local M = {}

---@param params { filePath: string, startLine?: integer, endLine?: integer }
---@param respond fun(result: table)
function M.handle(params, respond)
  vim.schedule(function()
    local abs = vim.fn.fnamemodify(params.filePath, ":p")
    vim.cmd("edit " .. vim.fn.fnameescape(abs))

    if params.startLine then
      local sl = math.max(1, params.startLine)
      if params.endLine and params.endLine >= sl then
        pcall(vim.cmd, ("normal! %dGV%dG"):format(sl, params.endLine))
      else
        pcall(vim.api.nvim_win_set_cursor, 0, { sl, 0 })
      end
    end

    respond({ filePath = abs, message = "Opened " .. abs })
  end)
end

return M
