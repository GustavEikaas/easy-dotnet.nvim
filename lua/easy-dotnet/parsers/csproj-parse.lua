local extensions = require "easy-dotnet.extensions"
local M = {}

-- Function to find the corresponding .csproj file
M.get_project_from_csproj = function(csproj_file_path)
  local isWebProject = M.is_web_project(csproj_file_path)
  local isConsoleProject = M.is_console_project(csproj_file_path)
  local isTestProject = M.is_test_project(csproj_file_path)
  local maybeSecretGuid = M.try_get_secret_id(csproj_file_path)

  return {
    display = csproj_file_path,
    path = csproj_file_path,
    name = csproj_file_path,
    runnable = isWebProject or isConsoleProject,
    secrets = maybeSecretGuid,

    isTestProject = isTestProject,
    isConsoleProject = isConsoleProject,
    isWebProject = isWebProject
  }
end

M.try_get_secret_id = function(project_file_path)
  local pattern = "<UserSecretsId>([a-fA-F0-9%-]+)</UserSecretsId>"
  local file = io.open(project_file_path, "r")
  if not file then
    return false, "File not found or cannot be opened"
  end

  local contains_secrets = extensions.find(file:lines(), function(line)
    local value = line:match(pattern)
    if value then
      return true
    end
    return false
  end)

  return (type(contains_secrets) == "string" and contains_secrets:match(pattern)) or false
end

-- Used for checking if a specific pattern is present in a file
local function is_in_project_file(project_file_path, pattern)
  local file = io.open(project_file_path, "r")
  if not file then
    return false, "File not found or cannot be opened"
  end

  local contains_output_type = extensions.any(file:lines(),
    function(line) return line:find(pattern) end)

  file:close()

  return contains_output_type
end

M.is_console_project = function(project_file_path)
  return is_in_project_file(project_file_path, '<%s*OutputType%s*>%s*(exe|winexe|library)%s*</%s*OutputType%s*>')
end

M.is_test_project = function(project_file_path)
  return is_in_project_file(project_file_path, '<%s*IsTestProject%s*>%s*true%s*</%s*IsTestProject%s*>')
end

M.is_web_project = function(project_file_path)
  return is_in_project_file(project_file_path, '<Project%s+Sdk="Microsoft.NET.Sdk.Web"')
end


M.find_csproj_file = function()
  local file = require("plenary.scandir").scan_dir({ ".", "./src" }, { search_pattern = "%.csproj$", depth = 3 })
  return file[1]
end

return M
