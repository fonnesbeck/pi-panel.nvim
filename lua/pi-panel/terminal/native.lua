-- Native terminal provider: pi runs in a vsplit via Neovim's built-in
-- terminal. Always-available fallback when snacks.nvim is absent.

local M = {}

---@class PiPanelNativeState
---@field buf integer
---@field win integer|nil  nil while the panel is hidden (buffer/job kept alive)
---@field job integer
---@field cfg table

---@type PiPanelNativeState|nil
local state = nil

-- jobstart({term=true}) is the modern API (0.11+); termopen() is the 0.10
-- fallback. Both turn the *current* buffer into a terminal. An empty Lua table
-- encodes as a list, which jobstart's `env` rejects (E475), so pass nil instead.
local function start_term(cmd, opts)
  local env = (opts.env and next(opts.env)) and opts.env or nil
  if vim.fn.has("nvim-0.11") == 1 then
    return vim.fn.jobstart(cmd, { term = true, env = env, on_exit = opts.on_exit })
  end
  return vim.fn.termopen(cmd, { env = env, on_exit = opts.on_exit })
end

function M.is_open()
  return state ~= nil and state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

--- The terminal job channel (for chansend), or nil if not running.
function M.channel()
  return state and state.job or nil
end

local function buf_valid()
  return state ~= nil and vim.api.nvim_buf_is_valid(state.buf)
end

local function open_split(cfg)
  vim.cmd(cfg.terminal.split_side == "left" and "topleft vsplit" or "botright vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, math.floor(vim.o.columns * cfg.terminal.split_width_percentage))
  return win
end

-- Put the (hidden) terminal buffer back into a fresh split, entering insert.
local function show_existing_buffer()
  assert(state)
  state.win = open_split(state.cfg)
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.cmd("startinsert")
end

---@param opts { cmd: string[], env: table, cfg: table, on_exit?: fun(code: integer) }
function M.open(opts)
  local cfg = opts.cfg
  if M.is_open() then
    M.focus()
    return
  end
  if buf_valid() then
    show_existing_buffer()
    return
  end

  local win = open_split(cfg)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_set_current_win(win) -- start_term targets the current buffer

  local job = start_term(opts.cmd, {
    env = opts.env,
    on_exit = function(_, code)
      vim.schedule(function()
        if opts.on_exit then
          opts.on_exit(code)
        end
        if cfg.terminal.auto_close then
          M.close()
        end
      end)
    end,
  })
  state = { buf = buf, win = win, job = job, cfg = cfg }
  vim.cmd("startinsert")
end

--- Hide the panel if visible (keeping the job alive), else reopen it.
function M.toggle()
  if M.is_open() then
    ---@cast state PiPanelNativeState
    vim.api.nvim_win_close(state.win, false)
    state.win = nil
  elseif buf_valid() then
    show_existing_buffer()
  end
end

--- Bring focus to the panel, reopening the window if it was hidden.
function M.focus()
  if M.is_open() then
    ---@cast state PiPanelNativeState
    vim.api.nvim_set_current_win(state.win)
    vim.cmd("startinsert")
  elseif buf_valid() then
    show_existing_buffer()
  end
end

--- Tear down the terminal completely (job, window, buffer).
function M.close()
  if not state then
    return
  end
  pcall(vim.fn.jobstop, state.job)
  if state.win ~= nil and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  if vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  state = nil
end

return M
