local extensions = require "easy-dotnet.extensions"
local M = {}

---@class DotnetProject
---@field language "csharp" | "fsharp"
---@field display string
---@field path string
---@field name string
---@field version string
---@field runnable boolean
---@field secrets string
---@field bin_path string
---@field dll_path string
---@field isTestProject boolean
---@field isConsoleProject boolean
---@field isWebProject boolean

--- Extracts a pattern from a file
---@param project_file_path string
---@param pattern string
---@return string | false
local function extract_from_project(project_file_path, pattern)
  if project_file_path == nil then
    return false
  end

  local file = io.open(project_file_path, "r")
  if not file then
    return false
  end

  local contains_pattern = extensions.find(file:lines(), function(line)
    local value = line:match(pattern)
    if value then
      return true
    end
    return false
  end)

  return (type(contains_pattern) == "string" and contains_pattern:match(pattern)) or false
end

M.get_project_references_from_projects = function(project_path)
  local projects = {}
  local output = vim.fn.systemlist(string.format("dotnet list %s reference", project_path))

  for _, line in ipairs(output) do
    line = line:gsub("\\", "/")
    local filename = line:match("[^/\\]+%.%a+proj")
    if filename ~= nil then
      local project_name = filename:gsub("%.csproj$", ""):gsub("%.fsproj$", "")
      table.insert(projects, project_name)
    end
  end

  local exit_code = vim.v.shell_error
  if exit_code ~= 0 then
    vim.notify("Command failed")
    return {}
  end
  return projects
end

---Extracts the project name from a path
---@param path string
---@return string
local function extractProjectName(path)
  local filename = path:match("[^/\\]+%.%a+proj")
  if filename == nil then
    return "Unknown"
  end
  return filename:gsub("%.csproj$", ""):gsub("%.fsproj$", "")
end

local function get_version_from_build_props(starting_directory)
  local current_directory = starting_directory

  while current_directory do
    local build_props_path = current_directory .. "/Directory.Build.props"
    local sdk_version = M.extract_version(build_props_path)
    if sdk_version then
      return sdk_version
    end

    current_directory = current_directory:match("(.*/)")
  end

  return nil
end

local function extract_import_props(csproj_path)
  local imports = {}
  local pattern = '<Import%s+Project%s*=%s*"[%.%\\%/]+[%w_%-%.%/]+%.props"%s*/>'
  local file = io.open(csproj_path, "r")
  if not file then
    print("Failed to open file: " .. csproj_path)
    return nil
  end

  for line in file:lines() do
    local match = line:match(pattern)
    if match then
      local project_path = line:match('Project%s*=%s*"([%.%\\%/]+[%w_%-%.%/]+%.props)"')
      if project_path then
        local normalized_path = project_path:gsub("\\", "/")
        table.insert(imports, normalized_path)
      end
    end
  end

  file:close()

  return imports
end


local function get_version_from_props(csproj_path)
  local imports = extract_import_props(csproj_path)
  if not imports then
    return nil
  end
  for _, value in ipairs(imports) do
    local version = M.extract_version(vim.fs.joinpath(vim.fs.dirname(csproj_path), value))
    if version then
      return version
    end
  end
  return nil
end

-- Get the project definition from a csproj/fsproj file
---@param project_file_path string
---@return DotnetProject
M.get_project_from_project_file = function(project_file_path)
  local display = extractProjectName(project_file_path)
  local name = display
  local language = project_file_path:match("%.csproj$") and "csharp" or project_file_path:match("%.fsproj$") and "fsharp" or
      "unknown"
  local isWebProject = M.is_web_project(project_file_path)
  local isConsoleProject = M.is_console_project(project_file_path)
  local isTestProject = M.is_test_project(project_file_path)
  local maybeSecretGuid = M.try_get_secret_id(project_file_path)
  local version = M.extract_version(project_file_path) or get_version_from_props(project_file_path) or
      get_version_from_build_props(vim.fs.dirname(project_file_path))

  local bin_path = vim.fs.joinpath(vim.fs.dirname(project_file_path), "bin", "Debug", "net" .. version)
  local dll_path = vim.fs.joinpath(bin_path, name .. ".dll")

  if version and version ~= false then
    display = display .. "@" .. version
  end

  if language == "csharp" then
    display = display .. " 󰙱"
  elseif language == "fsharp" then
    display = display .. " 󰫳"
  end

  if isTestProject then
    display = display .. " 󰙨"
  end
  if maybeSecretGuid then
    display = display .. " "
  end
  if isWebProject then
    display = display .. " 󱂛"
  end
  if isConsoleProject then
    display = display .. " 󰆍"
  end

  return {
    display = display,
    path = project_file_path,
    language = language,
    name = name,
    version = version,
    runnable = isWebProject or isConsoleProject,
    secrets = maybeSecretGuid,
    bin_path = bin_path,
    dll_path = dll_path,
    isTestProject = isTestProject,
    isConsoleProject = isConsoleProject,
    isWebProject = isWebProject
  }
end

M.extract_version = function(project_file_path)
  return extract_from_project(project_file_path, "<TargetFramework>net(.-)</TargetFramework>")
end

M.try_get_secret_id = function(project_file_path)
  return extract_from_project(project_file_path, "<UserSecretsId>([a-fA-F0-9%-]+)</UserSecretsId>")
end

M.is_console_project = function(project_file_path)
  return type(extract_from_project(project_file_path, "<OutputType>%s*Exe%s*</OutputType>")) ==
      "string"
end

M.is_test_project = function(project_file_path)
  if type(extract_from_project(project_file_path, '<%s*IsTestProject%s*>%s*true%s*</%s*IsTestProject%s*>')) == "string" then
    return true
  end
  if type(extract_from_project(project_file_path, '<PackageReference Include="Microsoft%.NET%.Test%.Sdk" Version=".-" />')) == "string" then
    return true
  end
  if type(extract_from_project(project_file_path, '<PackageReference Include="MSTest%.TestFramework" Version=".-" />')) == "string" then
    return true
  end
  if type(extract_from_project(project_file_path, '<PackageReference Include="NUnit" Version=".-" />')) == "string" then
    return true
  end
  if type(extract_from_project(project_file_path, '<PackageReference Include="xunit" Version=".-" />')) == "string" then
    return true
  end

  return false
end

M.is_web_project = function(project_file_path)
  return type(extract_from_project(project_file_path, '<Project%s+Sdk="Microsoft.NET.Sdk.Web"')) == "string"
end


M.find_csproj_file = function()
  local file = require("plenary.scandir").scan_dir({ "." }, { search_pattern = "%.csproj$", depth = 3 })
  return file[1]
end

M.find_fsproj_file = function()
  local file = require("plenary.scandir").scan_dir({ "." }, { search_pattern = "%.fsproj$", depth = 3 })
  return file[1]
end

---Tries to find a csproj or fsproj file
M.find_project_file = function()
  return M.find_csproj_file() or M.find_fsproj_file()
end

return M
