-- snacks.nvim terminal provider (default when snacks is installed). Thin
-- wrapper over Snacks.terminal; the heavy lifting (window mgmt, insert mode)
-- lives in snacks. Not unit-tested — it delegates to external terminal I/O.

local M = {}

-- The snacks.win terminal object returned by Snacks.terminal.open.
local term = nil

local function build_opts(opts)
  local cfg = opts.cfg
  return {
    env = (opts.env and next(opts.env)) and opts.env or nil,
    cwd = vim.fn.getcwd(),
    interactive = true,
    auto_close = cfg.terminal.auto_close,
    win = vim.tbl_deep_extend("force", {
      position = cfg.terminal.split_side == "left" and "left" or "right",
      width = cfg.terminal.split_width_percentage,
    }, cfg.terminal.snacks_win_opts or {}),
  }
end

function M.is_open()
  return term ~= nil and term:valid() and term.win ~= nil and vim.api.nvim_win_is_valid(term.win)
end

--- The terminal job channel (for chansend), or nil if not running.
function M.channel()
  if term and term.buf and vim.api.nvim_buf_is_valid(term.buf) then
    return vim.b[term.buf].terminal_job_id
  end
  return nil
end

---@param opts { cmd: string[], env: table, cfg: table, on_exit?: fun(code: integer) }
function M.open(opts)
  local Snacks = require("snacks")
  if M.is_open() then
    M.focus()
    return
  end
  term = Snacks.terminal.open(opts.cmd, build_opts(opts))

  if opts.on_exit and term and term.buf then
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = term.buf,
      once = true,
      callback = function()
        local code = (vim.v.event or {}).status or 0
        vim.schedule(function()
          opts.on_exit(code)
        end)
      end,
    })
  end
end

function M.toggle()
  if term then
    term:toggle()
  end
end

function M.focus()
  if term then
    term:show()
    if term.win and vim.api.nvim_win_is_valid(term.win) then
      vim.api.nvim_set_current_win(term.win)
    end
    vim.cmd("startinsert")
  end
end

function M.close()
  if term then
    term:close()
    term = nil
  end
end

return M
