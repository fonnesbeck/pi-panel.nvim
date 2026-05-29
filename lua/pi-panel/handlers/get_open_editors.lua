-- get_open_editors: list the named, listed buffers (the user's "open editors").

local M = {}

---@param _ table
---@param respond fun(result: table)
function M.handle(_, respond)
  vim.schedule(function()
    local current = vim.api.nvim_get_current_buf()
    local editors = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(buf)
      if vim.bo[buf].buflisted and name ~= "" then
        editors[#editors + 1] = {
          filePath = name,
          name = vim.fn.fnamemodify(name, ":t"),
          active = buf == current,
          dirty = vim.bo[buf].modified,
        }
      end
    end
    respond({ editors = editors })
  end)
end

return M
