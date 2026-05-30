-- Native Neovim diff view for reviewing pi's proposed file changes.
--
-- diff.open(params, on_result) shows the original file (left) next to the
-- proposal (right) in diff mode, and returns a `view`. Exactly one of
-- accept/reject/close eventually resolves it:
--   accept -> writes the (possibly edited) right buffer to disk, on_result("FILE_SAVED")
--   reject -> on_result("DIFF_REJECTED"), nothing written
--   close  -> tears down silently (used by cancel/timeout, which respond separately)
-- The open_diff handler blocks on on_result; see handlers/open_diff.lua.

local config = require("pi-panel.config")

local M = {}

-- Active diffs keyed by the right (proposed) buffer id, plus the most-recent
-- view for the *_current commands when no buffer match is in focus.
local active = {}
local last = nil

-- Split a string into buffer lines, dropping the trailing "" that a final
-- newline produces so writefile() round-trips the content faithfully.
local function to_lines(s)
  local lines = vim.split(s or "", "\n", { plain = true })
  if #lines > 1 and lines[#lines] == "" then
    table.remove(lines)
  end
  return lines
end

local function original_lines(params)
  if params.oldContents ~= nil then
    return to_lines(params.oldContents)
  end
  if vim.fn.filereadable(params.filePath) == 1 then
    return vim.fn.readfile(params.filePath)
  end
  return {}
end

---@param params { filePath: string, newContents: string, oldContents?: string }
---@param on_result fun(result: "FILE_SAVED"|"DIFF_REJECTED")
---@return table view
function M.open(params, on_result)
  local cfg = config.get().diff_opts
  local start_win = vim.api.nvim_get_current_win()
  local orig_lines = original_lines(params)
  local new_lines = to_lines(params.newContents)

  -- Carve out windows we fully own so the user's layout survives teardown:
  -- a new tab, or a far-side vertical/horizontal split in the current tab.
  if cfg.open_in_new_tab then
    vim.cmd("tabnew")
  else
    vim.cmd(cfg.layout == "horizontal" and "botright split" or "botright vsplit")
  end

  local orig_win = vim.api.nvim_get_current_win()
  local orig_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(orig_buf, 0, -1, false, orig_lines)
  vim.bo[orig_buf].buftype = "nofile"
  vim.bo[orig_buf].modifiable = false
  pcall(vim.api.nvim_buf_set_name, orig_buf, params.filePath .. " [original]")
  vim.api.nvim_win_set_buf(orig_win, orig_buf)
  vim.cmd("diffthis")

  vim.cmd(cfg.layout == "horizontal" and "split" or "vsplit")
  local new_win = vim.api.nvim_get_current_win()
  local new_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, new_lines)
  vim.bo[new_buf].buftype = "acwrite" -- lets `:w` fire BufWriteCmd -> accept
  pcall(vim.api.nvim_buf_set_name, new_buf, params.filePath .. " [proposed]")
  vim.api.nvim_win_set_buf(new_win, new_buf)
  vim.cmd("diffthis")

  local view = {
    filePath = params.filePath,
    orig_buf = orig_buf,
    new_buf = new_buf,
    orig_win = orig_win,
    new_win = new_win,
    on_result = on_result,
    done = false,
  }
  active[new_buf] = view
  last = view

  vim.keymap.set("n", "<leader>pa", function()
    M.accept(view)
  end, { buffer = new_buf, desc = "pi: accept diff" })
  vim.keymap.set("n", "<leader>pr", function()
    M.reject(view)
  end, { buffer = new_buf, desc = "pi: reject diff" })
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = new_buf,
    callback = function()
      M.accept(view)
    end,
  })

  -- By default the user lands in the proposed buffer to review it; with
  -- keep_terminal_focus, leave focus on the window they came from (the panel).
  if cfg.keep_terminal_focus and vim.api.nvim_win_is_valid(start_win) then
    vim.api.nvim_set_current_win(start_win)
  end

  return view
end

local function teardown(view)
  active[view.new_buf] = nil
  if last == view then
    last = nil
  end
  for _, win in ipairs({ view.new_win, view.orig_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  for _, buf in ipairs({ view.new_buf, view.orig_buf }) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

function M.accept(view)
  if not view or view.done then
    return
  end
  view.done = true
  local lines = vim.api.nvim_buf_is_valid(view.new_buf) and vim.api.nvim_buf_get_lines(view.new_buf, 0, -1, false) or {}
  vim.fn.mkdir(vim.fn.fnamemodify(view.filePath, ":h"), "p")
  vim.fn.writefile(lines, view.filePath)
  teardown(view)
  if view.on_result then
    view.on_result("FILE_SAVED")
  end
end

function M.reject(view)
  if not view or view.done then
    return
  end
  view.done = true
  teardown(view)
  if view.on_result then
    view.on_result("DIFF_REJECTED")
  end
end

-- Silent teardown for cancel/timeout (the caller sends its own JSON-RPC error).
function M.close(view)
  if not view or view.done then
    return
  end
  view.done = true
  teardown(view)
end

function M.is_active()
  return next(active) ~= nil
end

-- Reject every open diff (so pending open_diff requests resolve) and return the
-- number closed. Used by the close_all_diff_tabs tool.
function M.close_all()
  local views = {}
  for _, view in pairs(active) do
    views[#views + 1] = view
  end
  for _, view in ipairs(views) do
    M.reject(view)
  end
  return #views
end

-- Resolve the diff for the current buffer, else the most recently opened one.
local function current_view()
  return active[vim.api.nvim_get_current_buf()] or last
end

function M.accept_current()
  local view = current_view()
  if view then
    M.accept(view)
  end
end

function M.reject_current()
  local view = current_view()
  if view then
    M.reject(view)
  end
end

return M
