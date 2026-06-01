-- Plugin entry point: setup(), panel lifecycle (open/toggle/focus/stop),
-- and status. Wires the WebSocket server (Phase 1) to the terminal panel.

local config = require("pi-panel.config")
local server = require("pi-panel.server")
local terminal = require("pi-panel.terminal")

local M = {}

-- True once the panel has been opened in this session (so toggle/focus know
-- whether there is a provider to delegate to).
local started = false

--- Open the pi panel, starting the WebSocket server first if needed.
function M.open()
  local cfg = config.get()
  local info = server.start() -- idempotent; returns { port, token }
  terminal.open(cfg, info, function()
    -- pi exited. The provider handles auto_close; nothing else to do here yet
    -- (Phase 5 will update the statusline).
    started = false
  end)
  started = true

  -- Warn if the agent never connects to the side channel within connection_timeout.
  local timeout = cfg.connection_timeout
  if type(timeout) == "number" and timeout > 0 then
    vim.defer_fn(function()
      if server.is_running() and not server.has_client() then
        vim.notify(
          ("pi-panel: no connection from %s after %dms (try :PiReconnect)"):format(cfg.display or "pi", timeout),
          vim.log.levels.WARN
        )
      end
    end, timeout)
  end
end

--- Toggle panel visibility (opening + launching pi on first use).
function M.toggle()
  if started then
    terminal.toggle()
  else
    M.open()
  end
end

--- Focus the panel, opening it on first use.
function M.focus()
  if started then
    terminal.focus()
  else
    M.open()
  end
end

--- Close the panel and stop the server (removing the lock file).
function M.stop()
  terminal.close()
  server.stop()
  started = false
end

--- Force a clean reconnection: tear everything down and relaunch with a fresh
--- server port/token and a new pi process. Recovers from a wedged connection
--- without restarting Neovim.
function M.reconnect()
  M.stop()
  M.open()
end

--- Accept the active diff (write the proposal, unblock pi).
function M.accept()
  require("pi-panel.diff").accept_current()
end

--- Reject the active diff (discard the proposal, unblock pi).
function M.reject()
  require("pi-panel.diff").reject_current()
end

--- Send the current visual selection into pi's terminal as a code reference.
function M.send_selection()
  local sel = require("pi-panel.selection").current()
  if sel.isEmpty then
    vim.notify("pi-panel: no visual selection to send", vim.log.levels.WARN)
    return
  end
  local ref = ("@%s:%d-%d"):format(
    vim.fn.fnamemodify(sel.filePath, ":."),
    sel.selection.start.line,
    sel.selection["end"].line
  )
  local block = ("%s\n```\n%s\n```\n"):format(ref, sel.text)
  if not require("pi-panel.terminal").send_text(block) then
    vim.notify("pi-panel: pi terminal is not running", vim.log.levels.WARN)
  end
end

--- Send an @file mention into pi's terminal. With no argument, uses the path
--- under the cursor in a file tree, else the current buffer.
---@param file? string
function M.add_file(file)
  if not file or file == "" then
    file = require("pi-panel.filetree").current_path() or vim.api.nvim_buf_get_name(0)
  end
  if not file or file == "" then
    return
  end
  if not require("pi-panel.terminal").send_text("@" .. vim.fn.fnamemodify(file, ":.") .. " ") then
    vim.notify("pi-panel: pi terminal is not running", vim.log.levels.WARN)
  end
end

--- Print a one-line connection summary via vim.notify.
function M.status()
  local name = config.get().display or "pi"
  local msg
  if not server.is_running() then
    msg = "pi-panel: server off"
  elseif server.has_client() then
    msg = ("pi-panel: %s connected (port %d)"):format(name, server.port())
  else
    msg = ("pi-panel: waiting for %s (port %d)"):format(name, server.port())
  end
  vim.notify(msg, vim.log.levels.INFO)
end

--- Configure the plugin. Safe to call multiple times.
---@param opts? table
---@return table M
function M.setup(opts)
  local cfg = config.setup(opts)
  -- Point discovery lock files at the active variant's home (~/.pi/ide or ~/.omp/ide).
  require("pi-panel.lockfile").set_dir(vim.fn.expand(cfg.lockfile_dir))
  require("pi-panel.commands").register()

  local group = vim.api.nvim_create_augroup("PiPanel", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    desc = "pi-panel: stop server and remove lock file on exit",
    callback = function()
      server.stop()
    end,
  })

  if cfg.track_selection then
    require("pi-panel.selection").setup(cfg)
  end

  if cfg.whichkey and cfg.whichkey.enabled then
    pcall(require("pi-panel.whichkey").register, cfg.whichkey)
  end

  if cfg.auto_start then
    -- Defer so setup() returns quickly and the UI is ready before pi launches.
    vim.schedule(M.open)
  end

  return M
end

return M
