---@class TestNode
---@field id string
---@field displayName string
---@field parentId string | nil
---@field filePath string | nil
---@field type "Solution" | "Project" | "Namespace" | "TestMethod" | "Subcase" | "TestGroup"
---@field children table<string, TestNode>
---@field expanded boolean
---@field indent number

---@alias TestNodeStatus
---| "Idle" | "Queued" | "Building" | "Discovering" | "Running" | "Debugging"
---| "Cancelling" | "Passed" | "Failed" | "Skipped" | "Cancelled"

local M = {
  nodes_by_id = {},
  status_by_id = {},
  roots = {}, -- Support multiple roots (e.g. multiple projects/solutions)
}

-- --- HELPERS ---

---Returns children sorted by Type Priority then Alphabetically
---@param node TestNode
---@return TestNode[]
local function get_sorted_children(node)
  if not node.children then return {} end

  local children = {}
  for _, child in pairs(node.children) do
    table.insert(children, child)
  end

  table.sort(children, function(a, b)
    -- 1. Sort by Type Priority
    local priority = { Solution = 1, Project = 2, Namespace = 3, TestGroup = 4, TestMethod = 5, Subcase = 6 }
    local pA = priority[a.type] or 99
    local pB = priority[b.type] or 99

    if pA ~= pB then return pA < pB end

    -- 2. Sort Alphabetically
    return a.displayName < b.displayName
  end)

  return children
end

-- --- WRITE OPERATIONS ---

---Add or overwrite a node in the tree
---@param node_dto table Raw DTO from server
function M.register_node(node_dto)
  local id = node_dto.id
  local existing = M.nodes_by_id[id]

  if existing then
    -- Update existing: Merge fields but PRESERVE state (expanded, children)
    existing.displayName = node_dto.displayName
    existing.type = node_dto.type or existing.type
    existing.filePath = node_dto.filePath or existing.filePath
    existing.parentId = node_dto.parentId or existing.parentId
    -- Do NOT touch existing.expanded or existing.children here
  else
    -- Create new node
    local new_node = {
      id = id,
      displayName = node_dto.displayName,
      parentId = node_dto.parentId,
      filePath = node_dto.filePath,
      type = node_dto.type,
      children = {},
      indent = 0,
      -- BUG FIX: Default expanded to FALSE unless it is a Solution/Root
      expanded = (node_dto.type == "Solution"),
    }

    M.nodes_by_id[id] = new_node

    -- Link to Parent
    if new_node.parentId then
      local parent = M.nodes_by_id[new_node.parentId]
      if parent then
        parent.children[id] = new_node
      else
        -- Parent not found yet? (Async discovery issue).
        -- For now, we can log or ignore. It will be linked when/if parent arrives?
        -- Actually, safer to assume parents arrive first or handled by re-parenting events.
        -- We will treat it as a temporary root for safety if needed, or just wait.
      end
    else
      M.roots[id] = new_node
    end
  end

  -- Trigger refresh
  -- (Optional: Debounce this in the Render module to avoid flickering)
  local render = require("easy-dotnet.test-runner.render")
  if render.refresh then render.refresh() end
end

---Change the parent of a node
---@param nodeId string
---@param newParentId string
function M.change_parent(nodeId, newParentId)
  local node = M.nodes_by_id[nodeId]
  if not node then return end

  -- 1. Unlink from old parent
  if node.parentId then
    local oldParent = M.nodes_by_id[node.parentId]
    if oldParent and oldParent.children then oldParent.children[nodeId] = nil end
  end

  -- Remove from roots if it was a root
  M.roots[nodeId] = nil

  -- 2. Link to new parent
  local newParent = M.nodes_by_id[newParentId]
  if newParent then
    newParent.children = newParent.children or {}
    newParent.children[nodeId] = node
    node.parentId = newParentId
  else
    -- Fallback: If new parent doesn't exist, make it a root?
    -- This shouldn't happen with correct server logic.
    M.roots[nodeId] = node
    node.parentId = nil
  end

  local render = require("easy-dotnet.test-runner.render")
  if render.refresh then render.refresh() end
end

---Remove a node
---@param nodeId string
function M.remove_node(nodeId)
  local node = M.nodes_by_id[nodeId]
  if not node then return end

  -- Unlink from parent
  if node.parentId then
    local parent = M.nodes_by_id[node.parentId]
    if parent then parent.children[nodeId] = nil end
  end

  -- Unlink from roots
  M.roots[nodeId] = nil
  M.nodes_by_id[nodeId] = nil
  M.status_by_id[nodeId] = nil

  local render = require("easy-dotnet.test-runner.render")
  if render.refresh then render.refresh() end
end

---Update ephemeral status
---@param nodeId string
---@param status TestNodeStatus
function M.update_status(nodeId, status)
  if M.nodes_by_id[nodeId] then M.status_by_id[nodeId] = status end
end

function M.set_expanded(nodeId, isExpanded)
  local node = M.nodes_by_id[nodeId]
  if node then node.expanded = isExpanded end
end

-- --- TRAVERSAL ---

---Traverse the tree (Visual Order: Sorted, Expanded Only)
---@param start_node TestNode | nil
---@param cb fun(node: TestNode)
function M.traverse_expanded(start_node, cb)
  local function visit(node, indent)
    node.indent = indent
    cb(node)

    if node.expanded then
      local children = get_sorted_children(node)
      for _, child in ipairs(children) do
        visit(child, indent + 1)
      end
    end
  end

  if start_node then
    visit(start_node, start_node.indent or 0)
  else
    -- Visit all roots sorted
    local sorted_roots = {}
    for _, r in pairs(M.roots) do
      table.insert(sorted_roots, r)
    end
    table.sort(sorted_roots, function(a, b) return a.displayName < b.displayName end)

    for _, root in ipairs(sorted_roots) do
      visit(root, 0)
    end
  end
end

---Get status map
function M.get_status_map() return M.status_by_id end

return M
