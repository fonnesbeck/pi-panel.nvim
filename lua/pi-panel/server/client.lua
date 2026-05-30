-- One WebSocket connection: drives the handshake, then buffers/decodes frames,
-- reassembles fragmented messages, answers control frames, and dispatches
-- JSON-RPC text messages. Transport is injected (write/close) so the state
-- machine is testable without a real socket.

local handshake = require("pi-panel.server.handshake")
local frame = require("pi-panel.server.frame")
local dispatch = require("pi-panel.server.dispatch")

local Client = {}
Client.__index = Client

---@param opts { write: fun(data:string), close: fun(), expected_token: string, registry: table }
function Client.new(opts)
  return setmetatable({
    buffer = "", -- unparsed bytes (handshake text, then frame bytes)
    state = "handshaking", -- handshaking | open | closed
    msg = "", -- reassembly buffer for fragmented messages
    write = opts.write,
    close = opts.close,
    expected_token = opts.expected_token,
    registry = opts.registry,
  }, Client)
end

function Client:send_text(str)
  self.write(frame.encode(frame.TEXT, str))
end

function Client:_shutdown()
  if self.state ~= "closed" then
    self.state = "closed"
    self.close()
  end
end

function Client:_try_handshake()
  local terminator = self.buffer:find("\r\n\r\n", 1, true)
  if not terminator then
    return -- header block not fully received yet
  end
  local response, accepted = handshake.handle(self.buffer, self.expected_token)
  self.write(response)
  self.buffer = self.buffer:sub(terminator + 4) -- skip the 4-byte \r\n\r\n terminator
  if accepted then
    self.state = "open"
  else
    self:_shutdown()
  end
end

function Client:_handle_frame(f)
  local op = f.opcode
  if op == frame.CLOSE then
    self.write(frame.encode(frame.CLOSE, ""))
    self:_shutdown()
  elseif op == frame.PING then
    self.write(frame.encode(frame.PONG, f.payload))
  elseif op == frame.PONG then
    -- keepalive acknowledgement; nothing to do
  else
    -- data frame: TEXT/BINARY start a message, CONTINUATION extends it
    self.msg = self.msg .. f.payload
    if f.fin then
      local message = self.msg
      self.msg = ""
      dispatch.handle(message, self.registry, function(resp)
        if self.state == "open" then
          self:send_text(resp)
        end
      end)
    end
  end
end

function Client:_drain_frames()
  while self.state == "open" do
    local f, rest = frame.decode(self.buffer)
    if not f then
      break -- incomplete frame; wait for more bytes
    end
    self.buffer = rest
    self:_handle_frame(f)
  end
end

--- Feed raw bytes received from the socket.
function Client:feed(data)
  if self.state == "closed" then
    return
  end
  self.buffer = self.buffer .. data
  if self.state == "handshaking" then
    self:_try_handshake()
  end
  if self.state == "open" then
    self:_drain_frames()
  end
end

return Client
