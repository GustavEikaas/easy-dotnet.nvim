local extensions = require "easy-dotnet.extensions"
local M = {}

-- Generates a relative path from cwd to the project.csproj file
local function generate_relative_path_for_project(path, slnpath)
  return slnpath:gsub("([^\\/]+)%.sln$", "") .. path
end

M.get_projects_from_sln = function(solutionFilePath)
  local file = io.open(solutionFilePath, "r")

  if not file then
    -- require("easy-dotnet.debug").write_to_log("Failed to open solution file: " .. solutionFilePath)
    error("Failed to open file " .. solutionFilePath)
  end
  local regexp = 'Project%("{(.-)}"%).*= "(.-)", "(.-)", "{.-}"'

  local projectLines = extensions.filter(file:lines(), function(line)
    local id, name, path = line:match(regexp)
    if id and name and path then
      return true
    end
    return false
  end)

  local projects = extensions.map(projectLines, function(line)
    local id, name, path = line:match(regexp)
    local project_file_path = generate_relative_path_for_project(path, solutionFilePath)
    return {
      display = name,
      name = name,
      path = project_file_path,
      id = id,
      runnable = M.is_web_project(project_file_path),
      secrets = M.has_secrets(project_file_path)
    }
  end)
  file:close()
  return projects
end

M.has_secrets = function(project_file_path)
  if string.find(project_file_path, "%.") == nil then
    return false
  end
  local pattern = "<UserSecretsId>([a-fA-F0-9%-]+)</UserSecretsId>"
  local file = io.open(project_file_path, "r")
  if not file then
    -- require("easy-dotnet.debug").write_to_log("Failed to open project file: " .. project_file_path)
    return false, "File not found or cannot be opened"
  end

  local contains_secrets = extensions.find(file:lines(), function(line)
    local value = line:match(pattern)
    if value then
      return true
    end
    return false
  end)

  return (contains_secrets and contains_secrets:match(pattern)) or false
end

M.is_web_project = function(project_file_path)
  if string.find(project_file_path, "%.") == nil then
    return false
  end

  local file = io.open(project_file_path, "r")
  if not file then
    -- require("easy-dotnet.debug").write_to_log("Failed to open project file: " .. project_file_path)
    vim.notify("Failed to open project file " .. project_file_path)
    return false, "File not found or cannot be opened"
  end

  local contains_sdk_web = extensions.any(file:lines(),
    function(line) return line:find('<Project%s+Sdk="Microsoft.NET.Sdk.Web"') end)

  file:close()

  return contains_sdk_web
end

M.find_solution_file = function()
  local file = require("plenary.scandir").scan_dir({ "." }, { search_pattern = "%.sln$", depth = 3 })
  return file[1]
end

return M
