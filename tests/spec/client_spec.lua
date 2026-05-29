local t = require("support.runner")
local Client = require("pi-panel.server.client")
local frame = require("pi-panel.server.frame")
local ws = require("support.ws")

-- A fake transport capturing everything the client would write to the socket.
local function fake()
  local sink = { written = "", closed = false }
  function sink.write(data) sink.written = sink.written .. data end
  function sink.close() sink.closed = true end
  return sink
end

local function new_client(sink, registry)
  return Client.new({
    write = sink.write,
    close = sink.close,
    expected_token = "secret",
    registry = registry or {},
  })
end

-- Decode every server frame the client wrote.
local function written_frames(sink)
  local frames, buf = {}, sink.written
  while true do
    local f, rest = frame.decode(buf)
    if not f then break end
    frames[#frames + 1] = f
    buf = rest
  end
  return frames
end

t.describe("Client handshake", function()
  t.it("completes the handshake and writes a 101 across a split feed", function()
    local sink = fake()
    local c = new_client(sink)
    local req = ws.upgrade_request("secret")
    c:feed(req:sub(1, 20)) -- partial: no response yet
    t.eq(sink.written, "")
    c:feed(req:sub(21))    -- remainder completes the header block
    t.truthy(sink.written:find("HTTP/1.1 101", 1, true), "101 sent")
    t.eq(c.state, "open")
  end)

  t.it("rejects a bad token and closes", function()
    local sink = fake()
    local c = new_client(sink)
    c:feed(ws.upgrade_request("wrong"))
    t.truthy(sink.written:find("401", 1, true), "401 sent")
    t.is_true(sink.closed)
    t.eq(c.state, "closed")
  end)
end)

t.describe("Client message handling", function()
  local function open_client(registry)
    local sink = fake()
    local c = new_client(sink, registry)
    c:feed(ws.upgrade_request("secret"))
    sink.written = "" -- discard the 101 so written_frames sees only post-handshake frames
    return c, sink
  end

  t.it("dispatches a JSON-RPC request frame and writes a response frame", function()
    local c, sink = open_client({
      echo = function(params) return { content = { { type = "text", text = params.msg } } } end,
    })
    local request = vim.json.encode({ jsonrpc = "2.0", id = "1", method = "echo", params = { msg = "yo" } })
    c:feed(ws.mask_frame(frame.TEXT, request))

    local frames = written_frames(sink)
    t.eq(#frames, 1)
    t.eq(frames[1].opcode, frame.TEXT)
    local resp = vim.json.decode(frames[1].payload)
    t.eq(resp.id, "1")
    t.eq(resp.result.content[1].text, "yo")
  end)

  t.it("replies to a ping with a pong carrying the same payload", function()
    local c, sink = open_client()
    c:feed(ws.mask_frame(frame.PING, "hb"))
    local frames = written_frames(sink)
    t.eq(frames[1].opcode, frame.PONG)
    t.eq(frames[1].payload, "hb")
  end)

  t.it("closes on a client close frame", function()
    local c, sink = open_client()
    c:feed(ws.mask_frame(frame.CLOSE, ""))
    t.is_true(sink.closed)
    t.eq(c.state, "closed")
  end)

  t.it("reassembles a fragmented text message before dispatching", function()
    local seen
    local c = (function()
      local sink = fake()
      local cl = new_client(sink, { collect = function(params) seen = params.parts end })
      cl:feed(ws.upgrade_request("secret"))
      return cl
    end)()
    local msg = vim.json.encode({ jsonrpc = "2.0", method = "collect", params = { parts = "abcdef" } })
    local half = math.floor(#msg / 2)
    c:feed(ws.mask_frame(frame.TEXT, msg:sub(1, half), false))   -- fin=false
    c:feed(ws.mask_frame(frame.CONTINUATION, msg:sub(half + 1), true)) -- final fragment
    t.eq(seen, "abcdef")
  end)
end)
