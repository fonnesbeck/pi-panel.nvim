local t = require("support.runner")
local frame = require("pi-panel.server.frame")

-- Build a masked client frame independently of the implementation (the inverse
-- of decode's unmasking), so round-trip tests aren't circular.
local function mask_frame(opcode, payload, fin)
  local b0 = (fin == false and 0 or 0x80) + opcode
  local len = #payload
  local header
  if len < 126 then
    header = string.char(b0, 0x80 + len)
  elseif len < 65536 then
    header = string.char(b0, 0x80 + 126, math.floor(len / 256), len % 256)
  else
    local lb = {}
    local rem = len
    for i = 8, 1, -1 do lb[i] = string.char(rem % 256); rem = math.floor(rem / 256) end
    header = string.char(b0, 0x80 + 127) .. table.concat(lb)
  end
  local key = string.char(0x37, 0xfa, 0x21, 0x3d)
  local masked = payload:gsub("()(.)", function(i, c)
    local k = key:byte((i - 1) % 4 + 1)
    return string.char(require("bit").bxor(c:byte(), k))
  end)
  return header .. key .. masked
end

t.describe("frame.decode", function()
  t.it("decodes the RFC 6455 masked 'Hello' text frame", function()
    local bytes = string.char(0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58)
    local f, rest = frame.decode(bytes)
    t.eq(f.opcode, frame.TEXT)
    t.is_true(f.fin)
    t.eq(f.payload, "Hello")
    t.eq(rest, "")
  end)

  t.it("returns nil when the frame is incomplete", function()
    local bytes = string.char(0x81, 0x85, 0x37) -- header truncated mid mask key
    local f = frame.decode(bytes)
    t.is_nil(f)
  end)

  t.it("returns trailing bytes after one complete frame", function()
    local two = mask_frame(frame.TEXT, "ab") .. mask_frame(frame.TEXT, "cd")
    local f1, rest = frame.decode(two)
    t.eq(f1.payload, "ab")
    local f2, rest2 = frame.decode(rest)
    t.eq(f2.payload, "cd")
    t.eq(rest2, "")
  end)

  t.it("handles a zero-length payload", function()
    local f = frame.decode(mask_frame(frame.PING, ""))
    t.eq(f.opcode, frame.PING)
    t.eq(f.payload, "")
  end)

  t.it("handles extended 16-bit payload length (126)", function()
    local payload = string.rep("x", 300)
    local f = frame.decode(mask_frame(frame.BINARY, payload))
    t.eq(f.opcode, frame.BINARY)
    t.eq(#f.payload, 300)
    t.eq(f.payload, payload)
  end)

  t.it("decodes control opcodes (close, pong)", function()
    t.eq(frame.decode(mask_frame(frame.CLOSE, "")).opcode, frame.CLOSE)
    t.eq(frame.decode(mask_frame(frame.PONG, "pong")).opcode, frame.PONG)
  end)

  t.it("reports fragmentation via fin and continuation opcode", function()
    local first = frame.decode(mask_frame(frame.TEXT, "Hel", false))
    t.eq(first.fin, false)
    t.eq(first.opcode, frame.TEXT)
    local cont = frame.decode(mask_frame(frame.CONTINUATION, "lo", true))
    t.is_true(cont.fin)
    t.eq(cont.opcode, frame.CONTINUATION)
  end)
end)

t.describe("frame.encode", function()
  t.it("encodes an unmasked server text frame", function()
    local out = frame.encode(frame.TEXT, "Hello")
    t.eq(out, string.char(0x81, 0x05) .. "Hello")
  end)

  t.it("does not set the mask bit (server frames are unmasked)", function()
    local out = frame.encode(frame.TEXT, "hi")
    t.is_true(out:byte(2) < 0x80, "mask bit must be clear")
  end)

  t.it("uses 16-bit extended length at the 126-byte boundary", function()
    local out = frame.encode(frame.BINARY, string.rep("y", 126))
    t.eq(out:byte(1), 0x82)        -- FIN + binary
    t.eq(out:byte(2), 126)         -- extended-length marker
    t.eq(out:byte(3), 0)           -- length high byte
    t.eq(out:byte(4), 126)         -- length low byte
    t.eq(#out, 4 + 126)
  end)

  t.it("round-trips through decode (encode server, decode is symmetric for content)", function()
    local out = frame.encode(frame.TEXT, "round trip")
    -- server frames are unmasked; decode must accept unmasked frames too
    local f = frame.decode(out)
    t.eq(f.payload, "round trip")
    t.is_true(f.fin)
  end)
end)
