-- Configuration management: defaults, deep-merge of user options, validation.

local M = {}

--- The full default configuration. See README/PLAN for field semantics.
M.defaults = {
  -- Auto-start the WebSocket server and launch pi on setup().
  auto_start = true,

  -- Which agent to drive: "pi" | "omp". Selects the default binary and the
  -- ~/.<variant>/ide lock directory. See M.variants below.
  variant = "pi",

  -- Override the agent binary (nil = use the variant's binary from PATH).
  -- Wins over the variant's default cmd; useful for a non-PATH install.
  pi_cmd = nil,

  -- Extra environment variables for the pi process.
  env = {},

  terminal = {
    provider = "auto", -- "auto" | "snacks" | "native"  ("external" is future)
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

  whichkey = {
    enabled = true,
    leader = "p",
  },
}

-- Known agent variants. Each maps to the default binary, the discovery lock
-- directory (a pi-panel convention under the agent's home), and a display name
-- used in user-facing status/connection messages.
M.variants = {
  pi = { cmd = "pi", lockfile_dir = "~/.pi/ide", display = "pi" },
  omp = { cmd = "omp", lockfile_dir = "~/.omp/ide", display = "oh-my-pi" },
}

--- Resolve the active variant spec for a config, defaulting to "pi".
---@param cfg table
---@return { cmd: string, lockfile_dir: string, display: string }
function M.variant(cfg)
  return M.variants[cfg.variant] or M.variants.pi
end

-- "external" (tmux/kitty/wezterm) is documented as future and has no provider
-- module yet, so it is intentionally NOT accepted here — selecting it fails at
-- setup() rather than crashing later in terminal/init.lua.
local PROVIDERS = { auto = true, snacks = true, native = true }
local SPLIT_SIDES = { left = true, right = true }

local function validate(cfg)
  if not M.variants[cfg.variant] then
    error(("pi-panel: invalid variant %q (expected pi|omp)"):format(tostring(cfg.variant)))
  end
  local term = cfg.terminal
  if not PROVIDERS[term.provider] then
    error(("pi-panel: invalid terminal.provider %q (expected auto|snacks|native)"):format(tostring(term.provider)))
  end
  if not SPLIT_SIDES[term.split_side] then
    error(("pi-panel: invalid terminal.split_side %q (expected left|right)"):format(tostring(term.split_side)))
  end
  local pct = term.split_width_percentage
  if type(pct) ~= "number" or pct <= 0 or pct >= 1 then
    error(("pi-panel: invalid terminal.split_width_percentage %s (expected a number in (0,1))"):format(tostring(pct)))
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
  -- Resolve the variant once here so downstream modules read plain fields off
  -- cfg (cmd / lockfile_dir / display) without reaching back into this module.
  -- pi_cmd, when set, overrides the variant's default binary.
  local v = M.variant(merged)
  merged.cmd = merged.pi_cmd or v.cmd
  merged.lockfile_dir = v.lockfile_dir
  merged.display = v.display
  current = merged
  return merged
end

--- The active config (a deepcopy of defaults if setup() hasn't run yet).
---@return table
function M.get()
  return current or vim.deepcopy(M.defaults)
end

return M
