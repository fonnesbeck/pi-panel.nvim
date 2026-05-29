-- Discovery lock file at <dir>/<port>.lock (default ~/.pi/ide).
-- Written atomically; swept of dead-pid entries on startup. These names are a
-- pi-panel convention, not a pi built-in (pi reads its port/token from env vars).

local M = {}

local dir = vim.fn.expand("~/.pi/ide")

--- Override the lock directory (used by tests; default is ~/.pi/ide).
function M.set_dir(d)
  dir = d
end

function M.get_dir()
  return dir
end

function M.path(port)
  return dir .. "/" .. tostring(port) .. ".lock"
end

--- Atomically write a lock file (write to .tmp, then rename).
---@param info { port: integer, authToken: string, workspaceFolders: string[], displayName: string }
---@return string path
function M.write(info)
  vim.fn.mkdir(dir, "p")
  local data = {
    pid = vim.fn.getpid(),
    port = info.port,
    authToken = info.authToken,
    workspaceFolders = info.workspaceFolders or {},
    displayName = info.displayName,
    ideName = "Neovim",
  }
  local path = M.path(info.port)
  local tmp = path .. ".tmp"
  local f = assert(io.open(tmp, "w"))
  f:write(vim.json.encode(data))
  f:close()
  assert(os.rename(tmp, path))
  return path
end

--- Read and decode a lock file, or nil if absent/unparseable.
---@param port integer
---@return table|nil
function M.read(port)
  local f = io.open(M.path(port), "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok then
    return nil
  end
  return decoded
end

function M.remove(port)
  os.remove(M.path(port))
end

local function pid_alive(pid)
  if type(pid) ~= "number" then
    return false
  end
  -- Signal 0 probes existence without delivering a signal; 0 == alive.
  local ok, res = pcall(vim.uv.kill, pid, 0)
  return ok and res == 0
end

--- Delete lock files whose owning process is gone (or that are unparseable).
--- VimLeavePre cleanup is skipped on a hard crash, so this runs on startup.
---@return integer[] removed_ports
function M.sweep_stale()
  local removed = {}
  for _, path in ipairs(vim.fn.globpath(dir, "*.lock", false, true)) do
    local alive, port = false, nil
    local f = io.open(path, "r")
    if f then
      local content = f:read("*a")
      f:close()
      local ok, decoded = pcall(vim.json.decode, content)
      if ok and type(decoded) == "table" then
        port = decoded.port
        alive = pid_alive(decoded.pid)
      end
    end
    if not alive then
      os.remove(path)
      removed[#removed + 1] = port or tonumber(path:match("(%d+)%.lock$"))
    end
  end
  return removed
end

return M
