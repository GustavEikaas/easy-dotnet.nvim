local polyfills = require("easy-dotnet.polyfills")
local logger = require("easy-dotnet.logger")
local M = {}

---@class MsbuildProperties
---@field outputPath string | nil Path to the build output directory (e.g., "bin\\Debug\\net9.0\\")
---@field outputType string | nil Type of output, typically "Exe" or "Library"
---@field targetExt string | nil File extension of the built output (e.g., ".dll")
---@field assemblyName string | nil The name of the resulting assembly
---@field targetFramework string | nil The target framework moniker (e.g., "net9.0")
---@field isTestProject boolean Whether the project is a test project ("true"/"false")
---@field userSecretsId string | nil The GUID used for User Secrets configuration
---@field testingPlatformDotnetTestSupport boolean Custom property, likely used by test tooling
---@field targetPath string Full path to the built output artifact
---@field version string | nil TargetVersion without net (e.g '8.0')

local msbuild_properties = {
  "OutputPath",
  "OutputType",
  "TargetExt",
  "AssemblyName",
  "TargetFramework",
  "IsTestProject",
  "UserSecretsId",
  "ProjectSdk",
  "TestingPlatformDotnetTestSupport",
  "TargetPath",
}

local function build_msbuild_command(project_path)
  local cmd = { "dotnet", "msbuild" }
  for _, prop in ipairs(msbuild_properties) do
    table.insert(cmd, ("-getProperty:%s"):format(prop))
  end
  table.insert(cmd, project_path)

  return cmd
end

---@param val string
---@return string | nil
local function empty_string_to_nil(val) return val ~= "" and val or nil end

local function string_to_boolean(val) return val == "true" and true or false end

---@return MsbuildProperties
local parse_msbuild_properties = function(output, project_name)
  vim.print(output)
  local result = vim.fn.json_decode(output)

  local raw = result[string.lower(project_name)]

  ---@type MsbuildProperties
  return raw
  -- return {
  --   outputPath = empty_string_to_nil(raw.OutputPath),
  --   outputType = empty_string_to_nil(raw.OutputType),
  --   userSecretsId = empty_string_to_nil(raw.UserSecretsId),
  --   assemblyName = empty_string_to_nil(raw.AssemblyName),
  --   targetPath = raw.TargetPath,
  --   isTestProject = string_to_boolean(raw.IsTestProject),
  --   testingPlatformDotnetTestSupport = string_to_boolean(raw.TestingPlatformDotnetTestSupport),
  --   version = raw.TargetFramework:gsub("%net", ""),
  --   targetExt = empty_string_to_nil(raw.TargetExt),
  --   targetFramework = empty_string_to_nil(raw.TargetFramework),
  -- }
end

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
---@field isTestPlatformProject boolean
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
---@type table<string, MsbuildProperties | integer>
local msbuild_cache = {}

--- Build and cache MSBuild properties for a project file
---@param project_file_path string
---@param on_finished fun(props: MsbuildProperties)? optional callback
function M.preload_msbuild_properties(project_file_path, on_finished)
  local maybe_cached = msbuild_cache[project_file_path]
  if maybe_cached ~= nil then
    if on_finished and type(maybe_cached) ~= "number" then
      ---@cast maybe_cached MsbuildProperties
      on_finished(maybe_cached)
    end
    return
  end

  local fullPath = vim.fs.joinpath(vim.fs.normalize(vim.fn.getcwd()), project_file_path)
  print(fullPath)
  local command = {
    'dotnet',
    'run',
    '--project',
    'C:/Users/Gustav/repo/msbuild-scanner/src/msbuild-scanner.MsbuildScanner/msbuild-scanner.MsbuildScanner.fsproj',
    '--framework',
    'net8.0',
    fullPath
  }
  -- local command = build_msbuild_command(project_file_path)
  local stdout = ""

  local job_id = vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then stdout = table.concat(data, "\n") end
    end,
    on_exit = function()
      local properties = parse_msbuild_properties(stdout, vim.fs.basename(project_file_path))
      msbuild_cache[project_file_path] = properties
      if on_finished then on_finished(properties) end
    end,
  })

  if job_id > 0 then
    msbuild_cache[project_file_path] = job_id
  else
    logger.error("Failed to start msbuild job")
  end
end

local function get_or_wait_or_set_cached_value(project_file_path)
  local cached = msbuild_cache[project_file_path]

  if type(cached) == "table" then
    -- print("Returning cached value for " .. project_file_path)
    return cached
  end

  if type(cached) == "number" then
    -- print("Awaiting cached value for " .. project_file_path)
    vim.fn.jobwait({ cached })
    return msbuild_cache[project_file_path]
  end

  if not cached or type(cached) ~= "table" then
    local command = build_msbuild_command(project_file_path)
    -- print("Forcing value for " .. project_file_path)
    local output = vim.fn.system(command)
    cached = parse_msbuild_properties(output, vim.fs.basename(project_file_path))
    msbuild_cache[project_file_path] = cached
    return cached
  end
end

