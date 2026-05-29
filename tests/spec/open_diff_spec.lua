local t = require("support.runner")
local handlers = require("pi-panel.handlers")
local diff = require("pi-panel.diff")
local config = require("pi-panel.config")

local function open(req_id, params)
  local captured
  handlers.registry.open_diff(
    vim.tbl_extend("force", { _requestId = req_id }, params),
    function(r)
      captured = r
    end
  )
  -- the handler schedules the diff open; wait for it to appear
  vim.wait(500, function()
    return diff.is_active()
  end)
  return function()
    return captured
  end
end

t.describe("handlers.open_diff", function()
  t.it("is registered and advertised by initialize", function()
    t.truthy(handlers.registry.open_diff)
    t.truthy(handlers.registry.cancel)
    t.truthy(vim.tbl_contains(handlers.registry.initialize({ protocolVersion = 1 }).supportedTools, "open_diff"))
  end)

  t.it("blocks until accept, then responds FILE_SAVED and writes the file", function()
    config.setup({ diff_opts = { open_in_new_tab = false, timeout = 300 } })
    local tmp = vim.fn.tempname()
    local get = open("r-accept", { filePath = tmp, newContents = "hello\n" })
    t.is_nil(get(), "no response before the user acts")
    diff.accept_current()
    vim.wait(500, function()
      return get() ~= nil
    end)
    t.eq(get().content[1].text, "FILE_SAVED")
    t.eq(vim.fn.readfile(tmp), { "hello" })
    os.remove(tmp)
  end)

  t.it("responds DIFF_REJECTED on reject", function()
    config.setup({ diff_opts = { open_in_new_tab = false, timeout = 300 } })
    local get = open("r-reject", { filePath = vim.fn.tempname(), newContents = "x\n" })
    diff.reject_current()
    vim.wait(500, function()
      return get() ~= nil
    end)
    t.eq(get().content[1].text, "DIFF_REJECTED")
  end)

  t.it("a cancel notification for the request closes the diff and errors", function()
    config.setup({ diff_opts = { open_in_new_tab = false, timeout = 300 } })
    local get = open("r-cancel", { filePath = vim.fn.tempname(), newContents = "x\n" })
    handlers.registry.cancel({ id = "r-cancel" })
    vim.wait(500, function()
      return get() ~= nil
    end)
    t.truthy(get().error, "errored")
    t.eq(diff.is_active(), false, "diff torn down on cancel")
  end)

  t.it("auto-rejects with an error after the configured timeout", function()
    config.setup({ diff_opts = { open_in_new_tab = false, timeout = 0.05 } }) -- 50ms
    local get = open("r-timeout", { filePath = vim.fn.tempname(), newContents = "x\n" })
    vim.wait(1000, function()
      return get() ~= nil
    end)
    t.truthy(get().error, "errored on timeout")
    t.truthy(get().error.message:lower():find("timeout"), "message mentions timeout")
    config.setup({ diff_opts = { timeout = 300 } }) -- restore
  end)
end)
