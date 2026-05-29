-- close_tab: delete the buffer for a given file (closing its window/tab).

local M = {}

---@param params { filePath: string }
---@param respond fun(result: table)
function M.handle(params, respond)
  vim.schedule(function()
    local buf = params.filePath and vim.fn.bufnr(params.filePath) or vim.api.nvim_get_current_buf()
    if buf == -1 or not vim.api.nvim_buf_is_valid(buf) then
      respond({ closed = false, found = false })
      return
    end
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    respond({ closed = true })
  end)
end

return M
