local ns_id = require("easy-dotnet.constants").ns_id
local polyfills = require("easy-dotnet.polyfills")

---@class Window
---@field tree table<string,TestNode>
---@field jobs table
---@field appendJob table
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
  tree = {},
  jobs = {},
  appendJob = nil,
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

---Traverses a tree from the given node, giving a callback for every item
---@param tree TestNode | nil
---@param cb function
M.traverse = function(tree, cb)
  if not tree then tree = M.tree end
  --HACK: handle no tree set
  if not tree.name then return end

  cb(tree)
  for _, node in pairs(tree.children or {}) do
    M.traverse(node, cb)
  end
end

M.traverse_expanded = function(tree, cb)
  if not tree then tree = M.tree end
  --HACK: handle no tree set
  if not tree.name then return end
  cb(tree)
  for _, node in pairs(tree.children or {}) do
    local filterpass = M.filter == nil or (M.filter == node.icon or node.icon == "<Running>")
    if tree.expanded and filterpass then M.traverse_expanded(node, cb) end
  end
end

---@param id string
---@param type "Run" | "Discovery" | "Build"
---@param subtask_count number | nil
function M.appendJob(id, type, subtask_count)
  local job = {
    type = type,
    id = id,
    subtask_count = (subtask_count and subtask_count > 0) and subtask_count or 1,
  }
  table.insert(M.jobs, job)
  M.refreshTree()

  local on_job_finished_callback = function()
    job.completed = true
    local is_all_finished = polyfills.iter(M.jobs):all(function(s) return s.completed end)
    if is_all_finished == true then M.jobs = {} end
    M.refreshTree()
  end

  return on_job_finished_callback
end

function M.redraw_virtual_text()
  if #M.jobs > 0 then
    local total_subtask_count = 0
    local completed_count = 0
    for _, value in ipairs(M.jobs) do
      total_subtask_count = total_subtask_count + value.subtask_count
      if value.completed == true then completed_count = completed_count + value.subtask_count end
    end

    local job_type = M.jobs[1].type

    vim.api.nvim_buf_set_extmark(M.buf, ns_id, 0, 0, {
      virt_text = {
        {
          string.format("%s %s/%s", job_type == "Run" and "Running" or job_type == "Discovery" and "Discovering" or "Building", completed_count, total_subtask_count),
          "Character",
        },
      },
      virt_text_pos = "right_align",
      priority = 200,
    })
  end
end

local function setBufferOptions()
  if M.options.viewmode ~= "buf" then vim.api.nvim_win_set_height(M.win, M.height) end
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
---@param tree TestNode The root node of the tree structure to traverse.
---@return TestNode | nil
local function translateIndex(line_num, tree)
  local current_line = 1
  local result = nil

  M.traverse_expanded(tree, function(node)
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
  if node.icon == M.options.icons.failed then
    return "EasyDotnetTestRunnerFailed"
  elseif node.icon == "<Running>" then
    return "EasyDotnetTestRunnerRunning"
  elseif node.icon == M.options.icons.passed then
    return "EasyDotnetTestRunnerPassed"
  elseif node.highlight ~= nil and type(node.highlight) == "string" then
    return node.highlight
  end
  return nil
end

local function convert_time(timeStr)
  local hours, minutes, seconds, microseconds = timeStr:match("(%d+):(%d+):(%d+)%.(%d+)")
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

local function node_to_string(node)
  local total_tests = 0
  ---@param i TestNode
  M.traverse(node, function(i)
    if i.type == "subcase" or i.type == "test" then total_tests = total_tests + 1 end
  end)

  local formatted = string.format(
    "%s%s%s%s %s %s",
    string.rep(" ", node.indent or 0),
    node.preIcon and (node.preIcon .. " ") or "",
    node.name,
    node.icon and node.icon ~= M.options.icons.passed and (" " .. node.icon) or "",
    node.type ~= "subcase" and node.type ~= "test" and string.format("(%s)", total_tests) or "",
    node.duration and convert_time(node.duration) or ""
  )

  return formatted
end

---@param tree TestNode
---@return string[], table[]
local function tree_to_string(tree)
  local result = {}
  local highlights = {}
  local index = 0
  ---@param node TestNode
  M.traverse_expanded(tree, function(node)
    index = index + 1

    local formatted = node_to_string(node)
    local highlight = calculate_highlight(node)
    table.insert(highlights, { index = index, highlight = highlight })
    table.insert(result, formatted)
  end)
  return result, highlights
end

local function printNodes()
  vim.api.nvim_buf_clear_namespace(M.buf, ns_id, 0, -1)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)
  local stringLines, highlights = tree_to_string(M.tree)
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, true, stringLines)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", M.modifiable)

  M.redraw_virtual_text()
  apply_highlights(highlights)
end

local function setMappings()
  if M.keymap == nil then return end
  if M.buf == nil then return end
  for key, value in pairs(M.keymap()) do
    vim.keymap.set("n", key, function()
      local line_num = vim.api.nvim_win_get_cursor(0)[1]
      local node = translateIndex(line_num, M.tree)
      if not node then error("Current line is not a node") end
      value(node, M)
    end, { buffer = M.buf, noremap = true, silent = true })
  end
end

M.setKeymaps = function(mappings)
  M.keymap = mappings
  setMappings()
  return M
end

---@param options TestRunnerOptions
M.setOptions = function(options)
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
---@param mode "float" | "split" | "buf"
-- Function to hide the window or buffer based on the mode
function M.hide(mode)
  if not mode then mode = M.options.viewmode end
  if mode == "float" or mode == "split" then
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

---@param mode "float" | "split" | "buf"
function M.open(mode)
  if not mode then mode = M.options.viewmode end

  if mode == "float" then
    if not M.buf then M.buf = vim.api.nvim_create_buf(false, true) end
    local win_opts = get_default_win_opts()
    M.win = vim.api.nvim_open_win(M.buf, true, win_opts)
    vim.api.nvim_buf_set_option(M.buf, "bufhidden", "hide")
    return true
  elseif mode == "split" then
    if not M.buf then M.buf = vim.api.nvim_create_buf(false, true) end
    vim.cmd("split")
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

---@param mode "float" | "split" | "buf"
function M.toggle(mode)
  if not mode then mode = M.options.viewmode end

  if mode == "float" or mode == "split" then
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
---@param mode "float" | "split" | "buf"
M.render = function(mode)
  local isVisible = M.toggle(mode)
  if not isVisible then return end

  printNodes()
  setBufferOptions()
  setMappings()
  return M
end

M.refreshMappings = function()
  if M.buf == nil then error("Can not refresh buffer before render() has been called") end
  setMappings()
  return M
end

M.refreshTree = function()
  if M.buf == nil then error("Can not refresh buffer before render() has been called") end
  printNodes()
  return M
end

--- Refreshes the buffer if lines have changed
M.refresh = function()
  if M.buf == nil then error("Can not refresh buffer before render() has been called") end
  printNodes()
  setBufferOptions()
  return M
end

return M
