-- JSON-RPC handler registry. Capability negotiation plus the Phase 3 tools
-- (open_file, get_selection, get_workspace_folders). More land in Phases 4–5.

local M = {}

local PROTOCOL_VERSION = 1

M.registry = {
  open_file = require("pi-panel.handlers.open_file").handle,
  get_selection = require("pi-panel.handlers.get_selection").handle,
  get_workspace_folders = require("pi-panel.handlers.get_workspace_folders").handle,
}

--- Capability negotiation. Both sides exchange protocol version + tool list;
--- a mismatch is warned (never rejected) so the protocol can evolve.
M.registry.initialize = function(params)
  if params.protocolVersion ~= PROTOCOL_VERSION then
    vim.notify(
      ("pi-panel: protocol version mismatch (peer=%s, neovim=%d)")
        :format(tostring(params.protocolVersion), PROTOCOL_VERSION),
      vim.log.levels.WARN)
  end

  -- Tool names this Neovim end can service (every registry key but initialize).
  local supported = {}
  for method in pairs(M.registry) do
    if method ~= "initialize" then
      supported[#supported + 1] = method
    end
  end

  return { protocolVersion = PROTOCOL_VERSION, supportedTools = supported }
end

return M
