local t = require("support.runner")
local handlers = require("pi-panel.handlers")

-- Async handler call helper (same pattern as handlers_spec).
local function call(method, params)
  assert(handlers.registry[method], "no handler: " .. method)
  local captured
  handlers.registry[method](params or {}, function(r)
    captured = r
  end)
  vim.wait(500, function()
    return captured ~= nil
  end)
  return captured
end

local function find(list, pred)
  for _, item in ipairs(list) do
    if pred(item) then
      return item
    end
  end
end

t.describe("handlers.get_open_editors", function()
  t.it("lists named, listed buffers with active/dirty flags", function()
    local name = vim.fn.tempname() .. "_open.txt"
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, name)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x" }) -- marks modified

    local r = call("get_open_editors", {})
    local entry = find(r.editors, function(e)
      return e.filePath == name
    end)
    t.truthy(entry, "our buffer is listed")
    t.eq(entry.active, true, "current buffer marked active")
    t.eq(entry.dirty, true, "modified buffer marked dirty")
  end)
end)

t.describe("handlers.get_diagnostics", function()
  t.it("returns LSP diagnostics for a file with mapped severity names", function()
    local name = vim.fn.tempname() .. "_diag.txt"
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, name)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "aaa", "bbb" })
    local ns = vim.api.nvim_create_namespace("pi_test_diag")
    vim.diagnostic.set(ns, buf, {
      { lnum = 0, col = 1, message = "boom", severity = vim.diagnostic.severity.ERROR, source = "x" },
    })

    local r = call("get_diagnostics", { filePath = name })
    local d = find(r.diagnostics, function(x)
      return x.message == "boom"
    end)
    t.truthy(d, "diagnostic present")
    t.eq(d.severity, "ERROR")
    t.eq(d.line, 1, "1-indexed line")
  end)
end)

t.describe("handlers.check_dirty", function()
  t.it("reports modified state for a file", function()
    local name = vim.fn.tempname() .. "_chk.txt"
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, name)
    t.eq(call("check_dirty", { filePath = name }).isDirty, false, "fresh buffer not dirty")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "edit" })
    t.eq(call("check_dirty", { filePath = name }).isDirty, true, "edited buffer dirty")
  end)

  t.it("reports not dirty for an unknown file", function()
    local r = call("check_dirty", { filePath = "/no/such/buffer/here.txt" })
    t.eq(r.isDirty, false)
  end)
end)

t.describe("handlers.save_document", function()
  t.it("writes the buffer to disk and clears the modified flag", function()
    local tmp = vim.fn.tempname()
    local buf = vim.fn.bufadd(tmp)
    vim.fn.bufload(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "saved", "content" })
    local r = call("save_document", { filePath = tmp })
    t.eq(r.saved, true)
    t.eq(vim.fn.readfile(tmp), { "saved", "content" })
    t.eq(vim.bo[buf].modified, false)
    os.remove(tmp)
  end)
end)

t.describe("handlers.close_tab", function()
  t.it("deletes the buffer for the given file", function()
    local name = vim.fn.tempname() .. "_closetab.txt"
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, name)
    t.truthy(vim.fn.bufexists(name) == 1)
    local r = call("close_tab", { filePath = name })
    t.eq(r.closed, true)
    t.eq(vim.fn.bufexists(name), 0, "buffer gone")
  end)
end)

t.describe("handlers.close_all_diff_tabs", function()
  t.it("closes every active diff and reports the count", function()
    require("pi-panel.config").setup({ diff_opts = { open_in_new_tab = false } })
    local diff = require("pi-panel.diff")
    diff.open({ filePath = vim.fn.tempname(), newContents = "a\n" }, function() end)
    diff.open({ filePath = vim.fn.tempname(), newContents = "b\n" }, function() end)
    t.is_true(diff.is_active())
    local r = call("close_all_diff_tabs", {})
    t.is_true(r.closed >= 2, "closed at least the two we opened")
    t.eq(diff.is_active(), false)
  end)
end)

t.describe("handlers.registry includes the Phase 5 tools", function()
  t.it("advertises all six new tools via initialize", function()
    local tools = handlers.registry.initialize({ protocolVersion = 1 }).supportedTools
    for _, name in ipairs({
      "get_open_editors",
      "get_diagnostics",
      "check_dirty",
      "save_document",
      "close_tab",
      "close_all_diff_tabs",
    }) do
      t.truthy(vim.tbl_contains(tools, name), name .. " advertised")
    end
  end)
end)
