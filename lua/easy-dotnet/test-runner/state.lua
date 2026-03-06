---@class easy-dotnet.TestRunner.NodeStatus
---@field type string e.g. "Idle"|"Running"|"Passed"|"Failed"|"Skipped"|"Building"|"Discovering"|"Cancelled"
---@field durationDisplay? string
---@field errorMessage? string[]

---@class easy-dotnet.TestRunner.Node
---@field id string
---@field displayName string
---@field parentId string|nil
---@field filePath string|nil
---@field signatureLine integer|nil
---@field bodyStartLine integer|nil
---@field endLine integer|nil
---@field type table  e.g. { Type = "TestMethod" }
---@field projectId string|nil
---@field availableActions string[]
---@field targetFramework string|nil
---@field status easy-dotnet.TestRunner.NodeStatus|nil  last received updateStatus
---@field expanded boolean  pure UI state — never sent to server

---@class easy-dotnet.TestRunner.RunnerStatus
---@field isLoading boolean
---@field currentOperation string|nil
---@field overallStatus string
---@field totalPassed integer
---@field totalFailed integer
---@field totalSkipped integer
---@field totalCancelled integer

local M = {}

-- id → TestNode
---@type table<string, easy-dotnet.TestRunner.Node>
M.nodes = {}
M.quick_discover_started = false

-- Top-level runner status from testrunner/statusUpdate
---@type easy-dotnet.TestRunner.RunnerStatus
M.runner_status = {
  isLoading = false,
  currentOperation = nil,
  overallStatus = "Idle",
  totalPassed = 0,
  totalFailed = 0,
  totalSkipped = 0,
  totalCancelled = 0,
}

M.root_id = nil

M.active_handle = nil

--- Upsert a node. Preserves local UI state (expanded) if the node already exists.
---@param node easy-dotnet.TestRunner.Node
function M.register(node)
  local existing = M.nodes[node.id]
  local node_type = node.type and node.type.type or ""

  if existing then
    node.expanded = existing.expanded
  else
    node.expanded = node_type == "Solution" or node_type == "Project"
  end

  node.status = existing and existing.status or nil
  M.nodes[node.id] = node
  if node.parentId == nil then M.root_id = node.id end
end

--- Update cached status for a node. nil status = reset to idle.
---@param id string
---@param status easy-dotnet.TestRunner.NodeStatus|nil
---@param available_actions string[]|nil
function M.update_status(id, status, available_actions)
  local node = M.nodes[id]
  if not node then return end
  node.status = status
  if available_actions then node.availableActions = available_actions end
end

--- Update global runner status.
---@param status easy-dotnet.TestRunner.RunnerStatus
function M.update_runner_status(status)
  M.runner_status = status
  if not status.isLoading then M.active_handle = nil end
end

function M.cancel()
  if not M.active_handle then return end
  M.active_handle.cancel()
  M.runner_status = vim.tbl_extend("force", M.runner_status, {
    isLoading = true,
    currentOperation = "Cancelling",
  })
  M.active_handle = nil
end

function M.update_line_numbers(update)
  local node = M.nodes[update.id]
  if not node then return end
  node.signatureLine = update.signatureLine
  node.bodyStartLine = update.bodyStartLine
  node.endLine = update.endLine
end

--- Returns direct children of a node, sorted by displayName.
---@param parent_id string
---@return easy-dotnet.TestRunner.Node[]
function M.children(parent_id)
  local result = {}
  for _, node in pairs(M.nodes) do
    if node.parentId == parent_id then table.insert(result, node) end
  end
  table.sort(result, function(a, b) return a.displayName < b.displayName end)
  return result
end

--- Wipe all state. Called before a fresh initialize.
function M.clear()
  M.nodes = {}
  M.root_id = nil
  M.runner_status = {
    isLoading = false,
    currentOperation = nil,
    overallStatus = "Idle",
    totalPassed = 0,
    totalFailed = 0,
    totalSkipped = 0,
    totalCancelled = 0,
  }
end

--- Walk all visible (expanded) nodes in display order, calling cb(node, depth).
---@param cb fun(node: easy-dotnet.TestRunner.Node, depth: integer)
function M.traverse_visible(cb)
  if not M.root_id then return end

  local function walk(id, depth)
    local node = M.nodes[id]
    if not node then return end
    cb(node, depth)
    if node.expanded then
      for _, child in ipairs(M.children(id)) do
        walk(child.id, depth + 1)
      end
    end
  end

  walk(M.root_id, 0)
end

--- Walk ALL nodes in tree order regardless of expansion, calling cb(node, depth).
---@param cb fun(node: easy-dotnet.TestRunner.Node, depth: integer)
function M.traverse_all(cb)
  if not M.root_id then return end

  local function walk(id, depth)
    local node = M.nodes[id]
    if not node then return end
    cb(node, depth)
    for _, child in ipairs(M.children(id)) do
      walk(child.id, depth + 1)
    end
  end

  walk(M.root_id, 0)
end

--- Returns true if the node has the given action available.
---@param node easy-dotnet.TestRunner.Node
---@param action string
---@return boolean
function M.has_action(node, action)
  if not node.availableActions then return false end
  for _, a in ipairs(node.availableActions) do
    if a == action then return true end
  end
  return false
end

return M
