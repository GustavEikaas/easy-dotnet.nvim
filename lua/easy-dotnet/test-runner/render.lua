local ns_id = require("easy-dotnet.constants").ns_id
local M = {
  lines = {
    { value = "Discovering tests...", preIcon = "🔃" }
  },
  jobs = {},
  appendJob = nil,
  buf = nil,
  win = nil,
  height = 10,
  modifiable = false,
  buf_name = "",
  filetype = "",
  filter = nil,
  keymap = {}
}

---@param id string
---@param type "Run" | "Discovery"
---@param subtask_count number | nil
function M.appendJob(id, type, subtask_count)
  table.insert(M.jobs, { type = type, id = id, subtask_count = subtask_count or 1 })
  M.refreshLines()

  return function()
    local is_all_finished = true
    for _, value in ipairs(M.jobs) do
      if value.id == id then
        value.completed = true
      end

      if value.completed ~= true then
        is_all_finished = false
      end
    end
    if is_all_finished == true then
      M.jobs = {}
    end
    M.refreshLines()
  end
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

    vim.api.nvim_buf_set_extmark(M.buf, ns_id, 0, 0, {
      virt_text = { { string.format("%s %s/%s", M.jobs[1].type == "Run" and "Running" or "Discovering", completed_count, total_subtask_count), "Character" } },
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

-- Translates line num to M.lines index accounting for hidden lines
local function translateIndex(line_num)
  local i = 0
  local r = nil

  for index, line in ipairs(M.lines) do
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
  for _, value in ipairs(M.lines) do
    if value.hidden == false or value.hidden == nil then
      shadow_index = shadow_index + 1
      if value.icon == "❌" then
        vim.api.nvim_buf_add_highlight(M.buf, ns_id, "ErrorMsg", shadow_index - 1, 0, -1)
      elseif value.icon == "<Running>" then
        vim.api.nvim_buf_add_highlight(M.buf, ns_id, "SpellCap", shadow_index - 1, 0, -1)
      elseif value.icon == "✔" then
        vim.api.nvim_buf_add_highlight(M.buf, ns_id, "Character", shadow_index - 1, 0, -1)
      elseif value.highlight ~= nil and type(value.highlight) == "string" then
        vim.api.nvim_buf_add_highlight(M.buf, ns_id, value.highlight, shadow_index - 1, 0, -1)
      end
    end
  end
end

local function printLines()
  vim.api.nvim_buf_clear_namespace(M.buf, ns_id, 0, -1)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)
  local stringLines = {}
  for _, line in ipairs(M.lines) do
    if line.hidden == false or line.hidden == nil then
      local formatted = string.format("%s%s%s%s", string.rep(" ", line.indent or 0),
        line.preIcon and (line.preIcon .. " ") or "", line.name,
        line.icon and line.icon ~= "✔" and (" " .. line.icon) or "")
      table.insert(stringLines, formatted)
    end
  end

  vim.api.nvim_buf_set_lines(M.buf, 0, -1, true, stringLines)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", M.modifiable)
  M.redraw_virtual_text()

  apply_highlights()
end

local function setMappings()
  if M.keymap == nil then
    return
  end
  if M.buf == nil then
    return
  end
  for key, value in pairs(M.keymap) do
    vim.keymap.set('n', key, function()
      local line_num = vim.api.nvim_win_get_cursor(0)[1]
      local index = translateIndex(line_num)
      value(index, M.lines[index], M)
    end, { buffer = M.buf, noremap = true, silent = true })
  end
end

M.setKeymaps = function(mappings)
  M.keymap = mappings
  setMappings()
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
local function toggle(mode)
  if mode == "float" then
    -- Handle floating window mode
    if M.win and vim.api.nvim_win_is_valid(M.win) then
      -- Close floating window (hides it, buffer is not deleted)
      vim.api.nvim_win_close(M.win, false) -- false means don't force delete buffer
      M.win = nil
      return false
    else
      -- Create a floating window
      if not M.buf then
        M.buf = vim.api.nvim_create_buf(false, true) -- Create new buffer if not exists
      end
      local win_opts = get_default_win_opts()
      M.win = vim.api.nvim_open_win(M.buf, true, win_opts)
      vim.api.nvim_buf_set_option(M.buf, 'bufhidden', 'hide') -- Set to hide buffer on close
      return true
    end
  elseif mode == "split" then
    -- Handle split window mode
    if M.win and vim.api.nvim_win_is_valid(M.win) then
      -- Close split (hides the buffer)
      vim.api.nvim_win_close(M.win, false) -- false means don't delete the buffer
      M.win = nil
      return false
    else
      -- Create a split window
      if not M.buf then
        M.buf = vim.api.nvim_create_buf(false, true) -- Create new buffer if not exists
      end
      vim.cmd("split")                               -- Create split below
      M.win = vim.api.nvim_get_current_win()         -- Get the split window
      vim.api.nvim_win_set_buf(M.win, M.buf)         -- Set buffer in the split
      return true
    end
  elseif mode == "buf" then
    -- Handle buffer mode (rendered in window 0)
    if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
      -- Hide buffer by switching to another buffer in current window (window 0)
      vim.cmd("b#") -- Switch to previous buffer
      return false
    else
      -- Create or switch to buffer in the current window
      if not M.buf then
        M.buf = vim.api.nvim_create_buf(false, true)
      end
      vim.api.nvim_set_current_buf(M.buf)
      return true
    end
  end
  return false
end

--- Renders the buffer
---@param mode "float" | "split" | "buf"
M.render = function(mode)
  local isVisible = toggle(mode)
  if not isVisible then
    return
  end

  printLines()
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

M.refreshLines = function()
  if M.buf == nil then
    error("Can not refresh buffer before render() has been called")
  end
  printLines()
  return M
end

--- Refreshes the buffer if lines have changed
M.refresh = function()
  if M.buf == nil then
    error("Can not refresh buffer before render() has been called")
  end
  printLines()
  setBufferOptions()
  return M
end


return M
