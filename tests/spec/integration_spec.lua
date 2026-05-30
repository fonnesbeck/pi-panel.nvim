local t = require("support.runner")
local server = require("pi-panel.server")

-- Run the self-contained node client against a running server. With `method`,
-- the client sends that JSON-RPC request (after initialize) and returns its
-- response; `params` is encoded to JSON.
local function run_client(port, token, method, params)
  local cmd = { "node", "tests/support/ws_client.js", tostring(port) }
  if token then
    cmd[#cmd + 1] = token
  end
  if method then
    cmd[#cmd + 1] = method
    cmd[#cmd + 1] = vim.json.encode(params or vim.empty_dict())
  end
  -- Run async and pump the loop with vim.wait: tool handlers respond from a
  -- vim.schedule callback, which a blocking :wait() would never let run.
  local result
  vim.system(cmd, { text = true }, function(res)
    result = res
  end)
  vim.wait(8000, function()
    return result ~= nil
  end)
  return result or { code = -1, stdout = '{"ok":false,"error":"client did not finish"}', stderr = "" }
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

  t.it("dispatches a get_workspace_folders tool call end-to-end", function()
    local s = server.start({ auth_token = "tok", write_lock = false })
    local res = run_client(s.port, "tok", "get_workspace_folders", {})
    server.stop()
    t.eq(res.code, 0, "client failed: " .. tostring(res.stdout) .. tostring(res.stderr))
    local out = vim.json.decode(res.stdout)
    t.is_true(out.ok)
    t.truthy(vim.tbl_contains(out.result.folders, vim.fn.getcwd()), "cwd returned")
  end)

  t.it("dispatches an open_file tool call end-to-end", function()
    local tmp = vim.fn.tempname()
    vim.fn.writefile({ "x", "y", "z" }, tmp)
    local s = server.start({ auth_token = "tok", write_lock = false })
    local res = run_client(s.port, "tok", "open_file", { filePath = tmp, startLine = 2 })
    server.stop()
    t.eq(res.code, 0, "client failed: " .. tostring(res.stdout) .. tostring(res.stderr))
    local out = vim.json.decode(res.stdout)
    t.is_true(out.ok)
    t.truthy(out.result.message:find("Opened", 1, true))
    os.remove(tmp)
  end)

  t.it("returns a JSON-RPC error for an unknown method", function()
    local s = server.start({ auth_token = "tok", write_lock = false })
    local res = run_client(s.port, "tok", "no_such_method", {})
    server.stop()
    local out = vim.json.decode(res.stdout)
    t.eq(out.ok, false, "unknown method should error")
  end)
end)