-- Get the project definition from a csproj/fsproj file
---@param project_file_path string
---@return DotnetProject
M.get_project_from_project_file = function(project_file_path)
  local msbuild_props = get_or_wait_or_set_cached_value(project_file_path)

  local maybe_cache_object = project_cache[project_file_path]
  if maybe_cache_object then return maybe_cache_object end
  local display = extractProjectName(project_file_path)
  local name = display
  local language = project_file_path:match("%.csproj$") and "csharp" or project_file_path:match("%.fsproj$") and "fsharp" or "unknown"
  local is_web_project = M.is_web_project(project_file_path)
  local is_worker_project = M.is_worker_project(project_file_path)
  local is_console_project = M.is_console_project(project_file_path)
  local is_test_project = msbuild_props.isTestProject or M.is_test_project(project_file_path)
  local is_test_platform_project = M.is_test_platform_project(msbuild_props)
  local is_win_project = M.is_win_project(msbuild_props)
  local maybe_secret_guid = M.try_get_secret_id(msbuild_props)
  local version = msbuild_props.version

  if version then display = display .. "@" .. version end

  if language == "csharp" then
    display = display .. " 󰙱"
  elseif language == "fsharp" then
    display = display .. " 󰫳"
  end

  if is_test_project then display = display .. " 󰙨" end
  if maybe_secret_guid then display = display .. " " end
  if is_web_project then display = display .. " 󱂛" end
  if is_console_project then display = display .. " 󰆍" end
  if is_worker_project then display = display .. " " end
  if is_win_project then display = display .. " " end

  local project = {
    display = display,
    path = project_file_path,
    language = language,
    name = name,
    version = version,
    runnable = is_web_project or is_worker_project or is_console_project or is_win_project,
    secrets = maybe_secret_guid,
    get_dll_path = function()
      return msbuild_props.targetPath
      -- local c = project_cache[project_file_path]
      -- if c and c.dll_path then return c.dll_path end
      -- local value = vim.fn.json_decode(
      --   vim.fn.system(string.format("dotnet msbuild %s -getProperty:OutputPath -getProperty:TargetExt -getProperty:AssemblyName -getProperty:TargetFramework", project_file_path))
      -- ).Properties
      -- local target = string.format("%s%s", value.AssemblyName, value.TargetExt)
      -- local path = polyfills.fs.joinpath(vim.fs.dirname(project_file_path), value.OutputPath:gsub("\\", "/"), target)
      -- local msbuild_target_framework = value.TargetFramework:gsub("%net", "")
      --
      -- c["version"] = msbuild_target_framework
      -- c["dll_path"] = path
      -- return path
    end,
    dll_path = msbuild_props.targetPath,
    isTestProject = is_test_project,
    isTestPlatformProject = is_test_platform_project,
    isConsoleProject = is_console_project,
    isWorkerProject = is_worker_project,
    isWebProject = is_web_project,
    isWinProject = is_win_project,
  }

  project_cache[project_file_path] = project
  -- if version then project_cache[project_file_path].dll_path = polyfills.fs.joinpath(vim.fs.dirname(project_file_path), "bin", "Debug", "net" .. version, name .. ".dll") end
  return project
end

---@param props MsbuildProperties
---@return string | nil
M.try_get_secret_id = function(props) return props.userSecretsId end

---@param project_file_path string
---@return boolean
M.is_console_project = function(project_file_path) return type(extract_from_project(project_file_path, "<OutputType>%s*Exe%s*</OutputType>")) == "string" end

---@param props MsbuildProperties
---@return boolean
M.is_test_platform_project = function(props) return props.testingPlatformDotnetTestSupport end

---@param project_file_path string
---@return boolean
M.is_test_project = function(project_file_path)
  --TODO: this should check both msbuild properties and dotnet package list
  local patterns = {
    "<%s*IsTestProject%s*>%s*true%s*</%s*IsTestProject%s*>",
    "<%s*TestingPlatformDotnetTestSupport%s*>%s*true%s*</%s*TestingPlatformDotnetTestSupport%s*>",
    "<%s*UseMicrosoftTestingPlatformRunner%s*>%s*true%s*</%s*UseMicrosoftTestingPlatformRunner%s*>",
  }
  for _, pattern in ipairs(patterns) do
    if type(extract_from_project(project_file_path, pattern)) == "string" then return true end
  end

  -- Check for test-related package references
  local test_packages = {
    "Microsoft%.NET%.Test%.Sdk",
    "MSTest%.TestFramework",
    "Microsoft.Testing.Platform.MSBuild",
    "NUnit",
    "xunit",
    "xunit.v3",
    "TUnit.Assertions",
    "TUnit",
  }

  for _, package in ipairs(test_packages) do
    local pattern = string.format('<PackageReference Include="%s"%%s*', package)
    if type(extract_from_project(project_file_path, pattern)) == "string" then return true end
  end

  return false
end

---@param project_file_path string
---@return boolean
M.is_web_project = function(project_file_path) return type(extract_from_project(project_file_path, '<Project%s+Sdk="Microsoft.NET.Sdk.Web"')) == "string" end

---@param project_file_path string
---@return boolean
M.is_worker_project = function(project_file_path) return type(extract_from_project(project_file_path, '<Project%s+Sdk="Microsoft.NET.Sdk.Worker"')) == "string" end

---@param props MsbuildProperties
---@return boolean
M.is_win_project = function(props) return props.outputType == "WinExe" end

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
