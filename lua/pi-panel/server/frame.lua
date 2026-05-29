-- RFC 6455 frame codec.
--   decode(buffer) -> frame, rest   (one frame at a time; nil if incomplete)
--   encode(opcode, payload, fin)    -> unmasked server frame
-- Message reassembly (continuation frames) is the caller's responsibility;
-- decode exposes `fin` and `opcode` so the caller can stitch fragments.

local bit = require("bit")
local band, bxor = bit.band, bit.bxor

local M = {}

M.CONTINUATION = 0x0
M.TEXT = 0x1
M.BINARY = 0x2
M.CLOSE = 0x8
M.PING = 0x9
M.PONG = 0xA

local function unmask(payload, key)
  local out = {}
  for i = 1, #payload do
    out[i] = string.char(bxor(payload:byte(i), key:byte((i - 1) % 4 + 1)))
  end
  return table.concat(out)
end

--- Decode a single frame from the front of `data`.
--- Returns (frame, rest) or nil if more bytes are needed.
---@param data string
---@return { fin: boolean, opcode: integer, payload: string }|nil, string?
function M.decode(data)
  local n = #data
  if n < 2 then
    return nil
  end

  local b1, b2 = data:byte(1), data:byte(2)
  local fin = band(b1, 0x80) ~= 0
  local opcode = band(b1, 0x0f)
  local masked = band(b2, 0x80) ~= 0
  local len = band(b2, 0x7f)
  local pos = 3

  if len == 126 then
    if n < pos + 1 then return nil end
    len = data:byte(pos) * 256 + data:byte(pos + 1)
    pos = pos + 2
  elseif len == 127 then
    if n < pos + 7 then return nil end
    len = 0
    for i = 0, 7 do
      len = len * 256 + data:byte(pos + i)
    end
    pos = pos + 8
  end

  local key
  if masked then
    if n < pos + 3 then return nil end
    key = data:sub(pos, pos + 3)
    pos = pos + 4
  end

  if n < pos + len - 1 then
    return nil -- payload not fully received
  end

  local payload = data:sub(pos, pos + len - 1)
  if masked then
    payload = unmask(payload, key)
  end

  local rest = data:sub(pos + len)
  return { fin = fin, opcode = opcode, payload = payload }, rest
end

--- Encode an unmasked server frame (servers MUST NOT mask, per RFC 6455).
---@param opcode integer
---@param payload string
---@param fin boolean? defaults to true
---@return string
function M.encode(opcode, payload, fin)
  local b0 = (fin == false and 0 or 0x80) + opcode
  local len = #payload
  local header
  if len < 126 then
    header = string.char(b0, len)
  elseif len < 65536 then
    header = string.char(b0, 126, math.floor(len / 256), len % 256)
  else
    local lb = {}
    local rem = len
    for i = 8, 1, -1 do
      lb[i] = string.char(rem % 256)
      rem = math.floor(rem / 256)
    end
    header = string.char(b0, 127) .. table.concat(lb)
  end
  return header .. payload
end

return M
