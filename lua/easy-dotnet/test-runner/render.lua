local ns_id = require("easy-dotnet.constants").ns_id
local extensions = require("easy-dotnet.extensions")


---@class Window
---@field tree table<Project>
---@field jobs table
---@field appendJob table
---@field buf integer | nil
---@field win integer | nil
---@field height integer
---@field modifiable boolean
---@field buf_name string
---@field filetype string
---@field filter table
---@field keymap table
---@field options table


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
  options = {}
}

---@param id string
---@param type "Run" | "Discovery" | "Build"
---@param subtask_count number | nil
function M.appendJob(id, type, subtask_count)
  local job = { type = type, id = id, subtask_count = (subtask_count and subtask_count > 0) and subtask_count or 1 }
  table.insert(M.jobs, job)
  M.refreshTree()

  local on_job_finished_callback = function()
    job.completed = true
    local is_all_finished = extensions.every(M.jobs, function(s) return s.completed end)
    if is_all_finished == true then
      M.jobs = {}
    end
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
      if value.completed == true then
        completed_count = completed_count + value.subtask_count
      end
    end

    local job_type = M.jobs[1].type

    vim.api.nvim_buf_set_extmark(M.buf, ns_id, 0, 0, {
      virt_text = { { string.format("%s %s/%s", job_type == "Run" and "Running" or job_type == "Discovery" and "Discovering" or "Building", completed_count, total_subtask_count), "Character" } },
      virt_text_pos = "right_align",
      priority = 200,
    })
  end
end

local function setBufferOptions()
  vim.api.nvim_win_set_height(0, M.height)
  vim.api.nvim_buf_set_option(M.buf, 'modifiable', M.modifiable)
  vim.api.nvim_buf_set_name(M.buf, M.buf_name)
  vim.api.nvim_buf_set_option(M.buf, "filetype", M.filetype)
end

-- Translates line num to M.tree index accounting for hidden lines
local function translateIndex(line_num)
  local i = 0
  local r = nil

  for index, line in ipairs(M.tree) do
    if line.hidden == false or line.hidden == nil then
      i = i + 1
    end

    if line_num == i then
      r = index
      break
    end
  end

  return r
end


local function apply_highlights()
  --Some lines are hidden so tracking the actual line numbers using shadow_index
  local shadow_index = 0
  for _, value in ipairs(M.tree) do
    if value.hidden == false or value.hidden == nil then
      shadow_index = shadow_index + 1
      if value.icon == M.options.icons.failed then
        vim.api.nvim_buf_add_highlight(M.buf, ns_id, "EasyDotnetTestRunnerFailed", shadow_index - 1, 0, -1)
      elseif value.icon == "<Running>" then
        vim.api.nvim_buf_add_highlight(M.buf, ns_id, "EasyDotnetTestRunnerRunning", shadow_index - 1, 0, -1)
      elseif value.icon == M.options.icons.passed then
        vim.api.nvim_buf_add_highlight(M.buf, ns_id, "EasyDotnetTestRunnerPassed", shadow_index - 1, 0, -1)
      elseif value.highlight ~= nil and type(value.highlight) == "string" then
        vim.api.nvim_buf_add_highlight(M.buf, ns_id, value.highlight, shadow_index - 1, 0, -1)
      end
    end
  end
end

local function flattenTree(tree, result)
  result = result or {}

  for _, node in pairs(tree or {}) do
    -- Format the current node and add it to the result
    local formatted = string.format("%s%s%s%s",
      string.rep(" ", node.indent or 0),
      node.preIcon and (node.preIcon .. " ") or "",
      node.name,
      node.icon and node.icon ~= M.options.icons.passed and (" " .. node.icon) or "")
    table.insert(result, formatted)

    -- Recursively process children
    if node.children and next(node.children) then
      flattenTree(node.children, result)
    end
  end

  return result
end

local function printNodes()
  -- vim.api.nvim_buf_clear_namespace(M.buf, ns_id, 0, -1)

  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)
  print(vim.inspect(M.tree))
  print("" .. (M.tree.children and #M.tree.children or 0))
  local stringLines = flattenTree(M.tree.children)
  print("" .. #stringLines)
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, true, stringLines)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", M.modifiable)

  -- M.redraw_virtual_text()
  -- apply_highlights()
end

local function setMappings()
  if M.keymap == nil then
    return
  end
  if M.buf == nil then
    return
  end
  for key, value in pairs(M.keymap()) do
    vim.keymap.set('n', key, function()
      local line_num = vim.api.nvim_win_get_cursor(0)[1]
      local index = translateIndex(line_num)
      value(index, M.tree[index], M)
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
  if options then
    M.options = options
  end
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
    border = "rounded"
  }
end


-- Toggle function to handle different window modes
---@param mode "float" | "split" | "buf"
-- Function to hide the window or buffer based on the mode
function M.hide(mode)
  if not mode then
    mode = M.options.viewmode
  end
  if mode == "float" or mode == "split" then
    if M.win and vim.api.nvim_win_is_valid(M.win) then
      vim.api.nvim_win_close(M.win, false)
      M.win = nil
      return true
    end
  elseif mode == "buf" then
    if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
      vim.cmd("b#")
      return true
    end
  end
  return false
end

---@param mode "float" | "split" | "buf"
function M.open(mode)
  if not mode then
    mode = M.options.viewmode
  end

  if mode == "float" then
    if not M.buf then
      M.buf = vim.api.nvim_create_buf(false, true)
    end
    local win_opts = get_default_win_opts()
    M.win = vim.api.nvim_open_win(M.buf, true, win_opts)
    vim.api.nvim_buf_set_option(M.buf, "bufhidden", "hide")
    return true
  elseif mode == "split" then
    if not M.buf then
      M.buf = vim.api.nvim_create_buf(false, true)
    end
    vim.cmd("split")
    M.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M.win, M.buf)
    return true
  elseif mode == "buf" then
    if not M.buf then
      M.buf = vim.api.nvim_create_buf(false, true)
    end
    vim.api.nvim_set_current_buf(M.buf)
    return true
  end
  return false
end

---@param mode "float" | "split" | "buf"
function M.toggle(mode)
  if not mode then
    mode = M.options.viewmode
  end

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
  if not isVisible then
    return
  end

  printNodes()
  setBufferOptions()
  setMappings()
  return M
end

M.refreshMappings = function()
  if M.buf == nil then
    error("Can not refresh buffer before render() has been called")
  end
  setMappings()
  return M
end

M.refreshTree = function()
  if M.buf == nil then
    error("Can not refresh buffer before render() has been called")
  end
  printNodes()
  return M
end

--- Refreshes the buffer if lines have changed
M.refresh = function()
  if M.buf == nil then
    error("Can not refresh buffer before render() has been called")
  end
  printNodes()
  setBufferOptions()
  return M
end


return M
