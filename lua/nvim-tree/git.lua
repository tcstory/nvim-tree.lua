local utils = require'nvim-tree.utils'
local M = {}

local roots = {}

-- A map from git roots to a list of ignored paths
local gitignore_map = {}

local not_git = 'not a git repo'
local is_win32 = vim.fn.has('win32') == 1

local running_jobs = {}

local function update_root_status_second_callback(root)
  return function(_, data)
    local statuses = type(data[1]) == 'table' and data[1] or data

    roots[root] = {}
    gitignore_map[root] = {}

    for _, v in pairs(statuses) do
      if v ~= "" then
        local head = v:sub(0, 2)
        local body = v:sub(4, -1)
        -- probably useless check
        if body:match('%->') ~= nil then
          body = body:gsub('^.* %-> ', '')
        end

        --- Git returns paths with a forward slash wherever you run it, thats why i have to replace it only on windows
        if is_win32 then
          body = body:gsub("/", "\\")
        end

        roots[root][body] = head

        if head == "!!" then
          gitignore_map[root][utils.path_remove_trailing(utils.path_join({root, body}))] = true
        end
      end
    end
    running_jobs[root] = false
  end
end

local function update_root_status_callback(root)
  return function(_, data)
    local job = { 'git', 'status', '--porcelain=v1', '--ignored=matching' }
    if vim.trim(data[1]) ~= 'false' then
      table.insert(job, '-u')
    end

    vim.fn.jobstart(job, {
      stdin = nil,
      detach = true,
      cwd = root,
      stdout_buffered = true,
      on_stdout = update_root_status_second_callback(root)
    })
  end
end

local function update_root_status(root)
  if running_jobs[root] then
    return
  end
  running_jobs[root] = true
  local job = { 'git', 'config', '--type=bool', 'status.showUntrackedFiles' }
  vim.fn.jobstart(job, {
    stdin = nil,
    detach = true,
    cwd = root,
    stdout_buffered = true,
    on_stdout = update_root_status_callback(root), 
  })
end

function M.reload_roots()
  for root, status in pairs(roots) do
    if status ~= not_git then
      update_root_status(root)
    end
  end
end

local function get_git_root(path)
  if roots[path] then
    return path, roots[path]
  end

  for name, status in pairs(roots) do
    if status ~= not_git then
      if path:match(utils.path_to_matching_str(name)) then
        return name, status
      end
    end
  end
end

local function execute_create_root_callback(cwd, callback)
  return function(_, data)
    local git_root = data[1]

    if not git_root or #git_root == 0 or git_root:match('fatal') then
      roots[cwd] = not_git
      callback(false)
      return
    end

    if is_win32 then
      git_root = git_root:gsub("/", "\\")
    end

    update_root_status(git_root:sub(0, -1))
    callback(true)
  end
end

local function create_root(cwd, callback)
  current_job = vim.loop.hrtime()
  vim.fn.jobstart({
    'git',
    'rev-parse',
    '--show-toplevel'
  }, {
    stdin = nil,
    detach = true,
    cwd = cwd,
    on_stdout = execute_create_root_callback(cwd, callback),
    stdout_buffered = true,
  })
end

local function git_update_callback(git_root, git_status, entries, cwd, parent_node, with_redraw)
  if not parent_node then parent_node = {} end

  local matching_cwd = utils.path_to_matching_str( utils.path_add_trailing(git_root) )

  for _, node in pairs(entries) do
    if parent_node.git_status == "!!" then
      node.git_status = "!!"
    else
      local relpath = node.absolute_path:gsub(matching_cwd, '')
      if node.entries ~= nil then
        relpath = utils.path_add_trailing(relpath)
        node.git_status = nil
      end

      local status = git_status[relpath]
      if status then
        node.git_status = status
      elseif node.entries ~= nil then
        local matcher = '^'..utils.path_to_matching_str(relpath)
        for key, entry_status in pairs(git_status) do
          if entry_status ~= "!!" and key:match(matcher) then
            node.git_status = entry_status
            break
          end
        end
      else
        node.git_status = nil
      end
    end
  end
  if with_redraw then
    require'nvim-tree.lib'.redraw()
  end
end

function M.update_status(entries, cwd, parent_node, with_redraw, callback)
  local git_root, git_status = get_git_root(cwd)
  if not git_root then
    create_root(cwd, function(ret)
      if not ret then return end

      git_root, git_status = get_git_root(cwd)
      if not git_root then return end

      git_update_callback(git_root, git_status, entries, cwd, parent_node, with_redraw)
      callback()
    end)
  elseif git_status ~= not_git then
    git_update_callback(git_root, git_status, entries, cwd, parent_node, with_redraw)
    callback()
  end
end

---Check if the given path is ignored by git.
---@param path string Absolute path
---@return boolean
function M.should_gitignore(path)
  for _, paths in pairs(gitignore_map) do
    if paths[path] == true then
      return true
    end
  end
  return false
end

return M
