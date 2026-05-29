-- Configuration management: defaults, deep-merge of user options, validation.

local M = {}

--- The full default configuration. See README/PLAN for field semantics.
M.defaults = {
  -- Auto-start the WebSocket server and launch pi on setup().
  auto_start = true,

  -- Port range for the WebSocket server (0 lets the OS pick within bind()).
  port_range = { min = 10000, max = 65535 },

  -- Pi binary (nil = resolve "pi" from PATH).
  pi_cmd = nil,

  -- Extra environment variables for the pi process.
  env = {},

  terminal = {
    provider = "auto", -- "auto" | "snacks" | "native" | "external"
    split_side = "right", -- "left" | "right"
    split_width_percentage = 0.30,
    auto_close = true,
    snacks_win_opts = {},
  },

  track_selection = true,
  visual_demotion_delay_ms = 50,

  connection_timeout = 10000,
  reconnect_max_delay = 30000,

  diff_opts = {
    layout = "vertical",
    open_in_new_tab = false,
    keep_terminal_focus = false,
    timeout = 300,
  },

  log_level = "info", -- "trace" | "debug" | "info" | "warn" | "error"

  whichkey = {
    enabled = true,
    leader = "p",
  },
}

local PROVIDERS = { auto = true, snacks = true, native = true, external = true }
local SPLIT_SIDES = { left = true, right = true }
local LOG_LEVELS = { trace = true, debug = true, info = true, warn = true, error = true }

local function validate(cfg)
  local term = cfg.terminal
  if not PROVIDERS[term.provider] then
    error(("pi-panel: invalid terminal.provider %q (expected auto|snacks|native|external)")
      :format(tostring(term.provider)))
  end
  if not SPLIT_SIDES[term.split_side] then
    error(("pi-panel: invalid terminal.split_side %q (expected left|right)")
      :format(tostring(term.split_side)))
  end
  local pct = term.split_width_percentage
  if type(pct) ~= "number" or pct <= 0 or pct >= 1 then
    error(("pi-panel: invalid terminal.split_width_percentage %s (expected a number in (0,1))")
      :format(tostring(pct)))
  end
  if not LOG_LEVELS[cfg.log_level] then
    error(("pi-panel: invalid log_level %q (expected trace|debug|info|warn|error)")
      :format(tostring(cfg.log_level)))
  end
end

local current = nil

--- Merge `opts` over the defaults, validate, store, and return the result.
--- Raises on invalid configuration.
---@param opts? table
---@return table
function M.setup(opts)
  local merged = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  validate(merged)
  current = merged
  return merged
end

--- The active config (a deepcopy of defaults if setup() hasn't run yet).
---@return table
function M.get()
  return current or vim.deepcopy(M.defaults)
end

return M
