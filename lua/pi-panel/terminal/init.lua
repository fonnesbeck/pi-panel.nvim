-- Terminal provider abstraction: builds pi's launch command + discovery env,
-- selects a provider (snacks / native), and delegates open/toggle/focus/close.

local utils = require("pi-panel.utils")
local lockfile = require("pi-panel.lockfile")

local M = {}

--- Build the argv that launches pi with the pi-nvim-bridge extension.
---@param cfg table the active config
---@return string[]
function M.build_cmd(cfg)
  return { cfg.pi_cmd or "pi", "-e", utils.extension_path() }
end

--- Build the environment for the pi process: user env plus the PI_IDE_*
--- discovery vars (which always win over any user-supplied collision).
---@param cfg table the active config
---@param info { port: integer, token: string }
---@return table<string,string>
function M.build_env(cfg, info)
  local env = vim.tbl_extend("force", {}, cfg.env or {})
  env.PI_IDE_PORT = tostring(info.port)
  env.PI_IDE_AUTH = info.token
  env.PI_IDE_LOCKFILE = lockfile.path(info.port)
  return env
end

--- Resolve the concrete provider name. "auto" picks snacks when available,
--- else native. `has_snacks` is injectable for testing; defaults to a probe.
---@param cfg table
---@param has_snacks? boolean
---@return "snacks"|"native"|"external"
function M.select_provider(cfg, has_snacks)
  local provider = cfg.terminal.provider
  if provider ~= "auto" then
    return provider
  end
  if has_snacks == nil then
    has_snacks = pcall(require, "snacks")
  end
  return has_snacks and "snacks" or "native"
end

-- ---- stateful orchestration ----------------------------------------------

-- Active provider module (lazily resolved on first open).
local active = nil

local function provider_module(name)
  return require("pi-panel.terminal." .. name)
end

--- Open (or focus, if already open) pi's panel. Starts nothing on its own;
--- `info` carries the running server's port/token for discovery.
---@param cfg table
---@param info { port: integer, token: string }
---@param on_exit? fun(code: integer)
function M.open(cfg, info, on_exit)
  local name = M.select_provider(cfg)
  active = provider_module(name)
  active.open({
    cmd = M.build_cmd(cfg),
    env = M.build_env(cfg, info),
    cfg = cfg,
    on_exit = on_exit,
  })
end

function M.is_open()
  return active ~= nil and active.is_open()
end

--- Toggle visibility. Requires the panel to have been opened at least once
--- (callers route the first-open through M.open with server info).
function M.toggle()
  if active then
    active.toggle()
  end
end

function M.focus()
  if active then
    active.focus()
  end
end

function M.close()
  if active then
    active.close()
    active = nil
  end
end

--- Write text into the running pi terminal's stdin (e.g. a selection from
--- :PiSend). Returns true if it was sent.
---@param text string
---@return boolean
function M.send_text(text)
  local chan = active and active.channel and active.channel()
  if not chan then
    return false
  end
  pcall(vim.fn.chansend, chan, text)
  return true
end

return M
