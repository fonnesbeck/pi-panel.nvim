local t = require("support.runner")
local server = require("pi-panel.server")

-- Run the self-contained node client against a running server.
local function run_client(port, token)
  local cmd = { "node", "tests/support/ws_client.js", tostring(port) }
  if token then
    cmd[#cmd + 1] = token
  end
  return vim.system(cmd, { text = true }):wait(8000)
end

t.describe("end-to-end WebSocket server", function()
  if vim.fn.executable("node") ~= 1 then
    t.it("SKIPPED (node not found)", function() end)
    return
  end

  t.it("accepts an authorized client and negotiates initialize", function()
    local s = server.start({ auth_token = "integration-token", write_lock = false })
    local res = run_client(s.port, "integration-token")
    server.stop()
    t.eq(res.code, 0, "client failed: stdout=" .. tostring(res.stdout) .. " stderr=" .. tostring(res.stderr))
    local out = vim.json.decode(res.stdout)
    t.is_true(out.ok)
    t.eq(out.result.protocolVersion, 1)
  end)

  t.it("rejects a client that omits the auth token", function()
    local s = server.start({ auth_token = "integration-token", write_lock = false })
    local res = run_client(s.port, nil)
    server.stop()
    t.ne(res.code, 0, "server should reject the unauthorized client")
    local out = vim.json.decode(res.stdout)
    t.eq(out.ok, false)
  end)

  t.it("rejects a client presenting the wrong token", function()
    local s = server.start({ auth_token = "integration-token", write_lock = false })
    local res = run_client(s.port, "wrong-token")
    server.stop()
    t.ne(res.code, 0, "server should reject the wrong token")
  end)
end)
