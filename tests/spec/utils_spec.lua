local t = require("support.runner")
local utils = require("pi-panel.utils")

t.describe("utils.plugin_root", function()
  t.it("resolves to the repo root (three dirs above lua/pi-panel/utils.lua)", function()
    -- Tests run with cwd == repo root, and package.path points at <root>/lua,
    -- so the module's source path resolves back to the repo root.
    t.eq(utils.plugin_root(), vim.fn.getcwd())
  end)
end)

t.describe("utils.extension_path", function()
  t.it("points at the committed esbuild bundle under extensions/", function()
    t.eq(utils.extension_path(), utils.plugin_root() .. "/extensions/pi-nvim-bridge/dist/index.js")
  end)
end)
