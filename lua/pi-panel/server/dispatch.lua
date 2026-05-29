-- JSON-RPC 2.0 dispatch over a WebSocket text channel.
--   handle(raw_json, registry, send)
-- `registry` maps method -> handler(params, respond). A handler may either
-- return a value synchronously, or return nil and call `respond(value)` later
-- (async/blocking tools). A returned/`respond`ed table with an `error` field
-- becomes a JSON-RPC error; otherwise it becomes the `result`.
-- `send` receives an encoded response string (never called for notifications).

local M = {}

local function send_error(send, id, code, message)
  send(vim.json.encode({ jsonrpc = "2.0", id = id, error = { code = code, message = message } }))
end

---@param raw string
---@param registry table<string, fun(params:table, respond:fun(result:any))>
---@param send fun(response_json: string)
function M.handle(raw, registry, send)
  local ok, msg = pcall(vim.json.decode, raw)
  if not ok or type(msg) ~= "table" then
    send_error(send, vim.NIL, -32700, "Parse error")
    return
  end

  local id = msg.id -- nil ⇒ notification (no response)
  local handler = registry[msg.method]
  if not handler then
    if id ~= nil then
      send_error(send, id, -32601, "Method not found: " .. tostring(msg.method))
    end
    return
  end

  local responded = false
  local function respond(result)
    if id == nil or responded then
      return
    end
    responded = true
    if type(result) == "table" and result.error then
      send(vim.json.encode({ jsonrpc = "2.0", id = id, error = result.error }))
    else
      send(vim.json.encode({ jsonrpc = "2.0", id = id, result = result }))
    end
  end

  local ok2, ret = pcall(handler, msg.params or {}, respond)
  if not ok2 then
    if id ~= nil then
      send_error(send, id, -32603, "Internal error: " .. tostring(ret))
    end
    return
  end
  -- Non-nil return ⇒ synchronous result. nil ⇒ handler will call respond later.
  if ret ~= nil then
    respond(ret)
  end
end

return M
