-- get_selection: return the current charwise visual selection of the active
-- buffer (read from the '< / '> marks). Full debounced selection *tracking*
-- with notifications is Phase 5; this is the on-demand read.

local M = {}

---@param _ table
---@param respond fun(result: table)
function M.handle(_, respond)
  vim.schedule(function()
    local buf = vim.api.nvim_get_current_buf()
    local file = vim.api.nvim_buf_get_name(buf)
    local s = vim.fn.getpos("'<") -- { bufnum, lnum, col, off }
    local e = vim.fn.getpos("'>")
    local sl, sc, el, ec = s[2], s[3], e[2], e[3]

    if sl == 0 or el == 0 or (sl == el and sc == ec) then
      respond({ isEmpty = true, text = "", filePath = file })
      return
    end

    -- '> col is MAXCOL for end-of-line / linewise selections; clamp to the
    -- line's byte length (also the exclusive end for nvim_buf_get_text).
    local last_line = vim.api.nvim_buf_get_lines(buf, el - 1, el, false)[1] or ""
    local end_excl = math.min(ec, #last_line)
    local ok, lines = pcall(vim.api.nvim_buf_get_text, buf, sl - 1, sc - 1, el - 1, end_excl, {})

    respond({
      isEmpty = false,
      text = ok and table.concat(lines, "\n") or "",
      filePath = file,
      selection = {
        start = { line = sl, character = sc },
        ["end"] = { line = el, character = ec },
      },
    })
  end)
end

return M
