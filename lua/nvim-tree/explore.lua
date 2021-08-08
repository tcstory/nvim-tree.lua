local uv = vim.loop
local a = vim.api

local utils = require'nvim-tree.utils'

local M = {}

local function create_directory(path, name)
  local absolute_path = utils.path_join({path, name})
  if not uv.fs_access(absolute_path, 'R') then
    return nil
  end

  return {
    name = name,
    absolute_path = absolute_path,
    children = {},
    open = false,
  }
end

local function create_file(path, name)
  local absolute_path = utils.path_join({path, name})
  local is_executable = uv.fs_access(absolute_path, 'X')
  return {
    name = name,
    absolute_path = absolute_path,
    executable = is_executable,
    extension = string.match(name, ".?[^.]+%.(.*)") or "",
  }
end

-- TODO-INFO: sometimes fs_realpath returns nil
-- I expect this to be a bug in glibc, because it fails to retrieve the path for some
-- links (for instance libr2.so in /usr/lib) and thus even with a C program realpath fails
-- when it has no real reason to. Maybe there is a reason, but errno is definitely wrong.
-- So we need to check for link_to ~= nil when adding new links to the tree
local function create_symlink(path, name)
  --- I dont know if this is needed, because in my understanding,
  -- there isnt hard links in windows, but just to be sure i changed it.
  local absolute_path = utils.path_join({path, name})
  local link_to = uv.fs_realpath(absolute_path)
  if not link_to then
    return nil
  end

  local open, children
  if uv.fs_stat(link_to).type == 'directory' then
    open = false
    children = {}
  end

  return {
    name = name,
    absolute_path = absolute_path,
    link_to = link_to,
    open = open,
    children = children,
  }
end

local function node_comparator(left, right)
  if left.children and not right.children then
    return true
  elseif not left.children and right.children then
    return false
  end

  return left.name:lower() <= right.name:lower()
end

function M.scan_folder(path)
  local handle = uv.fs_scandir(path)
  if type(handle) == 'string' then
    a.nvim_err_writeln(handle)
    return nil
  end

  local dirs = {}
  local links = {}
  local files = {}

  while true do
    local name, t = uv.fs_scandir_next(handle)
    if not name then
      break
    end

    local abs = utils.path_join({path, name})
    if not t then
      local stat = uv.fs_stat(abs)
      t = stat and stat.type
    end

    if t == 'directory' then
      local dir = create_directory(path, name)
      if dir then
        table.insert(dirs, dir)
      end
    elseif t == 'link' then
      local link = create_symlink(path, name)
      if link then
        table.insert(links, link)
      end
    elseif t == 'file' then
      table.insert(files, create_file(path, name))
    end
  end

  local nodes = dirs
  vim.list_extend(nodes, links)
  vim.list_extend(nodes, files)
  utils.merge_sort(nodes, node_comparator)

  return nodes
end

return M
