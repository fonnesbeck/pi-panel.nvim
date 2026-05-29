-- which-key integration: registers a discoverable <leader>p group. No-op (and
-- harmless) when which-key isn't installed. Supports both the v3 (`add`) and
-- v2 (`register`) APIs.

local M = {}

---@param opts { leader?: string }
---@return boolean registered
function M.register(opts)
  local ok, wk = pcall(require, "which-key")
  if not ok then
    return false
  end
  local p = "<leader>" .. (opts.leader or "p")

  if type(wk.add) == "function" then
    wk.add({
      { p, group = "pi" },
      { p .. "p", "<cmd>Pi<cr>", desc = "Toggle panel" },
      { p .. "f", "<cmd>PiFocus<cr>", desc = "Focus panel" },
      { p .. "s", "<cmd>PiSend<cr>", desc = "Send selection", mode = "v" },
      { p .. "a", "<cmd>PiAccept<cr>", desc = "Accept diff" },
      { p .. "r", "<cmd>PiReject<cr>", desc = "Reject diff" },
      { p .. "b", "<cmd>PiAdd %<cr>", desc = "Add current buffer" },
      { p .. "x", "<cmd>PiStop<cr>", desc = "Stop pi" },
    })
  elseif type(wk.register) == "function" then
    wk.register({
      [opts.leader or "p"] = {
        name = "pi",
        p = { "<cmd>Pi<cr>", "Toggle panel" },
        f = { "<cmd>PiFocus<cr>", "Focus panel" },
        s = { "<cmd>PiSend<cr>", "Send selection" },
        a = { "<cmd>PiAccept<cr>", "Accept diff" },
        r = { "<cmd>PiReject<cr>", "Reject diff" },
        b = { "<cmd>PiAdd %<cr>", "Add current buffer" },
        x = { "<cmd>PiStop<cr>", "Stop pi" },
      },
    }, { prefix = "<leader>" })
  end
  return true
end

return M
