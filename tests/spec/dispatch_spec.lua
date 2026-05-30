local t = require("support.runner")
local dispatch = require("pi-panel.server.dispatch")

-- Capture responses that dispatch wants to send over the wire.
local function capture()
  local sent = {}
  return sent, function(str)
    sent[#sent + 1] = vim.json.decode(str)
  end
end

local function req(tbl)
  return vim.json.encode(tbl)
end

t.describe("dispatch.handle", function()
  t.it("routes a request to a handler and returns a JSON-RPC result", function()
    local registry = {
      echo = function(params)
        return { content = { { type = "text", text = params.msg } } }
      end,
    }
    local sent, send = capture()
    dispatch.handle(req({ jsonrpc = "2.0", id = "1", method = "echo", params = { msg = "hi" } }), registry, send)
    t.eq(#sent, 1)
    t.eq(sent[1].jsonrpc, "2.0")
    t.eq(sent[1].id, "1")
    t.eq(sent[1].result.content[1].text, "hi")
    t.is_nil(sent[1].error)
  end)

  t.it("returns -32601 for an unknown method", function()
    local sent, send = capture()
    dispatch.handle(req({ jsonrpc = "2.0", id = "2", method = "nope", params = {} }), {}, send)
    t.eq(sent[1].error.code, -32601)
    t.eq(sent[1].id, "2")
  end)

  t.it("does not respond to a notification (no id)", function()
    local called = false
    local registry = {
      ping = function()
        called = true
      end,
    }
    local sent, send = capture()
    dispatch.handle(req({ jsonrpc = "2.0", method = "ping", params = {} }), registry, send)
    t.is_true(called, "handler ran")
    t.eq(#sent, 0, "no response for notification")
  end)

  t.it("returns -32700 for malformed JSON", function()
    local sent, send = capture()
    dispatch.handle("{not json", {}, send)
    t.eq(sent[1].error.code, -32700)
  end)

  t.it("maps a handler-returned error to a JSON-RPC error", function()
    local registry = {
      boom = function()
        return { error = { code = -32000, message = "kaboom" } }
      end,
    }
    local sent, send = capture()
    dispatch.handle(req({ jsonrpc = "2.0", id = "5", method = "boom", params = {} }), registry, send)
    t.eq(sent[1].error.code, -32000)
    t.eq(sent[1].error.message, "kaboom")
    t.is_nil(sent[1].result)
  end)

  t.it("maps a raised error to internal error -32603", function()
    local registry = {
      explode = function()
        error("unexpected")
      end,
    }
    local sent, send = capture()
    dispatch.handle(req({ jsonrpc = "2.0", id = "6", method = "explode", params = {} }), registry, send)
    t.eq(sent[1].error.code, -32603)
  end)

  t.it("supports async handlers that respond via callback", function()
    local deferred
    local registry = {
      slow = function(_params, respond)
        deferred = respond -- respond later, return nil now
        return nil
      end,
    }
    local sent, send = capture()
    dispatch.handle(req({ jsonrpc = "2.0", id = "7", method = "slow", params = {} }), registry, send)
    t.eq(#sent, 0, "no immediate response")
    deferred({ content = { { type = "text", text = "done" } } })
    t.eq(sent[1].id, "7")
    t.eq(sent[1].result.content[1].text, "done")
  end)
end)

t.describe("initialize capability negotiation", function()
  local handlers = require("pi-panel.handlers")
  t.it("responds with protocolVersion 1 and a supportedTools list", function()
    local sent, send = capture()
    dispatch.handle(
      req({
        jsonrpc = "2.0",
        id = "init-1",
        method = "initialize",
        params = { protocolVersion = 1, supportedTools = {} },
      }),
      handlers.registry,
      send
    )
    t.eq(sent[1].result.protocolVersion, 1)
    t.truthy(type(sent[1].result.supportedTools) == "table", "supportedTools is a list")
  end)
end)
