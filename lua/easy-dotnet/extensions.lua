-- All the extension methods I never wanna write twice
local E = {}
E.remove_filename_from_path = function(path)
  -- Find the last occurrence of the directory separator
  local separator_index = path:find("[\\/]([^\\/]+)$")

  -- If separator found, remove the filename and return the modified path
  if separator_index then
    return path:sub(1, separator_index - 1)
  else
    -- If no separator found, return the original path
    return path
  end
end

E.isWindows = function()
  local platform = vim.loop.os_uname().sysname
  return platform == "Windows_NT"
end


-- Files
E.get_current_buffer_path = function()
  local bufnr = vim.api.nvim_get_current_buf()
  return vim.api.nvim_buf_get_name(bufnr)
end
local function executeCommand(command)
  local handle = io.popen(command) -- Open a pipe to the command
  local result = {}
  for line in handle:lines() do    -- Iterate over each line of output
    table.insert(result, line)     -- Insert each line into the table
  end
  handle:close()                   -- Close the pipe
  return result                    -- Return the table containing output lines
end

E.find_file_recursive = function(pattern, max_depth, directory)
  local cmd = string.format("find %s -maxdepth " .. max_depth .. " -type f -name '" .. pattern .. "'", directory)
  return executeCommand(cmd)
end

E.get_git_root = function()
  local command = "git rev-parse --show-toplevel"
  local handle = io.popen(command)
  if handle == nil then
    error("Failed to execute command: " .. command)
  end
  local value = handle:read("l")
  handle:close()
  return value
end

E.get_last_sub_path = function(path)
  local components = {}
  for component in path:gmatch("[^/]+") do
    table.insert(components, component)
  end
  local last_component = components[#components]

  return last_component
end

-- Tables
local function filter_table(tbl, cb)
  local results = {}
  for _, item in ipairs(tbl) do
    if cb(item) then
      table.insert(results, item)
    end
  end

  return results
end

local function filter_iterator(tbl, cb)
  local results = {}
  for line in tbl do
    if cb(line) then
      table.insert(results, line)
    end
  end
  return results
end

E.filter = function(tbl, cb)
  local table_type = type(tbl)
  if table_type == "function" then
    return filter_iterator(tbl, cb)
  elseif table_type == "table" then
    return filter_table(tbl, cb)
  else
    error("Expected function or table, received: " .. table_type)
  end
end

local function map_table(tbl, cb)
  local results = {}
  for _, item in ipairs(tbl) do
    table.insert(results, cb(item))
  end
  return results
end

local function map_iterator(tbl, cb)
  local results = {}
  for line in tbl do
    table.insert(results, cb(line))
  end
  return results
end

E.map = function(tbl, cb)
  local table_type = type(tbl)
  if table_type == "function" then
    return map_iterator(tbl, cb)
  elseif table_type == "table" then
    return map_table(tbl, cb)
  else
    error("Expected function or table, received: " .. table_type)
  end
end

local function foreach_table(tbl, cb)
  for index, item in ipairs(tbl) do
    cb(item, index)
  end
end

local function foreach_iterator(tbl, cb)
  for line in tbl do
    cb(line)
  end
end

E.foreach = function(tbl, cb)
  local table_type = type(tbl)
  if table_type == "function" then
    return foreach_iterator(tbl, cb)
  elseif table_type == "table" then
    return foreach_table(tbl, cb)
  else
    error("Expected function or table, received: " .. table_type)
  end
end

local function any_table(tbl, cb)
  for _, item in ipairs(tbl) do
    if cb(item) then
      return true
    end
  end
  return false
end

local function any_iterator(tbl, cb)
  for line in tbl do
    if cb(line) then
      return true
    end
  end
  return false
end

E.any = function(tbl, cb)
  local table_type = type(tbl)
  if table_type == "function" then
    return any_iterator(tbl, cb)
  elseif table_type == "table" then
    return any_table(tbl, cb)
  else
    error("Expected function or table, received: " .. table_type)
  end
end
local function find_table(tbl, cb)
  for _, item in ipairs(tbl) do
    if cb(item) then
      return item
    end
  end
  return false
end

local function find_iterator(tbl, cb)
  for line in tbl do
    if cb(line) then
      return line
    end
  end
  return false
end

---
---@param tbl table A table to search through
---@param cb function A function to run on every item
---@return boolean|string|table
E.find = function(tbl, cb)
  local table_type = type(tbl)
  if table_type == "function" then
    return find_iterator(tbl, cb)
  elseif table_type == "table" then
    return find_table(tbl, cb)
  end
  error("Expected function or table, received: " .. table_type)
end
local function every_table(tbl, cb)
  for _, item in ipairs(tbl) do
    if not cb(item) then
      return false
    end
  end
  return true
end

local function every_iterator(tbl, cb)
  for line in tbl do
    if not cb(line) then
      return false
    end
  end
  return true
end

E.every = function(tbl, cb)
  local table_type = type(tbl)
  if table_type == "function" then
    return every_iterator(tbl, cb)
  elseif table_type == "table" then
    return every_table(tbl, cb)
  else
    error("Expected function or table, received: " .. table_type)
  end
end

return E
