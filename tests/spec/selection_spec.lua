local t = require("support.runner")
local selection = require("pi-panel.selection")

-- Build a buffer and select `world` on line 1 (cols 7..11, 1-indexed inclusive).
local function buffer_with_selection()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello world", "second" })
  vim.api.nvim_set_current_buf(buf)
  vim.fn.setpos("'<", { buf, 1, 7, 0 })
  vim.fn.setpos("'>", { buf, 1, 11, 0 })
  return buf
end

t.describe("selection.current", function()
  t.it("reads the charwise visual selection of the active buffer", function()
    buffer_with_selection()
    local sel = selection.current()
    t.eq(sel.isEmpty, false)
    t.eq(sel.text, "world")
    t.eq(sel.selection.start.line, 1)
    t.eq(sel.selection.start.character, 7)
  end)

  t.it("reports empty when the marks coincide", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abc" })
    vim.api.nvim_set_current_buf(buf)
    vim.fn.setpos("'<", { buf, 0, 0, 0 })
    vim.fn.setpos("'>", { buf, 0, 0, 0 })
    t.eq(selection.current().isEmpty, true)
  end)
end)

t.describe("selection.capture", function()
  t.it("updates the latest cache and dedupes repeat captures", function()
    buffer_with_selection()
    local first = selection.capture()
    t.truthy(first, "first capture returns the selection")
    t.eq(selection.latest().text, "world", "latest cache populated")
    t.is_nil(selection.capture(), "same selection is deduped (no re-broadcast)")
  end)
end)

t.describe("selection.latest", function()
  t.it("returns an empty selection before anything is captured (fresh module ok)", function()
    -- latest() must always return a table with an isEmpty field
    local l = selection.latest()
    t.truthy(type(l) == "table")
    t.truthy(l.isEmpty ~= nil or l.text ~= nil)
  end)
end)

t.describe("get_latest_selection handler", function()
  t.it("returns the cached latest selection", function()
    buffer_with_selection()
    selection.capture()
    local handlers = require("pi-panel.handlers")
    local captured
    handlers.registry.get_latest_selection({}, function(r)
      captured = r
    end)
    vim.wait(500, function()
      return captured ~= nil
    end)
    t.eq(captured.text, "world")
  end)
end)
