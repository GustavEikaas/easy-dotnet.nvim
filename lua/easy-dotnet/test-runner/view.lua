local M = {}

local function get_recursive_test_count(node)
  local count = 0
  if not node.children then return 0 end

  for _, child in pairs(node.children) do
    if child.type == "TestMethod" or child.type == "Subcase" then
      count = count + 1
    else
      count = count + get_recursive_test_count(child)
    end
  end
  return count
end

---@param icon_config table
---@param node_type string
local function get_node_icon(icon_config, node_type)
  if node_type == "Solution" then return icon_config.sln end
  if node_type == "Project" then return icon_config.project end
  if node_type == "Namespace" then return icon_config.dir end
  if node_type == "TestMethod" or node_type == "Subcase" then return icon_config.test end
  return icon_config.test
end

local function get_node_highlight(node_type)
  if node_type == "Solution" then return "EasyDotnetTestRunnerSolution" end
  if node_type == "Project" then return "EasyDotnetTestRunnerProject" end
  if node_type == "Namespace" then return "EasyDotnetTestRunnerDir" end
  if node_type == "TestGroup" then return "EasyDotnetTestRunnerDir" end
  if node_type == "TestMethod" then return "EasyDotnetTestRunnerTest" end
  if node_type == "Subcase" then return "EasyDotnetTestRunnerSubcase" end
  return "EasyDotnetTestRunnerTest"
end

---@param icon_config table
---@param status table
local function get_status_icon(icon_config, status)
  if status == nil then return nil, nil end
  if status.type == "Passed" then return icon_config.passed, "EasyDotnetTestRunnerPassed" end
  if status.type == "Failed" then return icon_config.failed, "EasyDotnetTestRunnerFailed" end
  if status.type == "Skipped" then return icon_config.skipped, "Comment" end
  if status.type == "Running" or status.type == "Building" then return icon_config.reload, "EasyDotnetTestRunnerRunning" end
  return nil, nil
end

---@param node TestNode
local function format_line(node, status)
  local icons = require("easy-dotnet.options").get_option("test_runner").icons or {}
  local indent = string.rep("  ", node.indent or 0)

  -- 1. Try to get Status Icon & Color (e.g. Green Checkmark)
  local icon_char, hl_group = get_status_icon(icons, status)

  -- 2. Fallbacks
  if not icon_char then icon_char = get_node_icon(icons, node.type) end

  -- If no status color (Idle), use the Structural Color (Project/Solution/Test)
  if not hl_group then hl_group = get_node_highlight(node.type) end

  -- 3. Build Suffix (Duration + Child Count)
  local suffix = ""

  -- A: Duration
  if status and status.durationDisplay then suffix = suffix .. " " .. status.durationDisplay end

  -- B: Child Count (Only for containers)
  if node.type == "Solution" or node.type == "Project" or node.type == "Namespace" or node.type == "TestGroup" then
    local count = get_recursive_test_count(node)
    if count > 0 then suffix = suffix .. string.format(" (%d)", count) end
  end

  -- 4. Format Line
  local line = string.format("%s%s %s%s", indent, icon_char, node.displayName, suffix)

  return line, hl_group
end

---Functional Core: Transforms Tree+Status into UI
---@param tree_mod table The tree module (v2.lua)
---@param status_map table<string, TestNodeStatus> Map of NodeID -> Status Object
---@param options table
M.build = function(tree_mod, status_map, options)
  local lines = {}
  local highlights = {}
  local index = 0

  -- Traverse visual tree (expanded nodes only)
  tree_mod.traverse_expanded(nil, function(node)
    index = index + 1
    local status = status_map[node.id]

    local line_text, hl_group = format_line(node, status)
    table.insert(lines, line_text)

    if hl_group then table.insert(highlights, { index = index, group = hl_group }) end
  end)

  return lines, highlights
end

---Helper to map line number back to Node
M.get_node_at_line = function(tree_mod, line_index)
  local current = 1
  local found = nil
  tree_mod.traverse_expanded(nil, function(node)
    if found then return end
    if current == line_index then found = node end
    current = current + 1
  end)
  return found
end

return M
