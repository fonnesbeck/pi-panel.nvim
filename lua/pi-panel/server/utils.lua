-- Pure-Lua crypto/encoding primitives for the WebSocket handshake.
-- Neovim exposes vim.fn.sha256() but no SHA-1 and no base64, both of which
-- RFC 6455 requires for Sec-WebSocket-Accept.

local M = {}

local bit = require("bit")
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local rshift, rol, tobit = bit.rshift, bit.rol, bit.tobit

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

--- Base64-encode a raw byte string (RFC 4648).
---@param data string
---@return string
function M.base64_encode(data)
  local out = {}
  local n = #data
  local i = 1
  while i <= n do
    local b1 = data:byte(i)
    local b2 = data:byte(i + 1)
    local b3 = data:byte(i + 2)

    local c1 = math.floor(b1 / 4)
    local c2 = (b1 % 4) * 16 + (b2 and math.floor(b2 / 16) or 0)
    out[#out + 1] = B64:sub(c1 + 1, c1 + 1)
    out[#out + 1] = B64:sub(c2 + 1, c2 + 1)

    if b2 then
      local c3 = (b2 % 16) * 4 + (b3 and math.floor(b3 / 64) or 0)
      out[#out + 1] = B64:sub(c3 + 1, c3 + 1)
    else
      out[#out + 1] = "="
    end

    if b3 then
      local c4 = b3 % 64
      out[#out + 1] = B64:sub(c4 + 1, c4 + 1)
    else
      out[#out + 1] = "="
    end

    i = i + 3
  end
  return table.concat(out)
end

local function be32(x)
  return string.char(
    band(rshift(x, 24), 0xff),
    band(rshift(x, 16), 0xff),
    band(rshift(x, 8), 0xff),
    band(x, 0xff))
end

--- SHA-1 of a byte string (FIPS 180), returning the raw 20-byte digest.
---@param message string
---@return string
function M.sha1(message)
  local h0, h1, h2, h3, h4 =
    0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0

  local ml = #message * 8 -- message length in bits (fits in a double for our sizes)

  -- Pad: append 0x80, then zeros until length ≡ 56 (mod 64), then 64-bit BE length.
  message = message .. "\128"
  while (#message % 64) ~= 56 do
    message = message .. "\0"
  end
  local len_bytes = {}
  local rem = ml
  for idx = 8, 1, -1 do
    len_bytes[idx] = string.char(rem % 256)
    rem = math.floor(rem / 256)
  end
  message = message .. table.concat(len_bytes)

  local w = {}
  for chunk = 1, #message, 64 do
    for i = 0, 15 do
      local p = chunk + i * 4
      w[i] = bor(
        bit.lshift(message:byte(p), 24),
        bit.lshift(message:byte(p + 1), 16),
        bit.lshift(message:byte(p + 2), 8),
        message:byte(p + 3))
    end
    for i = 16, 79 do
      w[i] = rol(bxor(w[i - 3], w[i - 8], w[i - 14], w[i - 16]), 1)
    end

    local a, b, c, d, e = h0, h1, h2, h3, h4
    for i = 0, 79 do
      local f, k
      if i < 20 then
        f = bor(band(b, c), band(bnot(b), d))
        k = 0x5A827999
      elseif i < 40 then
        f = bxor(b, c, d)
        k = 0x6ED9EBA1
      elseif i < 60 then
        f = bor(band(b, c), band(b, d), band(c, d))
        k = 0x8F1BBCDC
      else
        f = bxor(b, c, d)
        k = 0xCA62C1D6
      end
      local temp = tobit(rol(a, 5) + f + e + k + w[i])
      e, d, c, b, a = d, c, rol(b, 30), a, temp
    end

    h0 = tobit(h0 + a)
    h1 = tobit(h1 + b)
    h2 = tobit(h2 + c)
    h3 = tobit(h3 + d)
    h4 = tobit(h4 + e)
  end

  return be32(h0) .. be32(h1) .. be32(h2) .. be32(h3) .. be32(h4)
end

--- 16 random bytes from libuv's CSPRNG, with a math.random fallback.
local function random_bytes(n)
  local ok, rnd = pcall(vim.uv.random, n)
  if ok and type(rnd) == "string" and #rnd == n then
    return rnd
  end
  math.randomseed(tonumber(tostring(vim.uv.hrtime()):sub(-9)) + vim.fn.getpid())
  local out = {}
  for i = 1, n do
    out[i] = string.char(math.random(0, 255))
  end
  return table.concat(out)
end

--- Generate a random RFC 4122 version-4 UUID string.
---@return string
function M.uuid_v4()
  local b = { random_bytes(16):byte(1, 16) }
  b[7] = band(b[7], 0x0f) + 0x40 -- version 4
  b[9] = band(b[9], 0x3f) + 0x80 -- variant 10xx
  local hex = {}
  for i = 1, 16 do
    hex[i] = string.format("%02x", b[i])
  end
  return table.concat({
    table.concat(hex, "", 1, 4),
    table.concat(hex, "", 5, 6),
    table.concat(hex, "", 7, 8),
    table.concat(hex, "", 9, 10),
    table.concat(hex, "", 11, 16),
  }, "-")
end

return M
