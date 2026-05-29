local t = require("support.runner")
local native = require("pi-panel.terminal.native")

-- A long-lived, side-effect-free command so the terminal job stays open for
-- the duration of the assertions.
local CMD = { "sleep", "30" }
local CFG = {
  terminal = { split_side = "right", split_width_percentage = 0.30, auto_close = false },
}

local function open()
  native.open({ cmd = CMD, env = {}, cfg = CFG })
end

t.describe("terminal.native open/close", function()
  t.it("opens a terminal buffer in a split and reports is_open", function()
    native.close() -- ensure clean slate
    t.eq(native.is_open(), false, "starts closed")
    open()
    t.is_true(native.is_open(), "open after open()")
    -- the focused buffer should be a terminal
    t.eq(vim.bo[vim.api.nvim_get_current_buf()].buftype, "terminal")
    native.close()
    t.eq(native.is_open(), false, "closed after close()")
  end)
end)

t.describe("terminal.native toggle", function()
  t.it("hides the window but keeps the buffer, then reopens it", function()
    native.close()
    open()
    local buf = vim.api.nvim_get_current_buf()
    t.is_true(native.is_open())

    native.toggle() -- hide
    t.eq(native.is_open(), false, "hidden after toggle")
    t.is_true(vim.api.nvim_buf_is_valid(buf), "buffer survives hide")

    native.toggle() -- reopen
    t.is_true(native.is_open(), "reopened after second toggle")
    t.eq(vim.api.nvim_get_current_buf(), buf, "same buffer reused")
    native.close()
  end)
end)
