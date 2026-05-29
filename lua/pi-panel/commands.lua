-- User-facing :Pi* commands. Registration is idempotent so it can be driven
-- from both the plugin/ file (so commands exist without setup) and setup().

local M = {}

local registered = false

function M.register()
  if registered then
    return
  end
  registered = true

  local function cmd(name, method, opts)
    vim.api.nvim_create_user_command(name, function()
      require("pi-panel")[method]()
    end, opts or {})
  end

  cmd("Pi", "toggle", { desc = "Toggle the pi panel" })
  cmd("PiFocus", "focus", { desc = "Focus the pi panel (open if needed)" })
  cmd("PiStart", "open", { desc = "Start the WebSocket server and launch pi" })
  cmd("PiStop", "stop", { desc = "Stop pi and the WebSocket server" })
  cmd("PiStatus", "status", { desc = "Show pi connection status" })
end

return M
