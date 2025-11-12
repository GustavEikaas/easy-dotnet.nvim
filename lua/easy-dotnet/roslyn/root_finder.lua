local Path = require("plenary.path")
local scan = require("plenary.scandir")

local M = {}

local function find_file_in_directory_or_parents(directory, pattern)
  local results = scan.scan_dir(directory, {
    search_pattern = pattern,
    depth = 1,
    hidden = false,
    add_dirs = false,
  })

  if #results > 0 then return results[1] end

  local parent = Path:new(directory):parent()
  if parent and parent:absolute() ~= directory then
    return find_file_in_directory_or_parents(parent:absolute(), pattern)
  else
    return nil
  end
end

local function find_files_in_directory_or_parents(directory, patterns)
  local cwd = Path:new(vim.fn.getcwd()):absolute()
  local matches = {}

  while directory ~= nil do
    for _, pattern in ipairs(patterns) do
      local results = scan.scan_dir(directory, {
        search_pattern = pattern,
        depth = 1,
        hidden = false,
        add_dirs = false,
      })
      for _, f in ipairs(results) do
        table.insert(matches, f)
      end
    end

    if directory == cwd then
      break
    end

    local parent = Path:new(directory):parent()
    if parent and parent:absolute() ~= directory then
      directory = parent:absolute()
    else
      break
    end
  end

  return matches
end

function M.find_csproj_from_file(file_path)
  local dir = Path:new(file_path):parent()
  if not dir or not dir:exists() then error("Invalid file path: " .. file_path) end
  return find_file_in_directory_or_parents(dir:absolute(), "%.csproj$")
end

function M.find_solutions_from_file(file_path)
  local dir = Path:new(file_path):parent()
  if not dir or not dir:exists() then error("Invalid file path: " .. file_path) end
  return find_files_in_directory_or_parents(dir:absolute(), { "%.sln$", "%.slnx$" })
end

return M
