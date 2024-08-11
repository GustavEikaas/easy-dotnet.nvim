local M = {
  lines = {
    { value = "Discovering tests...", icon = "🔃" }
  },
  buf = nil,
  height = 10,
  modifiable = false,
  buf_name = "",
  filetype = "",
  keymap = {}
}

local function setBufferOptions()
  vim.api.nvim_win_set_height(0, M.height)
  vim.api.nvim_buf_set_option(M.buf, 'modifiable', M.modifiable)
  vim.api.nvim_buf_set_name(M.buf, M.buf_name)
  vim.api.nvim_buf_set_option(M.buf, "filetype", M.filetype)
end

local function printLines()
  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)
  local stringLines = {}
  for _, line in ipairs(M.lines) do
    if line.hidden == false or line.hidden == nil then
      local formatted = string.format("%s%s%s%s", string.rep(" ", line.indent or 0),
        line.preIcon and (line.preIcon .. " ") or "", line.value,
        line.icon and (" " .. line.icon) or "")
      table.insert(stringLines, formatted)
    end
  end

  vim.api.nvim_buf_set_lines(M.buf, 0, -1, true, stringLines)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", M.modifiable)
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

--- Renders the buffer
M.render = function()
  M.buf = vim.api.nvim_create_buf(true, true) -- false for not listing, true for scratchend
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
