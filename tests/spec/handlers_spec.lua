local t = require("support.runner")
local handlers = require("pi-panel.handlers")

-- Handlers schedule their vim work and respond asynchronously; this drives the
-- event loop until the response callback fires (or a short timeout elapses).
local function call(method, params)
  local registry = handlers.registry
  assert(registry[method], "no handler registered for " .. method)
  local captured
  registry[method](params or {}, function(result)
    captured = result
  end)
  vim.wait(500, function()
    return captured ~= nil
  end)
  return captured
end

t.describe("handlers.registry wiring", function()
  t.it("exposes the Phase 3 tools and initialize lists them", function()
    t.truthy(handlers.registry.open_file, "open_file registered")
    t.truthy(handlers.registry.get_selection, "get_selection registered")
    t.truthy(handlers.registry.get_workspace_folders, "get_workspace_folders registered")

    local init = handlers.registry.initialize({ protocolVersion = 1 })
    t.truthy(vim.tbl_contains(init.supportedTools, "open_file"))
    t.truthy(vim.tbl_contains(init.supportedTools, "get_selection"))
    t.truthy(vim.tbl_contains(init.supportedTools, "get_workspace_folders"))
  end)
end)

t.describe("handlers.open_file", function()
  t.it("edits the file and positions the cursor at startLine", function()
    local tmp = vim.fn.tempname()
    vim.fn.writefile({ "line one", "line two", "line three" }, tmp)

    local result = call("open_file", { filePath = tmp, startLine = 2 })

    t.eq(vim.api.nvim_buf_get_name(0), vim.fn.fnamemodify(tmp, ":p"), "file is the current buffer")
    t.eq(vim.api.nvim_win_get_cursor(0)[1], 2, "cursor on startLine")
    t.eq(result.filePath, vim.fn.fnamemodify(tmp, ":p"))
    t.truthy(result.message:find("Opened", 1, true), "message confirms open")
    os.remove(tmp)
  end)
end)

t.describe("handlers.get_selection", function()
  t.it("returns the charwise visual selection of the current buffer", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello world", "second line" })
    vim.api.nvim_set_current_buf(buf)
    -- select "world" (line 1, cols 7..11, 1-indexed inclusive)
    vim.fn.setpos("'<", { buf, 1, 7, 0 })
    vim.fn.setpos("'>", { buf, 1, 11, 0 })

    local result = call("get_selection", {})

    t.eq(result.isEmpty, false)
    t.eq(result.text, "world")
    t.eq(result.selection.start.line, 1, "1-indexed start line")
    t.eq(result.selection.start.character, 7, "1-indexed start col")
  end)

  t.it("reports an empty selection when start and end marks coincide", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abc" })
    vim.api.nvim_set_current_buf(buf)
    vim.fn.setpos("'<", { buf, 0, 0, 0 })
    vim.fn.setpos("'>", { buf, 0, 0, 0 })

    local result = call("get_selection", {})
    t.eq(result.isEmpty, true)
    t.eq(result.text, "")
  end)
end)

t.describe("handlers.get_workspace_folders", function()
  t.it("returns the current working directory as a workspace folder", function()
    local result = call("get_workspace_folders", {})
    t.truthy(vim.tbl_contains(result.folders, vim.fn.getcwd()), "cwd is a folder")
  end)
end)
