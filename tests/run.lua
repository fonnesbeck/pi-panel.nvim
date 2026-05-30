-- Entry point: `nvim --headless -l tests/run.lua [spec_name]`
-- Discovers and runs tests/spec/*_spec.lua. Exits non-zero if any fail.

local root = vim.fn.getcwd()
package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  root .. "/tests/?.lua",
  package.path,
}, ";")

local filter = arg and arg[1] -- optional: run only spec files matching this substring

local spec_dir = root .. "/tests/spec"
local entries = vim.fn.globpath(spec_dir, "*_spec.lua", false, true)
table.sort(entries)

local runner = require("support.runner")

for _, path in ipairs(entries) do
  local name = path:match("([^/]+)%.lua$")
  if not filter or name:find(filter, 1, true) then
    local mod = name:gsub("%.lua$", "")
    local ok, err = pcall(require, "spec." .. mod)
    if not ok then
      -- Surface a load error as a failing test rather than aborting the run.
      runner.describe(name .. " (load error)", function()
        runner.it("loads", function()
          error(err, 0)
        end)
      end)
    end
  end
end

local failed = runner.run()
os.exit(failed > 0 and 1 or 0)
