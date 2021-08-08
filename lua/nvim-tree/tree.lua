local uv = vim.loop

local utils = require'nvim-tree.utils'
local explorer = require'nvim-tree.explore'
-- v1 refacto: MUST:
-- handle refresh event
-- filter nodes ? TODO: find a proper way to manage ignore
--
-- expose tools to explore the tree
--
-- v2: MUST:
-- see if it's possible to load a watcher for each node with children
-- to remove dependency on bufwritepost and git change event

local M = {}

local Tree = {}
Tree.__index = Tree

function Tree.new(opts)
  local cwd = uv.cwd()
  return setmetatable({
    cwd = cwd,
    children = explorer.scan_folder(cwd),
    group_empty = opts.group_empty or true,
  }, Tree)
end

function Tree:get_current_node(idx)
  return utils.find_node(
    self.children,
    function(_, i)
      return i == idx
    end
  )
end

local function should_group(nodes)
  return #nodes == 1 and nodes[1].children ~= nil
end

local function should_populate(node)
  return node.open and #node.children == 0
end

function Tree:collapse(node)
  node.open = not node.open

  if should_populate(node) then
    local cwd = node.link_to or node.absolute_path
    node.children = explorer.scan_folder(cwd, node)
    if self.group_empty and should_group(node.children) then
      self:collapse(node.children[1])
    end
  end
end

M.Tree = Tree

return M
