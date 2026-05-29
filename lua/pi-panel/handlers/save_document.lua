-- save_document: write a file's buffer to disk.

local M = {}

---@param params { filePath: string }
---@param respond fun(result: table)
function M.handle(params, respond)
  vim.schedule(function()
    local buf = params.filePath and vim.fn.bufnr(params.filePath) or vim.api.nvim_get_current_buf()
    if buf == -1 or not vim.api.nvim_buf_is_valid(buf) then
      respond({ error = { code = -32602, message = "No buffer for " .. tostring(params.filePath) } })
      return
    end
    local ok, err = pcall(vim.api.nvim_buf_call, buf, function()
      vim.cmd("silent keepalt write")
    end)
    if not ok then
      respond({ error = { code = -32000, message = "Save failed: " .. tostring(err) } })
      return
    end
    respond({ filePath = vim.api.nvim_buf_get_name(buf), saved = true })
  end)
end

return M
