-- open_diff: blocking tool. Opens a diff view and does not respond until the
-- user accepts/rejects, the request is cancelled (Esc in pi), or the timeout
-- fires. All paths funnel through respond_once so exactly one JSON-RPC
-- response is sent and the timeout timer never leaks.

local config = require("pi-panel.config")
local cancellations = require("pi-panel.handlers.cancellations")

local M = {}

---@param params { filePath: string, newContents: string, oldContents?: string, _requestId?: string }
---@param respond fun(result: table)
function M.handle(params, respond)
  local req_id = params._requestId
  local responded = false
  local timer

  local function respond_once(result)
    if responded then
      return
    end
    responded = true
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    cancellations.unregister(req_id)
    respond(result)
  end

  vim.schedule(function()
    local diff = require("pi-panel.diff")
    local view = diff.open(params, function(result)
      respond_once({ content = { { type = "text", text = result } } })
    end)

    -- Esc in pi -> extension sends a `cancel` notification -> close the diff.
    cancellations.register(req_id, function()
      diff.close(view)
      respond_once({ error = { code = -32001, message = "Diff cancelled" } })
    end)

    local timeout_ms = math.floor((config.get().diff_opts.timeout or 300) * 1000)
    timer = vim.defer_fn(function()
      diff.close(view)
      respond_once({ error = { code = -32000, message = "Diff timeout" } })
    end, timeout_ms)
  end)
end

return M
