local polyfills = require("easy-dotnet.polyfills")
local logger = require("easy-dotnet.logger")
local M = {}

---@class MsbuildProperties
---@field outputPath string | nil Normalized path to the build output directory (e.g., "bin/Debug/net9.0/")
---@field outputType string | nil Type of output, typically "Exe" or "Library"
---@field targetExt string | nil File extension of the built output (e.g., ".dll")
---@field assemblyName string | nil The name of the resulting assembly
---@field targetFramework string | nil The target framework moniker (e.g., "net9.0")
---@field targetFrameworks string[] | nil The target framework list [net9.0,net8.0]
---@field isTestProject boolean Whether the project is a test project ("true"/"false")
---@field userSecretsId string | nil The GUID used for User Secrets configuration
---@field testingPlatformDotnetTestSupport boolean Custom property, likely used by test tooling
---@field targetPath string | nil Full path to the built output artifact
---@field version string | nil TargetVersion without net (e.g '8.0')
---@field isMultiTarget boolean Does it target multiple versions

local msbuild_properties = {
  "OutputPath",
  "OutputType",
  "TargetExt",
  "AssemblyName",
  "TargetFramework",
  "TargetFrameworks",
  "IsTestProject",
  "UserSecretsId",
  "TestingPlatformDotnetTestSupport",
  "TargetPath",
}

---@param project_path string path to csproj file
---@param target_framework string | nil which target framework to query for e.g 'net9.0'
---@return string
local function build_msbuild_command(project_path, target_framework)
  local cmd = { "dotnet", "msbuild", vim.fn.shellescape(project_path) }
  for _, prop in ipairs(msbuild_properties) do
    table.insert(cmd, ("-getProperty:%s"):format(prop))
  end
  if target_framework then table.insert(cmd, "-p:TargetFramework=" .. target_framework) end

  return table.concat(cmd, " ")
end

local function normalized_path_or_nil(val) return val and vim.fs.normalize(val) or val end

---@param val string
---@return string | nil
local function empty_string_to_nil(val) return val ~= "" and val or nil end

local function string_to_boolean(val) return val == "true" and true or false end

---@return MsbuildProperties
local parse_msbuild_properties = function(output)
  local ok, result = pcall(vim.fn.json_decode, output)
  if not ok or not result or not result.Properties then error("Failed to parse msbuild output: " .. tostring(output)) end

  local raw = result.Properties

  ---@type MsbuildProperties
  return {
    outputPath = normalized_path_or_nil(empty_string_to_nil(raw.OutputPath)),
    outputType = empty_string_to_nil(raw.OutputType),
    userSecretsId = empty_string_to_nil(raw.UserSecretsId),
    assemblyName = empty_string_to_nil(raw.AssemblyName),
    targetPath = normalized_path_or_nil(empty_string_to_nil(raw.TargetPath)),
    isTestProject = string_to_boolean(raw.IsTestProject),
    testingPlatformDotnetTestSupport = string_to_boolean(raw.TestingPlatformDotnetTestSupport),
    version = raw.TargetFramework ~= nil and raw.TargetFramework:gsub("%net", "") or nil,
    targetExt = empty_string_to_nil(raw.TargetExt),
    targetFramework = empty_string_to_nil(raw.TargetFramework),
    targetFrameworks = raw.TargetFrameworks ~= "" and vim.split(raw.TargetFrameworks, ";") or nil,
    isMultiTarget = raw.TargetFrameworks ~= "",
  }
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
---@field msbuild_props MsbuildProperties
---@field get_specific_runtime_definition fun(target_framework: string): DotnetProject
---@field get_all_runtime_definitions fun(): DotnetProject[]
---@field type 'project' | 'project_framework'

---@class DotnetProjectFramework
---@field display string
---@field version string
---@field type 'project_framework'
---@field msbuild_props MsbuildProperties
---@field get_dll_path function

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

---@param project_file_path string
---@param target_framework string | nil which target framework to query for e.g 'net9.0'
local function build_cache_key(project_file_path, target_framework) return target_framework and string.format("%s@%s", project_file_path, target_framework) or project_file_path end

