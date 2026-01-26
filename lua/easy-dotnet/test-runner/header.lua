local Window = require("easy-dotnet.test-runner.window")
local M = {}

-- Map C# OverallStatusEnum integers to Icons/Text
-- 0: Idle, 1: Discovering, 2: Running, 3: Passed, 4: Failed, 5: Skipped (Adjust as needed)
local STATUS_ICONS = {
  [0] = { icon = "💤", text = "Idle" },
  [1] = { icon = "🚀", text = "Running" },
  [2] = { icon = "✔", text = "Passed" },
  [3] = { icon = "✘", text = "Failed" },
  [4] = { icon = "", text = "Cancelled" },
}

local ACTION_KEYS = {
  Run = "[r] Run",
  Debug = "[d] Debug",
  PeekOutput = "[c] Output",
  GoToSource = "[g] Goto",
  Refresh = "[R] Refresh",
}

---@param node TestNode
---@return string[]
local function get_default_actions(node)
  local actions = { "Run" }

  if node.type == "TestMethod" or node.type == "Subcase" then
    table.insert(actions, "Debug")
    if node.filePath then table.insert(actions, "GoToSource") end
  elseif node.type == "Solution" or node.type == "Project" then
    table.insert(actions, "Refresh")
  end

  return actions
end

---@class TestRunnerStatus
---@field isLoading boolean
---@field overallStatus number
---@field totalPassed number
---@field totalFailed number
---@field totalSkipped number

---@param node TestNode | nil
---@param status table | nil
local function format_actions(node, status)
  if not node then return "" end

  local action_list = {}

  if status and status.actions and #status.actions > 0 then
    action_list = status.actions
  else
    action_list = get_default_actions(node)
  end

  local parts = {}
  for _, action in ipairs(action_list) do
    if ACTION_KEYS[action] then table.insert(parts, ACTION_KEYS[action]) end
  end

  if #parts == 0 then return "" end
  return " " .. table.concat(parts, "  ")
end

---Pure Function: Formats status object to string and highlight group
---@param status TestRunnerStatus
---@return string line, string highlight_group
local function format_content(status)
  status = status or {}

  -- 1. Determine Status Definition
  local def = STATUS_ICONS[status.overallStatus] or { icon = "?", text = "Unknown" }

  -- Override if loading
  if status.isLoading then def = { icon = "⏳", text = "Working..." } end

  -- 2. Format Counts
  local counts = string.format("✔ %d   ✘ %d    %d", status.totalPassed or 0, status.totalFailed or 0, status.totalSkipped or 0)

  -- 3. Construct Line
  -- Layout:  [Icon] [StatusText]       |   [Counts]
  local line = string.format(" %s %-12s │   %s", def.icon, def.text, counts)

  -- 4. Determine Color
  local hl = "Directory" -- Default Blue/Cyan
  if (status.totalFailed or 0) > 0 then
    hl = "ErrorMsg" -- Red
  elseif status.overallStatus == 3 then
    hl = "String" -- Green
  end

  return line, hl
end

---@type Window | nil
M.win_instance = nil

---Render Side Effect: Updates the header window content
---@param status TestRunnerStatus
M.render = function(status, active_node, active_node_status)
  -- Guard: Only render if window exists and is valid
  if not M.win_instance or not M.win_instance.win or not vim.api.nvim_win_is_valid(M.win_instance.win) then return end

  local line1, hl1 = format_content(status or {})

  -- Line 2: Contextual Actions
  local line2 = format_actions(active_node, active_node_status)

  -- Use Window class method to write
  M.win_instance:write_buf({ line1, line2 })

  if M.win_instance.buf then
    vim.api.nvim_buf_add_highlight(M.win_instance.buf, -1, hl1, 0, 0, -1)
    vim.api.nvim_buf_add_highlight(M.win_instance.buf, -1, "Comment", 1, 0, -1)
  end
end

---Creates the header window relative to the parent window options
---@param parent_opts table The options used to create the main runner window
---@return Window The created window instance
M.create = function(parent_opts)
  -- Cleanup existing if any
  if M.win_instance then M.close() end

  -- Clone options to calculate position
  local opts = vim.deepcopy(parent_opts)

  -- Position: 3 lines above the main window (1 height + 2 borders)
  opts.row = opts.row - 4
  opts.height = 2
  opts.focusable = false

  -- Instantiate your Window class
  M.win_instance = Window.new_float()
  M.win_instance.opts = opts

  -- Create the actual Vim window
  M.win_instance:create()

  return M.win_instance
end

---Closes the header window and clears state
M.close = function()
  if M.win_instance then
    M.win_instance:close()
    M.win_instance = nil
  end
end

return M
