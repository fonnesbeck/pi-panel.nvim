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

--- Print a one-line connection summary via vim.notify.
function M.status()
  local msg
  if not server.is_running() then
    msg = "pi-panel: server off"
  elseif server.has_client() then
    msg = ("pi-panel: connected (port %d)"):format(server.port())
  else
    msg = ("pi-panel: waiting for pi (port %d)"):format(server.port())
  end
  vim.notify(msg, vim.log.levels.INFO)
end

--- Configure the plugin. Safe to call multiple times.
---@param opts? table
---@return table M
function M.setup(opts)
  local cfg = config.setup(opts)
  require("pi-panel.commands").register()

  local group = vim.api.nvim_create_augroup("PiPanel", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    desc = "pi-panel: stop server and remove lock file on exit",
    callback = function()
      server.stop()
    end,
  })

  if cfg.auto_start then
    -- Defer so setup() returns quickly and the UI is ready before pi launches.
    vim.schedule(M.open)
  end

  return M
end

return M
