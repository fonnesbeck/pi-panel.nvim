-- TCP listener (vim.uv) bound to localhost. Each accepted socket gets a Client
-- that drives the handshake/frame/dispatch pipeline. Localhost-only by default.

local Client = require("pi-panel.server.client")

local M = {}

--- Start listening. Returns { handle, port, clients }.
---@param opts { host?: string, port?: integer, expected_token: string, registry: table }
function M.listen(opts)
  local host = opts.host or "127.0.0.1"
  local server = assert(vim.uv.new_tcp())
  assert(server:bind(host, opts.port or 0))

  local clients = {} -- set of live Client objects

  server:listen(128, function(err)
    assert(not err, err)
    local sock = assert(vim.uv.new_tcp())
    server:accept(sock)

    local client
    local function drop()
      clients[client] = nil
      if not sock:is_closing() then
        sock:close()
      end
    end

    client = Client.new({
      write = function(data)
        if not sock:is_closing() then
          sock:write(data)
        end
      end,
      close = drop,
      expected_token = opts.expected_token,
      registry = opts.registry,
    })
    clients[client] = true

    sock:read_start(function(rerr, chunk)
      if rerr or not chunk then -- error or EOF
        drop()
        return
      end
      client:feed(chunk)
    end)
  end)

  local name = server:getsockname()
  return { handle = server, port = name.port, clients = clients }
end

return M
