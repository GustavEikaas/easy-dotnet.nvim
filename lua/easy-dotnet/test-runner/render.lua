local M = {
  lines = {
    { value = "Discovering tests...", preIcon = "🔃" }
  },
  buf = nil,
  height = 10,
  modifiable = false,
  buf_name = "",
  filetype = "",
  filter = nil,
  keymap = {}
}

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
  local ns_id = require("easy-dotnet.constants").ns_id

  --Some lines are hidden so tracking the actual line numbers using shadow_index
  local shadow_index = 0
  for _, value in ipairs(M.lines) do
    if value.hidden == false or value.hidden == nil then
      shadow_index = shadow_index + 1
      if value.highlight ~= nil then
        if type(value.highlight) == "string" then
          vim.api.nvim_buf_add_highlight(M.buf, ns_id, value.highlight, shadow_index - 1, 0, -1)
        else
          vim.notify("hl not supported as table")
        end
      end
    end
  end
end

local function printLines()
  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)
  local stringLines = {}
  for _, line in ipairs(M.lines) do
    if line.hidden == false or line.hidden == nil then
      local formatted = string.format("%s%s%s%s", string.rep(" ", line.indent or 0),
        line.preIcon and (line.preIcon .. " ") or "", line.name,
        line.icon and (" " .. line.icon) or "")
      table.insert(stringLines, formatted)
    end
  end

  vim.api.nvim_buf_set_lines(M.buf, 0, -1, true, stringLines)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", M.modifiable)

  apply_highlights()
end





local function setMappings()
  if M.keymap == nil then
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

local function buffer_exists(name)
  local bufs = vim.api.nvim_list_bufs()
  for _, buf_id in ipairs(bufs) do
    if vim.api.nvim_buf_is_valid(buf_id) then
      local buf_name = vim.api.nvim_buf_get_name(buf_id)
      local buf_filename = vim.fn.fnamemodify(buf_name, ":t")
      if buf_filename == name then
        return buf_id
      end
    end
  end
  return nil
end
--- Renders the buffer
M.render = function()
  -- if buf exists, restore
  local existing_buf = buffer_exists(M.buf_name)
  M.buf = existing_buf or vim.api.nvim_create_buf(true, true) -- false for not listing, true for scratchend
  vim.cmd("split")
  vim.api.nvim_win_set_buf(0, M.buf)
  vim.api.nvim_set_current_buf(M.buf)

  printLines()
  setBufferOptions()
  setMappings()
  --TODO: add highlights
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
