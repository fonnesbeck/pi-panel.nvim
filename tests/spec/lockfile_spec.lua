local t = require("support.runner")
local lockfile = require("pi-panel.lockfile")

-- Each test gets a fresh temp lock directory so we never touch real ~/.pi/ide.
local function fresh_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  lockfile.set_dir(dir)
  return dir
end

local function file_exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

t.describe("lockfile.write", function()
  t.it("writes a lock at <dir>/<port>.lock with the expected fields", function()
    fresh_dir()
    local path = lockfile.write({
      port = 12345,
      authToken = "tok-abc",
      workspaceFolders = { "/home/me/project" },
      displayName = "project",
    })
    t.eq(path, lockfile.path(12345))
    t.is_true(file_exists(path))

    local data = lockfile.read(12345)
    t.eq(data.port, 12345)
    t.eq(data.authToken, "tok-abc")
    t.eq(data.workspaceFolders, { "/home/me/project" })
    t.eq(data.displayName, "project")
    t.eq(data.ideName, "Neovim")
    t.eq(data.pid, vim.fn.getpid())
  end)

  t.it("leaves no .tmp file behind (atomic rename)", function()
    local dir = fresh_dir()
    lockfile.write({ port = 222, authToken = "x", workspaceFolders = {}, displayName = "d" })
    local leftovers = vim.fn.globpath(dir, "*.tmp", false, true)
    t.eq(#leftovers, 0)
  end)
end)

t.describe("lockfile.remove", function()
  t.it("deletes the lock file", function()
    fresh_dir()
    lockfile.write({ port = 333, authToken = "x", workspaceFolders = {}, displayName = "d" })
    t.is_true(file_exists(lockfile.path(333)))
    lockfile.remove(333)
    t.eq(file_exists(lockfile.path(333)), false)
  end)
end)

t.describe("lockfile.sweep_stale", function()
  t.it("removes locks whose pid is dead but keeps live ones", function()
    fresh_dir()
    -- live: our own pid
    lockfile.write({ port = 1001, authToken = "a", workspaceFolders = {}, displayName = "live" })
    -- stale: a pid that is not running
    lockfile.write({ port = 1002, authToken = "b", workspaceFolders = {}, displayName = "dead" })
    -- rewrite 1002's pid to a dead one
    local dead_path = lockfile.path(1002)
    local f = assert(io.open(dead_path, "w"))
    f:write(vim.json.encode({ pid = 2147483646, port = 1002, authToken = "b" }))
    f:close()

    local removed = lockfile.sweep_stale()

    t.is_true(file_exists(lockfile.path(1001)), "live lock kept")
    t.eq(file_exists(lockfile.path(1002)), false, "dead lock removed")
    t.truthy(vim.tbl_contains(removed, 1002), "reports removed port")
  end)

  t.it("removes a malformed lock file", function()
    local dir = fresh_dir()
    local bad = dir .. "/9.lock"
    local f = assert(io.open(bad, "w"))
    f:write("not json{{")
    f:close()
    lockfile.sweep_stale()
    t.eq(file_exists(bad), false)
  end)
end)
