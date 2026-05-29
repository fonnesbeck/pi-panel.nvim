-- JSON-RPC handler registry. Tool handlers (open_file, open_diff, ...) are
-- added in later phases; Phase 1 ships only capability negotiation.

local M = {}

local PROTOCOL_VERSION = 1

M.registry = {}

--- Capability negotiation. Both sides exchange protocol version + tool list;
--- a mismatch is warned (never rejected) so the protocol can evolve.
M.registry.initialize = function(params)
  if params.protocolVersion ~= PROTOCOL_VERSION then
    vim.notify(
      ("pi-panel: protocol version mismatch (peer=%s, neovim=%d)")
        :format(tostring(params.protocolVersion), PROTOCOL_VERSION),
      vim.log.levels.WARN)
  end

  -- Tool names this Neovim end can service. Populated as handlers land in
  -- Phases 3–5; empty for now (the server has no tools wired yet).
  local supported = {}
  for method in pairs(M.registry) do
    if method ~= "initialize" then
      supported[#supported + 1] = method
    end
  end

  return { protocolVersion = PROTOCOL_VERSION, supportedTools = supported }
end

return M
