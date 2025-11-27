local ns_id = require("easy-dotnet.constants").ns_id

---@class Window
---@field tree table<string, TestNode>
---@field buf integer | nil
---@field win integer | nil
---@field height integer
---@field modifiable boolean
---@field buf_name string
---@field filetype string
---@field filter TestResult
---@field keymap table
---@field options table

---@class Highlight
---@field index number
---@field highlight string

---@alias TestResult '"Failed"' | '"NotExecuted"' | '"Passed"'

local M = {
  tree_mod = require("easy-dotnet.test-runnerv2.v2"),
  buf = nil,
  win = nil,
  height = 10,
  modifiable = false,
  buf_name = "",
  filetype = "",
  filter = nil,
  keymap = {},
  options = {},
}

local function set_buffer_options()
  if M.options.viewmode ~= "buf" and M.options.viewmode ~= "vsplit" then vim.api.nvim_win_set_height(M.win, M.height) end
  vim.api.nvim_buf_set_option(M.buf, "modifiable", M.modifiable)
  vim.api.nvim_buf_set_name(M.buf, M.buf_name)
  vim.api.nvim_buf_set_option(M.buf, "filetype", M.filetype)
  --Crashes on nvim 0.9.5??
  -- vim.api.nvim_buf_set_option(M.buf, "cursorline", true)
end

---Translates a line number to the corresponding node in the tree structure, considering the `expanded` flag of nodes.
---Only expanded nodes contribute to the line number count, while collapsed nodes and their children are ignored.
---
---@param line_num number The line number in the buffer to be translated to a node in the tree structure.
---@return TestNode | nil
local function translate_index(line_num)
  local current_line = 1
  local result = nil

  M.tree_mod.traverse_expanded(nil, function(node)
    if result ~= nil then return end
    if current_line == line_num then result = node end
    current_line = current_line + 1
  end)

  return result
end

---@param highlights Highlight[]
local function apply_highlights(highlights)
  for _, value in ipairs(highlights) do
    if value.highlight ~= nil then vim.api.nvim_buf_add_highlight(M.buf, ns_id, value.highlight, value.index - 1, 0, -1) end
  end
end

---@param node TestNode
---@return string | nil
local function calculate_highlight(node)
  local status = M.tree_mod.status_by_id[node.id]
  if not status then return nil end

  vim.print(node.displayName .. "status " .. status)
  if status == nil or status == "Idle" or status == "Discovering" then
    --TODO: color based on node.type
    if node.type == "Solution" then
      return "EasyDotnetTestRunnerRunning"
    elseif node.type == "Project" then
      return "EasyDotnetTestRunnerPassed"
    end
    return "EasyDotnetTestRunnerRunning"
  end
  -- if node.job then
  --   if node.job.state == "pending" then
  --     return "EasyDotnetTestRunnerRunning"
  --   elseif node.job.state == "error" then
  --     return "EasyDotnetTestRunnerFailed"
  --   end
  -- end
  -- if node.icon == M.options.icons.failed then
  --   return "EasyDotnetTestRunnerFailed"
  -- elseif node.icon == "<Running>" then
  --   return "EasyDotnetTestRunnerRunning"
  -- elseif node.icon == M.options.icons.passed then
  --   return "EasyDotnetTestRunnerPassed"
  -- elseif node.highlight ~= nil and type(node.highlight) == "string" then
  --   return node.highlight
  -- end
  return nil
end

local function convert_time(time_str)
  local hours, minutes, seconds, microseconds = time_str:match("(%d+):(%d+):(%d+)%.(%d+)")
  hours = tonumber(hours)
  minutes = tonumber(minutes)
  seconds = tonumber(seconds)
  microseconds = tonumber(microseconds)

  local totalSeconds = hours * 3600 + minutes * 60 + seconds + microseconds / 1000000

  if totalSeconds >= 3600 then
    return string.format("%.1f h", totalSeconds / 3600)
  elseif totalSeconds >= 60 then
    return string.format("%.1f m", totalSeconds / 60)
  elseif totalSeconds >= 1 then
    return string.format("%.1f s", totalSeconds)
  elseif totalSeconds > 0 then
    return string.format("< 1 ms")
  else
    return "< 1 ms"
  end
end

---@param node TestNode
local function node_to_string(node)
  local total_tests = 0
  ---@param i TestNode
  M.tree_mod.traverse(node, function(i)
    if i.type == "subcase" or i.type == "test" then total_tests = total_tests + 1 end
  end)

  local formatted = string.format(
    "%s%s%s%s %s %s",
    string.rep(" ", node.indent or 0),
    node.preIcon and (node.preIcon .. " ") or "",
    node.displayName,
    node.icon and node.icon ~= M.options.icons.passed and (" " .. node.icon) or "",
    -- node.type ~= "subcase" and node.type ~= "test" and string.format("(%s)", total_tests) or "",
    string.format("(%s)", node.type) or "",
    type(node.duration) == "string" and convert_time(node.duration) or ""
  )

  return formatted
end

