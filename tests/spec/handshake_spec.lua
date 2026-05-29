local t = require("support.runner")
local handshake = require("pi-panel.server.handshake")

local CRLF = "\r\n"
local function request(headers)
  local lines = { "GET / HTTP/1.1" }
  for _, h in ipairs(headers) do
    lines[#lines + 1] = h
  end
  return table.concat(lines, CRLF) .. CRLF .. CRLF
end

local VALID = {
  "Host: 127.0.0.1:9999",
  "Upgrade: websocket",
  "Connection: Upgrade",
  "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
  "Sec-WebSocket-Version: 13",
  "x-pi-ide-authorization: secret-token",
}

t.describe("handshake.compute_accept", function()
  -- RFC 6455 section 1.3 worked example
  t.it("matches the RFC 6455 test vector", function()
    t.eq(handshake.compute_accept("dGhlIHNhbXBsZSBub25jZQ=="),
      "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
  end)
end)

t.describe("handshake.parse_request", function()
  t.it("parses method and path", function()
    local req = handshake.parse_request(request(VALID))
    t.eq(req.method, "GET")
    t.eq(req.path, "/")
  end)
  t.it("lowercases header names for case-insensitive lookup", function()
    local req = handshake.parse_request(request(VALID))
    t.eq(req.headers["sec-websocket-key"], "dGhlIHNhbXBsZSBub25jZQ==")
    t.eq(req.headers["upgrade"], "websocket")
    t.eq(req.headers["x-pi-ide-authorization"], "secret-token")
  end)
  t.it("returns nil for a request without a header terminator", function()
    t.is_nil(handshake.parse_request("GET / HTTP/1.1\r\nUpgrade: websocket\r\n"))
  end)
end)

t.describe("handshake.handle", function()
  t.it("accepts a valid request with the correct token", function()
    local response, accepted = handshake.handle(request(VALID), "secret-token")
    t.is_true(accepted)
    t.truthy(response:find("HTTP/1.1 101", 1, true), "status line")
    t.truthy(response:find("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", 1, true), "accept header")
    t.truthy(response:find("\r\n\r\n", 1, true), "header terminator")
  end)

  t.it("rejects a request with a wrong token", function()
    local response, accepted, reason = handshake.handle(request(VALID), "different-token")
    t.eq(accepted, false)
    t.truthy(response:find("401", 1, true), "401 status")
    t.truthy(reason:find("token", 1, true), "reason mentions token")
  end)

  t.it("rejects a request with a missing token", function()
    local headers = {
      "Host: 127.0.0.1:9999",
      "Upgrade: websocket",
      "Connection: Upgrade",
      "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
      "Sec-WebSocket-Version: 13",
    }
    local _, accepted = handshake.handle(request(headers), "secret-token")
    t.eq(accepted, false)
  end)

  t.it("rejects when Sec-WebSocket-Key is absent", function()
    local headers = {
      "Host: 127.0.0.1:9999",
      "Upgrade: websocket",
      "Connection: Upgrade",
      "Sec-WebSocket-Version: 13",
      "x-pi-ide-authorization: secret-token",
    }
    local response, accepted = handshake.handle(request(headers), "secret-token")
    t.eq(accepted, false)
    t.truthy(response:find("400", 1, true), "400 status")
  end)
end)
