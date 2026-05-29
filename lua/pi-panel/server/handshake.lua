-- RFC 6455 opening handshake: parse the client's HTTP upgrade request,
-- validate the auth token, and build the 101 Switching Protocols response.

local utils = require("pi-panel.server.utils")

local M = {}

-- Magic GUID from RFC 6455 section 1.3.
local GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

-- Header carrying the per-session auth token (matches the lock file's authToken).
M.AUTH_HEADER = "x-pi-ide-authorization"

--- Compute the Sec-WebSocket-Accept value for a given Sec-WebSocket-Key.
---@param key string
---@return string
function M.compute_accept(key)
  return utils.base64_encode(utils.sha1(key .. GUID))
end

--- Parse a raw HTTP request. Returns nil if the header block is incomplete.
---@param raw string
---@return { method: string, path: string, version: string, headers: table<string,string> }|nil
function M.parse_request(raw)
  if not raw:find("\r\n\r\n", 1, true) then
    return nil -- headers not fully received yet
  end

  local header_block = raw:match("^(.-)\r\n\r\n")
  local lines = {}
  for line in (header_block .. "\r\n"):gmatch("(.-)\r\n") do
    lines[#lines + 1] = line
  end

  local method, path, version = lines[1]:match("^(%S+)%s+(%S+)%s+(%S+)$")
  if not method then
    return nil
  end

  local headers = {}
  for i = 2, #lines do
    local name, value = lines[i]:match("^([^:]+):%s*(.-)%s*$")
    if name then
      headers[name:lower()] = value
    end
  end

  return { method = method, path = path, version = version, headers = headers }
end

local function error_response(code, status)
  return ("HTTP/1.1 %d %s\r\nConnection: close\r\nContent-Length: 0\r\n\r\n")
    :format(code, status)
end

--- Handle a complete handshake request.
--- Returns: response_string, accepted(boolean), reason(string|nil)
--- On success the response is a 101 upgrade; on failure it is a 4xx to send
--- before closing the socket.
---@param raw string
---@param expected_token string
---@return string response, boolean accepted, string? reason
function M.handle(raw, expected_token)
  local req = M.parse_request(raw)
  if not req then
    return error_response(400, "Bad Request"), false, "malformed request"
  end

  local h = req.headers
  if (h["upgrade"] or ""):lower() ~= "websocket" then
    return error_response(400, "Bad Request"), false, "missing websocket upgrade"
  end

  local key = h["sec-websocket-key"]
  if not key then
    return error_response(400, "Bad Request"), false, "missing Sec-WebSocket-Key"
  end

  local token = h[M.AUTH_HEADER]
  if not token or token ~= expected_token then
    return error_response(401, "Unauthorized"), false, "invalid or missing auth token"
  end

  local response = table.concat({
    "HTTP/1.1 101 Switching Protocols",
    "Upgrade: websocket",
    "Connection: Upgrade",
    "Sec-WebSocket-Accept: " .. M.compute_accept(key),
    "",
    "",
  }, "\r\n")
  return response, true, nil
end

return M
