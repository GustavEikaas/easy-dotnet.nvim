local polyfills = require("easy-dotnet.polyfills")
local logger = require("easy-dotnet.logger")
local M = {}

---@class DotnetProject
---@field language "csharp" | "fsharp"
---@field display string
---@field path string
---@field name string
---@field version string|nil
---@field runnable boolean
---@field secrets string
---@field get_dll_path function
---@field isTestProject boolean
---@field isConsoleProject boolean
---@field isWebProject boolean
---@field isWorkerProject boolean
---@field isWinProject boolean

--- Extracts a pattern from a file
---@param project_file_path string
---@param pattern string
---@return string | false
local function extract_from_project(project_file_path, pattern)
  if project_file_path == nil then return false end

  local file = io.open(project_file_path, "r")
  if not file then return false end
  local contains_pattern = polyfills.iter(file:lines()):find(function(line)
    local value = line:match(pattern)
    if value then return true end
    return false
  end)

  local result = (type(contains_pattern) == "string" and contains_pattern:match(pattern)) or false

  file:close()
  return result
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
    logger.error("Command failed")
    return {}
  end
  return projects
end

---Extracts the project name from a path
---@param path string
---@return string
local function extractProjectName(path)
  local filename = path:match("[^/\\]+%.%a+proj")
  if filename == nil then return "Unknown" end
  return filename:gsub("%.csproj$", ""):gsub("%.fsproj$", "")
end

---@type table<string, DotnetProject>
local project_cache = {}

-- Get the project definition from a csproj/fsproj file
---@param project_file_path string
---@return DotnetProject
M.get_project_from_project_file = function(project_file_path)
  local maybeCacheObject = project_cache[project_file_path]
  if maybeCacheObject then return maybeCacheObject end
  local display = extractProjectName(project_file_path)
  local name = display
  local language = project_file_path:match("%.csproj$") and "csharp" or project_file_path:match("%.fsproj$") and "fsharp" or "unknown"
  local isWebProject = M.is_web_project(project_file_path)
  local isWorkerProject = M.is_worker_project(project_file_path)
  local isConsoleProject = M.is_console_project(project_file_path)
  local isTestProject = M.is_test_project(project_file_path)
  local isWinProject = M.is_win_project(project_file_path)
  local maybeSecretGuid = M.try_get_secret_id(project_file_path)
  local version = M.extract_version(project_file_path)

  if version then display = display .. "@" .. version end

  if language == "csharp" then
    display = display .. " 󰙱"
  elseif language == "fsharp" then
    display = display .. " 󰫳"
  end

  if isTestProject then display = display .. " 󰙨" end
  if maybeSecretGuid then display = display .. " " end
  if isWebProject then display = display .. " 󱂛" end
  if isConsoleProject then display = display .. " 󰆍" end
  if isWorkerProject then display = display .. " " end
  if isWinProject then display = display .. " " end

  local project = {
    display = display,
    path = project_file_path,
    language = language,
    name = name,
    version = version,
    runnable = isWebProject or isWorkerProject or isConsoleProject or isWinProject,
    secrets = maybeSecretGuid,
    get_dll_path = function()
      local c = project_cache[project_file_path]
      if c and c.dll_path then return c.dll_path end
      local value = vim.fn.json_decode(
        vim.fn.system(string.format("dotnet msbuild %s -getProperty:OutputPath -getProperty:TargetExt -getProperty:AssemblyName -getProperty:TargetFramework", project_file_path))
      ).Properties
      local target = string.format("%s%s", value.AssemblyName, value.TargetExt)
      local path = polyfills.fs.joinpath(vim.fs.dirname(project_file_path), value.OutputPath:gsub("\\", "/"), target)
      local msbuild_target_framework = value.TargetFramework:gsub("%net", "")

      c["version"] = msbuild_target_framework
      c["dll_path"] = path
      return path
    end,
    isTestProject = isTestProject,
    isConsoleProject = isConsoleProject,
    isWorkerProject = isWorkerProject,
    isWebProject = isWebProject,
    isWinProject = isWinProject,
  }

  project_cache[project_file_path] = project
  if version then project_cache[project_file_path].dll_path = polyfills.fs.joinpath(vim.fs.dirname(project_file_path), "bin", "Debug", "net" .. version, name .. ".dll") end

  return project
end

M.extract_version = function(project_file_path)
  local version = extract_from_project(project_file_path, "<TargetFramework>net(.-)</TargetFramework>")
  if version == false then return nil end
  return version
end

M.try_get_secret_id = function(project_file_path)
  local secret = extract_from_project(project_file_path, "<UserSecretsId>([a-fA-F0-9%-]+)</UserSecretsId>")
  if secret == false then return nil end
  return secret
end

M.is_console_project = function(project_file_path) return type(extract_from_project(project_file_path, "<OutputType>%s*Exe%s*</OutputType>")) == "string" end

M.is_test_project = function(project_file_path)
  if type(extract_from_project(project_file_path, "<%s*IsTestProject%s*>%s*true%s*</%s*IsTestProject%s*>")) == "string" then return true end

  -- Check for test-related package references
  local test_packages = {
    "Microsoft%.NET%.Test%.Sdk",
    "MSTest%.TestFramework",
    "NUnit",
    "xunit",
  }

  for _, package in ipairs(test_packages) do
    local pattern = string.format('<PackageReference Include="%s"%%s*', package)
    if type(extract_from_project(project_file_path, pattern)) == "string" then return true end
  end

  return false
end

M.is_web_project = function(project_file_path) return type(extract_from_project(project_file_path, '<Project%s+Sdk="Microsoft.NET.Sdk.Web"')) == "string" end

M.is_worker_project = function(project_file_path) return type(extract_from_project(project_file_path, '<Project%s+Sdk="Microsoft.NET.Sdk.Worker"')) == "string" end

M.is_win_project = function(project_file_path) return type(extract_from_project(project_file_path, "<OutputType>WinExe</OutputType>")) == "string" end

M.find_csproj_file = function()
  local file = require("plenary.scandir").scan_dir({ "." }, { search_pattern = "%.csproj$", depth = 3 })
  return file[1]
end

M.find_fsproj_file = function()
  local file = require("plenary.scandir").scan_dir({ "." }, { search_pattern = "%.fsproj$", depth = 3 })
  return file[1]
end

---Tries to find a csproj or fsproj file
M.find_project_file = function() return M.find_csproj_file() or M.find_fsproj_file() end

return M
