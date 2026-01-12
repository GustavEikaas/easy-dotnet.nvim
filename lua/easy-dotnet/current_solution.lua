local constants = require("easy-dotnet.constants")

---@class SolutionCache
---@field solution_path string Absolute path to the solution file
---@field root_dir string convenience to check where it was cached from

---@class SolutionOption
---@field display string

local M = {
  max_depth = 2,
  cache_dir = constants.get_data_directory(),
}

--- Validates that the decoded JSON has the correct structure
---@param data any
---@return SolutionCache?
local function validate_cache_data(data)
  if type(data) ~= "table" then return nil end

  if type(data.solution_path) ~= "string" then return nil end

  return {
    solution_path = data.solution_path,
  }
end

--- Finds solution files starting from cwd
---@param cb fun(solutions: string[])
local function get_solutions_async(cb)
  local scan = require("plenary.scandir")
  scan.scan_dir_async(".", {
    respect_gitignore = true,
    search_pattern = "%.slnx?$",
    depth = M.max_depth,
    silent = true,
    on_exit = function(solutions)
      -- Normalize all paths to absolute
      local normalized = vim.tbl_map(function(path) return vim.fs.normalize(vim.fn.fnamemodify(path, ":p")) end, solutions)
      vim.schedule(function() cb(normalized) end)
    end,
  })
end

--- Prompts user to pick a solution from available options
---@param cb fun(solution_path: string?)
local function pick_solution(cb)
  get_solutions_async(function(solutions)
    if #solutions == 0 then
      cb(nil)
      return
    end

    ---@type SolutionOption[]
    local options = vim.tbl_map(function(value) return { display = value } end, solutions)

    require("easy-dotnet.picker").picker(nil, options, function(chosen) cb(chosen and chosen.display or nil) end, "Pick solution file", true, true)
  end)
end

--- Gets the data directory for storing solution cache files
---@return string
local function get_data_dir()
  local dir = vim.fs.joinpath(constants.get_data_directory(), "solutions")
  local file_utils = require("easy-dotnet.file-utils")
  file_utils.ensure_directory_exists(dir)
  return dir
end

--- Get the hash of the current working directory
---@return string
local function get_cwd_hash() return vim.fn.sha256(vim.fn.getcwd()) end

--- Gets the full path to the cache file for current cwd
---@return string
local function get_cache_file_path() return vim.fs.joinpath(get_data_dir(), get_cwd_hash()) end

--- Validates that a solution path exists and is readable
---@param path string?
---@return boolean
local function is_valid_solution(path)
  if not path or type(path) ~= "string" then return false end
  return vim.fn.filereadable(path) == 1
end

--- Clears the persisted solution for current cwd
local function clear_cache()
  local cache_path = get_cache_file_path()
  if vim.fn.filereadable(cache_path) == 1 then pcall(vim.loop.fs_unlink, cache_path) end
end

--- Reads the cache file and returns the decoded data
---@return SolutionCache | nil
local function read_cache_file()
  local cache_path = get_cache_file_path()

  if vim.fn.filereadable(cache_path) ~= 1 then return nil end

  local ok, contents = pcall(vim.fn.readfile, cache_path)
  if not ok then
    clear_cache()
    return nil
  end

  local json_str = table.concat(contents)
  local success, data = pcall(vim.fn.json_decode, json_str)

  -- Failed to decode JSON
  if not success then
    clear_cache()
    return nil
  end

  -- Validate the structure
  local validated = validate_cache_data(data)
  if not validated then
    clear_cache()
    return nil
  end

  return validated
end

--- Writes the solution cache to disk
---@param cache_data SolutionCache
---@return boolean success
local function write_cache_file(cache_data)
  local cache_path = get_cache_file_path()
  local stringified = vim.fn.json_encode(cache_data)

  local ok = pcall(vim.fn.writefile, { stringified }, cache_path)
  return ok
end

--- Reads and validates the persisted solution path
---@return string? solution_path Absolute path to solution, or nil if not found/invalid
local function try_get_solution_path()
  local cache_data = read_cache_file()

  if not cache_data then return nil end

  local solution_path = cache_data.solution_path

  -- Solution file was moved/deleted
  if not is_valid_solution(solution_path) then
    clear_cache()
    return nil
  end

  return solution_path
end

--- Returns the currently selected solution for this cwd, or nil
---@return string? solution_path Absolute path to the solution file
function M.try_get_selected_solution() return try_get_solution_path() end

--- Gets existing solution or prompts user to pick one
---@param cb fun(solution_path: string | nil) Callback with selected solution path or nil if cancelled
function M.get_or_pick_solution(cb)
  local curr_solution = try_get_solution_path()
  if curr_solution then
    cb(curr_solution)
    return
  end

  pick_solution(function(path)
    if path then M.set_solution(path) end
    coroutine.wrap(cb)(path)
    cb(path)
  end)
end

--- Sets the solution for the current cwd
---@param path string Solution path (will be normalized to absolute)
---@return boolean success True if successfully persisted
function M.set_solution(path)
  -- Validate input type
  if type(path) ~= "string" then error("set_solution expects a string path, got: " .. type(path)) end

  local normalized_path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))

  if not is_valid_solution(normalized_path) then error("Solution file does not exist or is not readable: " .. normalized_path) end

  ---@type SolutionCache
  local cache_data = {
    solution_path = normalized_path,
    root_dir = normalized_path,
  }

  return write_cache_file(cache_data)
end

--- Clears the current solution for this cwd
function M.clear_selected_solution() clear_cache() end

return M
