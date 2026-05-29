-- Best-effort file-tree integration: resolve the path of the node under the
-- cursor in a supported tree (nvim-tree / oil / neo-tree). Used by :PiAdd when
-- invoked from a tree buffer with no explicit argument. Returns nil if the
-- current buffer isn't a recognised tree or the plugin isn't installed.

local M = {}

---@return string|nil path
function M.current_path()
  local ft = vim.bo.filetype

  if ft == "NvimTree" then
    local ok, api = pcall(require, "nvim-tree.api")
    if ok then
      local node = api.tree.get_node_under_cursor()
      if node and node.absolute_path then
        return node.absolute_path
      end
    end
  elseif ft == "oil" then
    local ok, oil = pcall(require, "oil")
    if ok then
      local entry = oil.get_cursor_entry()
      local dir = oil.get_current_dir()
      if entry and dir then
        return dir .. entry.name
      end
    end
  elseif ft == "neo-tree" then
    local ok, manager = pcall(require, "neo-tree.sources.manager")
    if ok then
      local state = manager.get_state("filesystem")
      local node = state and state.tree and state.tree:get_node()
      if node and node.path then
        return node.path
      end
    end
  end

  return nil
end

return M
