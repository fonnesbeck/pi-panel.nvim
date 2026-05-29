-- Test helpers for building raw WebSocket bytes (client side).
local bit = require("bit")

local M = {}

--- Build a masked client frame (the inverse of frame.decode's unmasking).
---@param opcode integer
---@param payload string
---@param fin boolean? defaults to true
function M.mask_frame(opcode, payload, fin)
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
    for i = 8, 1, -1 do
      lb[i] = string.char(rem % 256)
      rem = math.floor(rem / 256)
    end
    header = string.char(b0, 0x80 + 127) .. table.concat(lb)
  end
  local key = string.char(0x37, 0xfa, 0x21, 0x3d)
  local masked = payload:gsub("()(.)", function(i, c)
    return string.char(bit.bxor(c:byte(), key:byte((i - 1) % 4 + 1)))
  end)
  return header .. key .. masked
end

--- Build a raw HTTP upgrade request.
---@param token string|nil  auth token (omitted if nil)
function M.upgrade_request(token)
  local lines = {
    "GET / HTTP/1.1",
    "Host: 127.0.0.1:0",
    "Upgrade: websocket",
    "Connection: Upgrade",
    "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
    "Sec-WebSocket-Version: 13",
  }
  if token then
    lines[#lines + 1] = "x-pi-ide-authorization: " .. token
  end
  return table.concat(lines, "\r\n") .. "\r\n\r\n"
end

return M
