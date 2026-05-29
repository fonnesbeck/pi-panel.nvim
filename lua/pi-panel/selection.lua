-- Selection tracking: reads the active buffer's visual selection, caches the
-- latest, and broadcasts debounced `selection_changed` notifications to the
-- connected pi extension. The shared reader M.current() is also used by the
-- get_selection / get_latest_selection handlers.

local M = {}

local latest = { isEmpty = true, text = "" }
local last_key = nil
local timer = nil

--- Read the current charwise visual selection of the active buffer.
---@return table selection { isEmpty, text, filePath, selection? }
function M.current()
  local buf = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)
  local s = vim.fn.getpos("'<") -- { bufnum, lnum, col, off }
  local e = vim.fn.getpos("'>")
  local sl, sc, el, ec = s[2], s[3], e[2], e[3]

  if sl == 0 or el == 0 or (sl == el and sc == ec) then
    return { isEmpty = true, text = "", filePath = file }
  end

  -- '> col is MAXCOL for end-of-line/linewise; clamp to the line's byte length
  -- (also the exclusive end column for nvim_buf_get_text).
  local last_line = vim.api.nvim_buf_get_lines(buf, el - 1, el, false)[1] or ""
  local end_excl = math.min(ec, #last_line)
  local ok, lines = pcall(vim.api.nvim_buf_get_text, buf, sl - 1, sc - 1, el - 1, end_excl, {})

  return {
    isEmpty = false,
    text = ok and table.concat(lines, "\n") or "",
    filePath = file,
    selection = {
      start = { line = sl, character = sc },
      ["end"] = { line = el, character = ec },
    },
  }
end

--- The most recently captured non-empty selection (or an empty placeholder).
function M.latest()
  return latest
end

local function key(sel)
  local s, e = sel.selection.start, sel.selection["end"]
  return table.concat({ sel.filePath, s.line, s.character, e.line, e.character }, ":")
end

--- Capture the current selection: update the cache and broadcast
--- `selection_changed` if it changed. Returns the selection, or nil when empty
--- or unchanged (deduped).
function M.capture()
  local sel = M.current()
  if sel.isEmpty then
    return nil
  end
  latest = sel
  local k = key(sel)
  if k == last_key then
    return nil
  end
  last_key = k
  require("pi-panel.server").broadcast("selection_changed", sel)
  return sel
end

--- Start debounced tracking. Idempotent. Skips terminal buffers.
---@param cfg table the active config
function M.setup(cfg)
  if timer then
    return
  end
  local delay = cfg.visual_demotion_delay_ms or 50
  timer = vim.uv.new_timer()
  local group = vim.api.nvim_create_augroup("PiPanelSelection", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "ModeChanged" }, {
    group = group,
    callback = function()
      if vim.bo.buftype == "terminal" then
        return
      end
      timer:stop()
      timer:start(delay, 0, function()
        vim.schedule(M.capture)
      end)
    end,
  })
end

return M
