---@class RPC_TestNode
---@field id string
---@field displayName string
---@field parentId string | nil
---@field filePath string | nil
---@field type "Solution" | "Project" | "Namespace" | "TestMethod" | "Subcase"

---@class TestNode
---@field id string
---@field displayName string
---@field parentId string | nil
---@field filePath string | nil
---@field type "Solution" | "Project" | "Namespace" | "TestMethod" | "Subcase"
---@field children table<string, TestNode>
---@field expanded boolean
---@field indent number

---@alias TestNodeStatus
---| "Idle"
---| "Queued"
---| "Building"
---| "Discovering"
---| "Running"
---| "Debugging"
---| "Cancelling"
---| "Passed"
---| "Failed"
---| "Skipped"
---| "Cancelled"

---@class TreeState
---@field nodesById table<string, TestNode>
---@field statusById table<string, TestNodeStatus>
---@field root TestNode | nil

local M = {
  nodes_by_id = {},
  status_by_id = {},
  root = nil,
}

local function rebuild_tree()
  if not M.root then return end

  local function set_indent_and_expand(node, indent)
    node.indent = indent or 0
    node.expanded = node.expanded == nil and true or node.expanded

    for _, child in pairs(node.children or {}) do
      set_indent_and_expand(child, indent + 1)
    end
  end

  set_indent_and_expand(M.root, 0)
end

---Add or overwrite a node in the tree
---@param node TestNode
function M.register_node(node)
  if not node.parentId then
    M.root = node
    node.children = node.children or {}
  else
    local parent = M.nodes_by_id[node.parentId]
    if not parent then error("Parent node missing: " .. node.parentId) end
    parent.children = parent.children or {}
    parent.children[node.id] = node
  end

  node.children = node.children or {}
  M.nodes_by_id[node.id] = node

  rebuild_tree()

  local render = require("easy-dotnet.test-runner.render")
  render.refresh()
end

---Update ephemeral status
---@param nodeId string
---@param status TestNodeStatus
function M.update_status(nodeId, status)
  if not M.nodes_by_id[nodeId] then error("Cannot update status of unknown node: " .. nodeId) end
  M.status_by_id[nodeId] = status
end

---Traverse the tree, sorted by displayName
---@param cb fun(node: TestNode)
---@param node TestNode | nil
function M.traverse(node, cb)
  node = node or M.root
  if not node then return end

  cb(node)

  local keys = vim.tbl_keys(node.children or {})
  table.sort(keys, function(a, b) return node.children[a].displayName < node.children[b].displayName end)

  for _, key in ipairs(keys) do
    M.traverse(node.children[key], cb)
  end
end

---Traverse the tree, sorted by displayName
---@param cb fun(node: TestNode)
---@param node TestNode | nil
function M.traverse_expanded(node, cb)
  node = node or M.root
  if not node then return end

  cb(node)

  if not node.expanded then return end

  local keys = vim.tbl_keys(node.children or {})
  table.sort(keys, function(a, b) return node.children[a].displayName < node.children[b].displayName end)

  for _, key in ipairs(keys) do
    M.traverse_expanded(node.children[key], cb)
  end
end

---Get the status for a node
---@param nodeId string
---@return TestNodeStatus | nil
function M.get_status(nodeId) return M.status_by_id[nodeId] end

---Get the tree root for rendering
---@return TestNode | nil
function M.get_render_root() return M.root end

---@return TreeState
function M.get_state()
  return {
    nodesById = M.nodes_by_id,
    statusById = M.status_by_id,
    root = M.root,
  }
end

return M
