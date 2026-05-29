-- get_diagnostics: LSP diagnostics for one file (params.filePath) or all
-- buffers. Severities are mapped to names; line/col are 1-indexed for display.

local M = {}

local SEVERITY = {
  [vim.diagnostic.severity.ERROR] = "ERROR",
  [vim.diagnostic.severity.WARN] = "WARN",
  [vim.diagnostic.severity.INFO] = "INFO",
  [vim.diagnostic.severity.HINT] = "HINT",
}

---@param params { filePath?: string }
---@param respond fun(result: table)
function M.handle(params, respond)
  vim.schedule(function()
    local bufnr = nil
    if params.filePath then
      local b = vim.fn.bufnr(params.filePath)
      bufnr = b ~= -1 and b or -1 -- -1 yields no diagnostics rather than all
    end

    local out = {}
    for _, d in ipairs(vim.diagnostic.get(bufnr)) do
      out[#out + 1] = {
        filePath = vim.api.nvim_buf_get_name(d.bufnr),
        severity = SEVERITY[d.severity] or tostring(d.severity),
        message = d.message,
        line = d.lnum + 1,
        col = d.col + 1,
        source = d.source,
      }
    end
    respond({ diagnostics = out })
  end)
end

return M
