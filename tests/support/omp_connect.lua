-- Headless driver for the omp (oh-my-pi) integration check.
--
-- Hosts the pi-panel WebSocket server in this Neovim, launches the real `omp`
-- binary with the committed pi-nvim-bridge bundle (`omp -e <bundle>`) under a
-- PTY, and asserts that the extension connects back to the server.
--
-- Why a PTY: omp's one-shot/print mode exits before the async WebSocket connect
-- completes (same gotcha as pi). Running interactively under `script` keeps omp
-- alive long enough for session_start → connect; `timeout` then tears it down.
--
-- Run via tests/support/omp_integration.sh. Exits 0 on connect, 1 otherwise.

local root = vim.fn.getcwd()
package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  package.path,
}, ";")

local server = require("pi-panel.server")
local utils = require("pi-panel.utils")

local AGENT = os.getenv("PI_PANEL_OMP_CMD") or "omp"
local WAIT_MS = tonumber(os.getenv("PI_PANEL_OMP_WAIT_MS") or "") or 20000

local function die(msg, code)
  io.stderr:write("[omp-connect] " .. msg .. "\n")
  vim.cmd("cquit " .. tostring(code or 1))
end

if vim.fn.executable(AGENT) ~= 1 then
  die(AGENT .. " not found on PATH", 2)
end

local bundle = utils.extension_path()
if vim.fn.filereadable(bundle) ~= 1 then
  die("bundle missing (run `make build`): " .. bundle, 2)
end

local info = server.start({ write_lock = false })
io.stdout:write(("[omp-connect] server on 127.0.0.1:%d, launching %s\n"):format(info.port, AGENT))

-- Inherit the current environment, then add the discovery vars the bundle reads.
local env = vim.fn.environ()
env.PI_IDE_PORT = tostring(info.port)
env.PI_IDE_AUTH = info.token

-- Interactive omp under a PTY (script -qec ... /dev/null), bounded by `timeout`.
local secs = math.floor(WAIT_MS / 1000) + 5
local inner = ("timeout %d %s -e %s"):format(secs, AGENT, vim.fn.shellescape(bundle))
local cmd = { "script", "-qec", inner, "/dev/null" }

local done = false
vim.system(cmd, { text = true, env = env }, function()
  done = true
end)

local connected = vim.wait(WAIT_MS, function()
  return server.has_client()
end, 100)

server.stop()

if connected then
  io.stdout:write("[omp-connect] CLIENT_CONNECTED=true\n")
  vim.cmd("qall!")
else
  die(
    "CLIENT_CONNECTED=false — omp did not connect within " .. WAIT_MS .. "ms (omp_finished=" .. tostring(done) .. ")",
    1
  )
end
