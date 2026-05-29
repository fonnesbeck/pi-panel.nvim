local t = require("support.runner")
local utils = require("pi-panel.server.utils")

t.describe("uuid_v4", function()
  t.it("matches the UUID v4 shape with correct version/variant nibbles", function()
    local id = utils.uuid_v4()
    -- 8-4-4-4-12 hex, version '4', variant one of 8/9/a/b
    t.truthy(id:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"),
      "got: " .. id)
  end)

  t.it("produces distinct values", function()
    t.ne(utils.uuid_v4(), utils.uuid_v4())
  end)
end)
