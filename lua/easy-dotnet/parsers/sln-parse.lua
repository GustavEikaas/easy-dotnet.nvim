local extensions = require "easy-dotnet.extensions"
local M = {}

-- Generates a relative path from cwd to the project.csproj file
local function generate_relative_path_for_project(path, slnpath)
  local dir = vim.fs.dirname(slnpath)
  local res = vim.fs.joinpath(dir, path):gsub("\\", "/")
  return res
end

-- TODO: Investigate using dotnet sln list command
---@param solutionFilePath string
---@return DotnetProject[]
M.get_projects_from_sln = function(solutionFilePath)
  local file = io.open(solutionFilePath, "r")

  if not file then
    error("Failed to open file " .. solutionFilePath)
  end
  local regexp = 'Project%("{(.-)}"%).*= "(.-)", "(.-)", "{.-}"'

  local projectLines = extensions.filter(file:lines(), function(line)
    local id, name, path = line:match(regexp)
    if id and name and path and (path:match("%.csproj$") or path:match("%.fsproj$")) then
      return true
    end
    return false
  end)

  local projects = extensions.map(projectLines, function(line)
    local csproj_parser     = require("easy-dotnet.parsers.csproj-parse")
    local _, _, path        = line:match(regexp)
    local project_file_path = generate_relative_path_for_project(path, solutionFilePath)
    local project           = csproj_parser.get_project_from_project_file(project_file_path)
    return project
  end)
  file:close()
  return projects
end

function M.get_solutions()
  local files = require("plenary.scandir").scan_dir({ "." }, { search_pattern = "%.sln$", depth = 5 })
  return files
end

M.try_get_selected_solution_file = function()
  local files = M.get_solutions()
  for _, value in ipairs(files) do
    local file = require("easy-dotnet.default-manager").try_get_cache_file(value)
    if file then
      return value
    end
  end
end

M.find_solution_file = function(no_cache)
  local files = M.get_solutions()
  local opts = {}
  for _, value in ipairs(files) do
    local file = require("easy-dotnet.default-manager").try_get_cache_file(value)
    if file and not no_cache then
      return value
    end
    table.insert(opts, { display = value, ordinal = value, value = value })
  end
  if #opts == 0 then
    return nil
  end
  local selection = require("easy-dotnet.picker").pick_sync(nil, opts, "Pick solution file")
  return selection and selection.value or nil
end

return M
