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

-- parent id → set of child ids
---@type table<string, table<string, true>>
local children_index = {}
-- parent id → children sorted by displayName, built lazily by M.children
---@type table<string, easy-dotnet.TestRunner.Node[]>
local sorted_children = {}
-- normalized file path → set of node ids
---@type table<string, table<string, true>>
local file_index = {}
-- normalized file path → nodes sorted by id, built lazily by M.nodes_in_file
---@type table<string, easy-dotnet.TestRunner.Node[]>
local sorted_file_nodes = {}
-- raw path → normalized path with symlinks resolved
---@type table<string, string>
local normalized_paths = {}

-- Statuses treated as failures for ]f / [f jump-to-failure navigation.
local FAILURE_STATUSES = {
  Failed = true,
  Faulted = true,
  BuildFailed = true,
}

--- Memoized canonical path (normalized, symlinks resolved); thousands of nodes share a handful of file paths.
---@param path string|nil
---@return string|nil
function M.normalize_path(path)
  if not path then return nil end
  local normalized = normalized_paths[path]
  if not normalized then
    normalized = vim.fs.normalize(vim.fn.resolve(vim.fs.normalize(path)))
    normalized_paths[path] = normalized
  end
  return normalized
end

---@param node easy-dotnet.TestRunner.Node
local function index_node(node)
  if node.parentId then
    local siblings = children_index[node.parentId]
    if not siblings then
      siblings = {}
      children_index[node.parentId] = siblings
    end
    siblings[node.id] = true
    sorted_children[node.parentId] = nil
  end
  if node.filePath then
    local path = M.normalize_path(node.filePath)
    local file_nodes = file_index[path]
    if not file_nodes then
      file_nodes = {}
      file_index[path] = file_nodes
    end
    file_nodes[node.id] = true
    sorted_file_nodes[path] = nil
  end
end

---@param node easy-dotnet.TestRunner.Node
local function unindex_node(node)
  if node.parentId then
    local siblings = children_index[node.parentId]
    if siblings then siblings[node.id] = nil end
    sorted_children[node.parentId] = nil
  end
  if node.filePath then
    local path = M.normalize_path(node.filePath)
    local file_nodes = file_index[path]
    if file_nodes then file_nodes[node.id] = nil end
    sorted_file_nodes[path] = nil
  end
end

--- Upsert a node. Preserves local UI state (expanded) if the node already exists.
---@param node easy-dotnet.TestRunner.Node
function M.register(node)
  local existing = M.nodes[node.id]
  local node_type = node.type and node.type.type or ""

  if existing then
    node.expanded = existing.expanded
    unindex_node(existing)
  else
    node.expanded = node_type == "Solution"
  end

  node.status = existing and existing.status or nil
  M.nodes[node.id] = node
  index_node(node)
  if node.parentId == nil then M.root_id = node.id end
end

--- Remove a node and all of its descendants from the state.
---@param id string
function M.remove(id)
  local stack = { id }
  while #stack > 0 do
    local current = table.remove(stack)
    local node = M.nodes[current]
    if node then
      unindex_node(node)
      M.nodes[current] = nil
      for child_id in pairs(children_index[current] or {}) do
        table.insert(stack, child_id)
      end
      children_index[current] = nil
      sorted_children[current] = nil
    end
  end
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

function M.update_line_numbers(update)
  local node = M.nodes[update.id]
  if not node then return end
  node.signatureLine = update.signatureLine
  node.bodyStartLine = update.bodyStartLine
  node.endLine = update.endLine
end

--- Returns direct children of a node, sorted by displayName.
--- The returned list is cached until the children change; do not mutate it.
---@param parent_id string
---@return easy-dotnet.TestRunner.Node[]
function M.children(parent_id)
  local cached = sorted_children[parent_id]
  if cached then return cached end

  local result = {}
  for id in pairs(children_index[parent_id] or {}) do
    local node = M.nodes[id]
    if node then table.insert(result, node) end
  end
  table.sort(result, function(a, b)
    if a.displayName ~= b.displayName then return a.displayName < b.displayName end
    return a.id < b.id
  end)
  sorted_children[parent_id] = result
  return result
end

--- Returns every node whose filePath matches the given path, ordered by id.
--- The returned list is cached until the file's nodes change; do not mutate it.
---@param path string
---@return easy-dotnet.TestRunner.Node[]
function M.nodes_in_file(path)
  local normalized = M.normalize_path(path)
  local cached = sorted_file_nodes[normalized]
  if cached then return cached end

  local result = {}
  for id in pairs(file_index[normalized] or {}) do
    local node = M.nodes[id]
    if node then table.insert(result, node) end
  end
  table.sort(result, function(a, b) return a.id < b.id end)
  sorted_file_nodes[normalized] = result
  return result
end

---@param path string
---@return boolean
function M.has_nodes_in_file(path) return next(file_index[M.normalize_path(path)] or {}) ~= nil end

function M.clear()
  M.nodes = {}
  children_index = {}
  sorted_children = {}
  file_index = {}
  sorted_file_nodes = {}
  normalized_paths = {}
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
