-- This spec monkeypatches server/terminal module functions to drive M.open()
-- in isolation; the reassignments are intentional.
---@diagnostic disable: duplicate-set-field
local t = require("support.runner")
local pi = require("pi-panel")
local config = require("pi-panel.config")
local server = require("pi-panel.server")
local terminal = require("pi-panel.terminal")

-- Drive M.open() with stubbed server/terminal so we can exercise the
-- connection-timeout warning without a real agent or socket. The warning was
-- added to name the active variant on the most common failure path (silent
-- no-connect); this locks that behaviour against future refactors.
local function open_with_timeout_stubs(opts)
  local orig = {
    start = server.start,
    is_running = server.is_running,
    has_client = server.has_client,
    t_open = terminal.open,
    defer = vim.defer_fn,
    notify = vim.notify,
  }
  server.start = function()
    return { port = 1, token = "t" }
  end
  server.is_running = function()
    return true
  end
  server.has_client = function()
    return false
  end -- never connects -> warning path
  terminal.open = function() end
  vim.defer_fn = function(fn)
    fn()
  end -- fire the deferred warning synchronously
  local captured
  vim.notify = function(msg)
    captured = msg
  end

  config.setup(vim.tbl_extend("force", { auto_start = false, connection_timeout = 10 }, opts or {}))
  local ok, err = pcall(pi.open)

  server.start, server.is_running, server.has_client = orig.start, orig.is_running, orig.has_client
  terminal.open = orig.t_open
  vim.defer_fn, vim.notify = orig.defer, orig.notify
  pi.stop() -- reset module-local started flag; idempotent
  config.setup({}) -- restore default config for later specs

  assert(ok, err)
  return captured
end

t.describe("pi-panel.open connection-timeout warning", function()
  t.it("names the active agent (omp) when no connection arrives", function()
    local msg = open_with_timeout_stubs({ variant = "omp" })
    t.truthy(msg and msg:find("oh-my-pi", 1, true), "warning should name the variant: " .. tostring(msg))
    t.truthy(msg:find("PiReconnect", 1, true), "warning should suggest :PiReconnect")
  end)

  t.it("names pi by default", function()
    local msg = open_with_timeout_stubs({})
    t.truthy(msg and msg:find("from pi after", 1, true), "warning should name pi: " .. tostring(msg))
  end)
end)
