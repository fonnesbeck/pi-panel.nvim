-- WebSocket server lifecycle: start/stop, lock-file management, auth token.

local tcp = require("pi-panel.server.tcp")
local utils = require("pi-panel.server.utils")
local handlers = require("pi-panel.handlers")
local lockfile = require("pi-panel.lockfile")

local M = {}

local state = nil -- { server, port, token } when running

--- Start the server (idempotent). Returns { port, token }.
---@param opts? { port?: integer, auth_token?: string, registry?: table, write_lock?: boolean }
function M.start(opts)
  opts = opts or {}
  if state then
    return { port = state.port, token = state.token }
  end

  -- Clean up locks left behind by crashed instances before claiming a port.
  lockfile.sweep_stale()

  local token = opts.auth_token or utils.uuid_v4()
  local server = tcp.listen({
    host = "127.0.0.1",
    port = opts.port or 0,
    expected_token = token,
    registry = opts.registry or handlers.registry,
  })
  state = { server = server, port = server.port, token = token }

  if opts.write_lock ~= false then
    local cwd = vim.fn.getcwd()
    lockfile.write({
      port = server.port,
      authToken = token,
      workspaceFolders = { cwd },
      displayName = vim.fn.fnamemodify(cwd, ":t"),
    })
  end

  return { port = state.port, token = state.token }
end

function M.stop()
  if not state then
    return
  end
  for client in pairs(state.server.clients) do
    pcall(function()
      client.close()
    end)
  end
  if not state.server.handle:is_closing() then
    state.server.handle:close()
  end
  pcall(lockfile.remove, state.port)
  state = nil
end

function M.is_running()
  return state ~= nil
end

function M.has_client()
  return state ~= nil and next(state.server.clients) ~= nil
end

function M.port()
  return state and state.port or nil
end

function M.token()
  return state and state.token or nil
end

return M
