-- Headless driver for the omp (oh-my-pi) integration check.
--
-- Hosts the pi-panel WebSocket server in this Neovim, launches the real `omp`
-- binary with the committed pi-nvim-bridge bundle (`omp -e <bundle>`) under a
-- PTY, and asserts that the extension performs a COMPLETED WebSocket handshake.
--
-- We assert on the server receiving the bridge's first real frame — the
-- `initialize` JSON-RPC request (bridge.ts sends it on `open`) — NOT on
-- has_client(). has_client() flips true on TCP accept (server/tcp.lua), before
-- the handshake, so under a broken client (e.g. `ws` under Bun, which rejects the
-- 101) it briefly reports connected then drops in a reconnect loop. Requiring an
-- `initialize` frame proves the upgrade succeeded client-side.
--
-- Why a PTY: omp's one-shot/print mode exits before the async WebSocket connect
-- completes (same gotcha as pi). Running interactively under `script` keeps omp
-- alive long enough for session_start → connect; `timeout` then tears it down.
--
-- Run via tests/support/omp_integration.sh. Exits 0 on a real handshake, 1 otherwise.

local root = vim.fn.getcwd()
package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  package.path,
}, ";")

local server = require("pi-panel.server")
local handlers = require("pi-panel.handlers")
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

-- Wrap the real registry so we learn when the bridge's `initialize` frame is
-- dispatched (a frame is only dispatched after a completed WS handshake). The
-- lookup delegates to handlers.registry, so the connection behaves normally.
local got_initialize = false
local registry = setmetatable({}, {
  __index = function(_, method)
    if method == "initialize" then
      got_initialize = true
    end
    return handlers.registry[method]
  end,
})

local info = server.start({ write_lock = false, registry = registry })
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

local handshook = vim.wait(WAIT_MS, function()
  return got_initialize
end, 100)

local tcp_seen = server.has_client() -- capture before stop() clears server state
server.stop()

if handshook then
  io.stdout:write("[omp-connect] HANDSHAKE_OK=true (initialize received)\n")
  vim.cmd("qall!")
else
  die(
    ("HANDSHAKE_OK=false — no initialize frame within %dms (tcp_seen=%s, omp_finished=%s). "):format(
      WAIT_MS,
      tostring(tcp_seen),
      tostring(done)
    ) .. "The WebSocket handshake never completed client-side.",
    1
  )
end