---@return string[], table[]
local function tree_to_string()
  local result = {}
  local highlights = {}
  local index = 0

  M.tree_mod.traverse_expanded(nil, function(node)
    index = index + 1

    local formatted = node_to_string(node)
    local highlight = calculate_highlight(node)
    table.insert(highlights, { index = index, highlight = highlight })
    table.insert(result, formatted)
  end)

  return result, highlights
end

local function print_nodes()
  vim.api.nvim_buf_clear_namespace(M.buf, ns_id, 0, -1)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)
  local stringLines, highlights = tree_to_string()
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, true, stringLines)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", M.modifiable)

  apply_highlights(highlights)
end

local function set_mappings()
  if M.keymap == nil then return end
  if M.buf == nil or not vim.api.nvim_buf_is_valid(M.buf) then return end
  for key, value in pairs(M.keymap()) do
    vim.keymap.set("n", key, function()
      local line_num = vim.api.nvim_win_get_cursor(0)[1]
      local node = translate_index(line_num)
      if not node then error("Current line is not a node") end
      value.handle(node, M)
    end, { buffer = M.buf, desc = value.desc, noremap = true, silent = true })
  end
end

M.set_keymaps = function(mappings)
  M.keymap = mappings
  set_mappings()
  return M
end

---@param options TestRunnerOptions
M.set_options = function(options)
  if options then M.options = options end
  return M
end

local function get_default_win_opts()
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  M.height = height

  return {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
  }
end

local function has_multiple_listed_buffers()
  local listed_buffers = 0

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_option(buf, "buflisted") then listed_buffers = listed_buffers + 1 end
  end

  return listed_buffers > 0
end

-- Toggle function to handle different window modes
---@param mode "float" | "split" | "buf" | "vsplit"
-- Function to hide the window or buffer based on the mode
function M.hide(mode)
  if not mode then mode = M.options.viewmode end
  if mode == "float" or mode == "split" or mode == "vsplit" then
    if M.win and vim.api.nvim_win_is_valid(M.win) then
      vim.api.nvim_win_close(M.win, false)
      M.win = nil
      return true
    end
  elseif mode == "buf" then
    if M.buf and vim.api.nvim_buf_is_valid(M.buf) and has_multiple_listed_buffers() then
      vim.cmd("bprev")
      return true
    end
  end
  return false
end

function M.close()
  if M.buf then
    vim.api.nvim_buf_delete(M.buf, { force = true })
    M.buf = nil
  end
end

---@param mode "float" | "split" | "buf" | "vsplit"
function M.open(mode)
  if not mode then mode = M.options.viewmode end

  if mode == "float" then
    if not M.buf then M.buf = vim.api.nvim_create_buf(false, true) end
    local win_opts = get_default_win_opts()
    M.win = vim.api.nvim_open_win(M.buf, true, win_opts)
    vim.api.nvim_buf_set_option(M.buf, "bufhidden", "hide")
    return true
  elseif mode == "split" or mode == "vsplit" then
    if not M.buf then M.buf = vim.api.nvim_create_buf(false, true) end
    if mode == "vsplit" and type(M.options.vsplit_width) == "number" and M.options.vsplit_width < vim.o.columns then
      mode = (M.options.vsplit_pos or "") .. tostring(M.options.vsplit_width) .. mode
    else
      mode = (M.options.vsplit_pos or "") .. tostring(math.floor(vim.o.columns * 0.5)) .. mode
    end
    vim.cmd(mode)
    M.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M.win, M.buf)
    return true
  elseif mode == "buf" then
    if not M.buf then M.buf = vim.api.nvim_create_buf(false, true) end
    M.win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_buf(M.buf)
    return true
  end
  return false
end

---@param mode "float" | "split" | "buf" | "vsplit"
function M.toggle(mode)
  if not mode then mode = M.options.viewmode end

  if mode == "float" or mode == "split" or mode == "vsplit" then
    if M.win and vim.api.nvim_win_is_valid(M.win) then
      return not M.hide(mode)
    else
      return M.open(mode)
    end
  elseif mode == "buf" then
    if M.buf and vim.api.nvim_buf_is_valid(M.buf) and vim.api.nvim_get_current_buf() == M.buf then
      return not M.hide(mode)
    else
      return M.open(mode)
    end
  end
  return false
end

--- Renders the buffer
---@param mode "float" | "split" | "buf" | "vsplit"
M.render = function(mode)
  local isVisible = M.toggle(mode)
  if not isVisible then return end

  print_nodes()
  set_buffer_options()
  set_mappings()
  return M
end

M.refreshMappings = function()
  if M.buf == nil then error("Can not refresh buffer before render() has been called") end
  set_mappings()
  return M
end

M.refreshTree = function()
  if M.buf == nil then error("Can not refresh buffer before render() has been called") end
  print_nodes()
  return M
end

--- Refreshes the buffer if lines have changed
M.refresh = function()
  if M.buf == nil then error("Can not refresh buffer before render() has been called") end
  print_nodes()
  set_buffer_options()
  set_mappings()
  return M
end

return M
