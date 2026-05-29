local t = require("support.runner")
local status = require("pi-panel.status")
local server = require("pi-panel.server")

t.describe("status.statusline", function()
  t.it("reports off when the server is not running", function()
    if server.is_running() then
      server.stop()
    end
    t.eq(status.statusline(), "pi: off")
  end)

  t.it("reports waiting when the server runs but no client is connected", function()
    server.start({ write_lock = false })
    t.eq(status.statusline(), "pi: waiting")
    server.stop()
    t.eq(status.statusline(), "pi: off")
  end)
end)