--- Build and cache MSBuild properties for a project file
---@param project_file_path string
---@param target_framework string | nil which target framework to query for e.g 'net9.0'
---@param on_finished fun(props: MsbuildProperties)? optional callback
function M.preload_msbuild_properties(project_file_path, on_finished, target_framework)
  assert(project_file_path, "Project file path cannot be nil")
  local cache_key = build_cache_key(project_file_path, target_framework)
  local maybe_cached = msbuild_cache[cache_key]
  if maybe_cached ~= nil then
    if on_finished and type(maybe_cached) ~= "number" then
      ---@cast maybe_cached MsbuildProperties
      on_finished(maybe_cached)
    end
    return
  end

  local ext = vim.fn.fnamemodify(project_file_path, ":e"):lower()
  if ext ~= "csproj" and ext ~= "fsproj" then error(project_file_path .. " is not a known project file") end

  local command = build_msbuild_command(project_file_path, target_framework)
  local stdout = ""

  local job_id = vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then stdout = table.concat(data, "\n") end
    end,
    on_exit = function()
      local properties = parse_msbuild_properties(stdout)
      msbuild_cache[cache_key] = properties
      if not target_framework and properties.isMultiTarget and #properties.targetFrameworks > 1 then
        for _, tr in ipairs(properties.targetFrameworks) do
          M.preload_msbuild_properties(project_file_path, nil, tr)
        end
      end
      if on_finished then on_finished(properties) end
    end,
  })

  if job_id > 0 then
    msbuild_cache[cache_key] = job_id
  else
    logger.error("Failed to start msbuild job")
  end
end

local function get_or_wait_or_set_cached_value(project_file_path, target_framework)
  local cache_key = build_cache_key(project_file_path, target_framework)
  local cached = msbuild_cache[cache_key]

  if type(cached) == "table" then return cached end

  if type(cached) == "number" then
    vim.fn.jobwait({ cached })
    return msbuild_cache[cache_key]
  end

  if not cached or type(cached) ~= "table" then
    local command = build_msbuild_command(project_file_path, target_framework)
    local output = vim.fn.system(command)
    cached = parse_msbuild_properties(output)
    msbuild_cache[cache_key] = cached
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
  local is_console_project = string.lower(msbuild_props.outputType) == "exe"
  local is_test_project = msbuild_props.isTestProject or M.is_directly_referencing_test_packages(project_file_path)
  local is_test_platform_project = msbuild_props.testingPlatformDotnetTestSupport
  local is_win_project = string.lower(msbuild_props.outputType) == "winexe"
  local maybe_secret_guid = msbuild_props.userSecretsId
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

  ---@type DotnetProject
  local project = {
    display = display,
    path = project_file_path,
    language = language,
    name = name,
    version = version,
    runnable = is_web_project or is_worker_project or is_console_project or is_win_project,
    secrets = maybe_secret_guid,
    --TODO: consolidate method and property, support multi target frameworks where targetPath would be nil
    get_dll_path = function()
      if msbuild_props.isMultiTarget then logger.error("Calling get_dll_path on the root definition of a multi target project is invalid") end
      return msbuild_props.targetPath
    end,
    dll_path = msbuild_props.targetPath,
    isTestProject = is_test_project,
    isTestPlatformProject = is_test_platform_project,
    isConsoleProject = is_console_project,
    isWorkerProject = is_worker_project,
    isWebProject = is_web_project,
    isWinProject = is_win_project,
    msbuild_props = msbuild_props,
    type = "project",
    get_all_runtime_definitions = nil,
    get_specific_runtime_definition = nil,
  }

  ---@param target_framework string specified as e.g net8.0
  ---@return DotnetProjectFramework
  project.get_specific_runtime_definition = function(target_framework)
    if not project.msbuild_props.isMultiTarget then return project end
    --TODO: validate that arg is a valid targetFramework on the project
    local msbuild_target_framework_props = get_or_wait_or_set_cached_value(project_file_path, target_framework)
    local runtime_version = target_framework:gsub("%net", "")
    ---@type DotnetProjectFramework
    local project_framework = {
      display = project.display .. "@" .. runtime_version,
      get_dll_path = function() return msbuild_target_framework_props.targetPath end,
      version = msbuild_target_framework_props.version,
      dll_path = msbuild_target_framework_props.targetPath,
      type = "project_framework",
      ---@type MsbuildProperties
      msbuild_props = {
        targetFramework = target_framework,
      },
    }
    return vim.tbl_deep_extend("keep", project_framework, project)
  end

  project.get_all_runtime_definitions = function()
    if not project.msbuild_props.isMultiTarget then return { project } end
    return vim.tbl_map(function(target) return project.get_specific_runtime_definition(target) end, project.msbuild_props.targetFrameworks)
  end

  project_cache[project_file_path] = project
  return project
end

---@param project_file_path string
---@return boolean
M.is_directly_referencing_test_packages = function(project_file_path)
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

M.find_csproj_file = function()
  local file = require("plenary.scandir").scan_dir({ "." }, { search_pattern = "%.csproj$", depth = 3 })
  return file[1]
end

M.find_fsproj_file = function()
  local file = require("plenary.scandir").scan_dir({ "." }, { search_pattern = "%.fsproj$", depth = 3 })
  return file[1]
end

---Tries to find a csproj or fsproj file
---@return string | nil
M.find_project_file = function() return M.find_csproj_file() or M.find_fsproj_file() end

return M
