local extensions = require "easy-dotnet.extensions"
local M = {}

-- Generates a relative path from cwd to the project.csproj file
local function generate_relative_path_for_project(path, slnpath)
  return slnpath:gsub("([^\\/]+)%.sln$", "") .. path
end

-- TODO: Investigate using dotnet sln list command
M.get_projects_from_sln = function(solutionFilePath)
  local file = io.open(solutionFilePath, "r")

  if not file then
    error("Failed to open file " .. solutionFilePath)
  end
  local regexp = 'Project%("{(.-)}"%).*= "(.-)", "(.-)", "{.-}"'

  local projectLines = extensions.filter(file:lines(), function(line)
    local id, name, path = line:match(regexp)
    if id and name and path and path:match("%.csproj$") then
      return true
    end
    return false
  end)

  local projects = extensions.map(projectLines, function(line)
    local csproj_parser     = require("easy-dotnet.parsers.csproj-parse")
    local id, name, path    = line:match(regexp)
    local project_file_path = generate_relative_path_for_project(path, solutionFilePath)
    local project           = csproj_parser.get_project_from_csproj(project_file_path)
    return project
  end)
  file:close()
  return projects
end

M.find_solution_file = function()
  local file = require("plenary.scandir").scan_dir({ "." }, { search_pattern = "%.sln$", depth = 3 })
  return file[1]
end

return M
