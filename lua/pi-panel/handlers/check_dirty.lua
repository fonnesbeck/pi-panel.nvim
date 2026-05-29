-- check_dirty: report whether a file's buffer has unsaved changes.

local M = {}

---@param params { filePath?: string }
---@param respond fun(result: table)
function M.handle(params, respond)
  vim.schedule(function()
    local buf = params.filePath and vim.fn.bufnr(params.filePath) or vim.api.nvim_get_current_buf()
    if buf == -1 or not vim.api.nvim_buf_is_valid(buf) then
      respond({ filePath = params.filePath, isDirty = false, found = false })
      return
    end
    respond({
      filePath = vim.api.nvim_buf_get_name(buf),
      isDirty = vim.bo[buf].modified,
      found = true,
    })
  end)
end

return M
