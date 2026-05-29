-- JSON-RPC handler registry. Capability negotiation plus the Phase 3 tools
-- (open_file, get_selection, get_workspace_folders). More land in Phases 4–5.

local M = {}

local PROTOCOL_VERSION = 1

M.registry = {
  open_file = require("pi-panel.handlers.open_file").handle,
  open_diff = require("pi-panel.handlers.open_diff").handle,
  get_selection = require("pi-panel.handlers.get_selection").handle,
  get_workspace_folders = require("pi-panel.handlers.get_workspace_folders").handle,
  get_open_editors = require("pi-panel.handlers.get_open_editors").handle,
  get_diagnostics = require("pi-panel.handlers.get_diagnostics").handle,
  check_dirty = require("pi-panel.handlers.check_dirty").handle,
  save_document = require("pi-panel.handlers.save_document").handle,
  close_tab = require("pi-panel.handlers.close_tab").handle,
  close_all_diff_tabs = require("pi-panel.handlers.close_all_diff_tabs").handle,
}

-- `cancel` is a notification (no response): an Esc in pi aborts a blocking
-- tool. It carries the cancelled request's id in params.id.
M.registry.cancel = function(params)
  require("pi-panel.handlers.cancellations").cancel(params.id)
end

--- Capability negotiation. Both sides exchange protocol version + tool list;
--- a mismatch is warned (never rejected) so the protocol can evolve.
M.registry.initialize = function(params)
  if params.protocolVersion ~= PROTOCOL_VERSION then
    vim.notify(
      ("pi-panel: protocol version mismatch (peer=%s, neovim=%d)")
        :format(tostring(params.protocolVersion), PROTOCOL_VERSION),
      vim.log.levels.WARN)
  end

  -- Tool names this Neovim end can service (registry keys minus the internal
  -- initialize/cancel control methods).
  local supported = {}
  for method in pairs(M.registry) do
    if method ~= "initialize" and method ~= "cancel" then
      supported[#supported + 1] = method
    end
  end

  return { protocolVersion = PROTOCOL_VERSION, supportedTools = supported }
end

return M
