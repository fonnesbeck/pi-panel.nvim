local t = require("support.runner")
local pi = require("pi-panel")
local config = require("pi-panel.config")

local function cmd_exists(name)
  return vim.fn.exists(":" .. name) == 2
end

t.describe("pi-panel.setup", function()
  t.it("applies and validates configuration", function()
    pi.setup({ auto_start = false, terminal = { split_side = "left" } })
    t.eq(config.get().terminal.split_side, "left")
    t.eq(config.get().auto_start, false)
  end)

  t.it("registers the user-facing commands", function()
    pi.setup({ auto_start = false })
    t.is_true(cmd_exists("Pi"), ":Pi defined")
    t.is_true(cmd_exists("PiFocus"), ":PiFocus defined")
    t.is_true(cmd_exists("PiStart"), ":PiStart defined")
    t.is_true(cmd_exists("PiStop"), ":PiStop defined")
    t.is_true(cmd_exists("PiStatus"), ":PiStatus defined")
  end)

  t.it("propagates invalid config as an error", function()
    t.error_contains(function()
      pi.setup({ terminal = { provider = "nope" } })
    end, "provider")
  end)
end)
