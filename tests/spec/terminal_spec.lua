local t = require("support.runner")
local terminal = require("pi-panel.terminal")
local utils = require("pi-panel.utils")
local lockfile = require("pi-panel.lockfile")

t.describe("terminal.build_cmd", function()
  t.it("defaults to `pi` from PATH and loads the bundled extension via -e", function()
    local cmd = terminal.build_cmd({ pi_cmd = nil })
    t.eq(cmd, { "pi", "-e", utils.extension_path() })
  end)

  t.it("honours an explicit pi_cmd path", function()
    local cmd = terminal.build_cmd({ pi_cmd = "/opt/pi/bin/pi" })
    t.eq(cmd, { "/opt/pi/bin/pi", "-e", utils.extension_path() })
  end)
end)

t.describe("terminal.build_env", function()
  t.it("sets the PI_IDE_* discovery vars from the running server", function()
    local env = terminal.build_env({ env = {} }, { port = 4321, token = "tok-xyz" })
    t.eq(env.PI_IDE_PORT, "4321", "port stringified")
    t.eq(env.PI_IDE_AUTH, "tok-xyz")
    t.eq(env.PI_IDE_LOCKFILE, lockfile.path(4321))
  end)

  t.it("merges user-supplied env without clobbering the discovery vars", function()
    local env = terminal.build_env(
      { env = { FOO = "bar", PI_IDE_PORT = "ignored" } },
      { port = 10, token = "t" }
    )
    t.eq(env.FOO, "bar", "user var passed through")
    t.eq(env.PI_IDE_PORT, "10", "discovery var wins over user override")
  end)
end)

t.describe("terminal.select_provider", function()
  t.it("returns an explicitly configured provider unchanged", function()
    t.eq(terminal.select_provider({ terminal = { provider = "native" } }), "native")
    t.eq(terminal.select_provider({ terminal = { provider = "snacks" } }), "snacks")
  end)

  t.it("auto resolves to snacks when snacks is available", function()
    t.eq(terminal.select_provider({ terminal = { provider = "auto" } }, true), "snacks")
  end)

  t.it("auto falls back to native when snacks is missing", function()
    t.eq(terminal.select_provider({ terminal = { provider = "auto" } }, false), "native")
  end)
end)
