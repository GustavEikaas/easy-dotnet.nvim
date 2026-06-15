---@class easy-dotnet.TestRunner.NodeStatus
---@field type string e.g. "Idle"|"Queued"|"Running"|"Debugging"|"Passed"|"Failed"|"Faulted"|"Skipped"|"Inconclusive"|"Building"|"Discovering"|"BuildFailed"|"Cancelling"|"Cancelled"
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
---@field totalTests integer
---@field totalRunning integer
---@field totalPassed integer
---@field totalFailed integer
---@field totalSkipped integer
---@field totalCancelled integer
---@field totalInconclusive integer

local M = {}

-- id → TestNode
---@type table<string, easy-dotnet.TestRunner.Node>
M.nodes = {}

---@type easy-dotnet.TestRunner.RunnerStatus
M.runner_status = {
  isLoading = false,
  currentOperation = nil,
  overallStatus = "Idle",
  totalTests = 0,
  totalRunning = 0,
  totalPassed = 0,
  totalFailed = 0,
  totalSkipped = 0,
  totalCancelled = 0,
  totalInconclusive = 0,
}

M.root_id = nil
M.initialized = false
M.active_handle = nil

-- Statuses treated as failures for ]f / [f jump-to-failure navigation.
local FAILURE_STATUSES = {
  Failed = true,
  Faulted = true,
  BuildFailed = true,
}

--- Upsert a node. Preserves local UI state (expanded) if the node already exists.
---@param node easy-dotnet.TestRunner.Node
function M.register(node)
  local existing = M.nodes[node.id]
  local node_type = node.type and node.type.type or ""

  if existing then
    node.expanded = existing.expanded
  else
    node.expanded = node_type == "Solution"
  end

  node.status = existing and existing.status or nil
  M.nodes[node.id] = node
  if node.parentId == nil then M.root_id = node.id end
end

--- Remove a node from the state.
---@param id string
function M.remove(id) M.nodes[id] = nil end

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

function M.clear()
  M.nodes = {}
  M.root_id = nil
  M.initialized = false
  M.runner_status = {
    isLoading = false,
    currentOperation = nil,
    overallStatus = "Idle",
    totalTests = 0,
    totalRunning = 0,
    totalPassed = 0,
    totalFailed = 0,
    totalSkipped = 0,
    totalCancelled = 0,
    totalInconclusive = 0,
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

--- Find the next/previous failing leaf test relative to from_id, in full tree
--- order, wrapping around. A "leaf" failure is a failed node with no failed child,
--- so containers on the failure path (project/class/namespace) are skipped and you
--- land on the actual failing test. Returns nil when there are no failures.
---@param from_id string|nil  node to search from (usually the node under the cursor)
---@param direction 1|-1      1 = next (]f), -1 = previous ([f)
---@return string|nil
function M.failure_jump_target(from_id, direction)
  local order = {}
  local failed = {}
  local has_failed_child = {}
  M.traverse_all(function(node)
    order[#order + 1] = node.id
    if node.status ~= nil and FAILURE_STATUSES[node.status.type] == true then
      failed[node.id] = true
      if node.parentId then has_failed_child[node.parentId] = true end
    end
  end)

  local n = #order
  if n == 0 then return nil end

  local is_target = {}
  local has_target = false
  for id in pairs(failed) do
    if not has_failed_child[id] then
      is_target[id] = true
      has_target = true
    end
  end
  if not has_target then return nil end

  local from = 0
  for i, id in ipairs(order) do
    if id == from_id then
      from = i
      break
    end
  end

  for step = 1, n do
    local idx = (from - 1 + direction * step) % n + 1
    if is_target[order[idx]] then return order[idx] end
  end
  return nil
end

return M
