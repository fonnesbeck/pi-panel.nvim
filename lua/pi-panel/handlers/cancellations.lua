-- Registry of cancel callbacks for in-flight blocking tools (open_diff),
-- keyed by JSON-RPC request id. The dispatch layer passes a request's id to
-- its handler as params._requestId; a `cancel` notification carries that id in
-- params.id and triggers the registered callback.

local M = {}

local registry = {}

function M.register(id, fn)
  if id ~= nil then
    registry[id] = fn
  end
end

function M.unregister(id)
  if id ~= nil then
    registry[id] = nil
  end
end

function M.cancel(id)
  local fn = registry[id]
  if fn then
    fn()
  end
end

return M
