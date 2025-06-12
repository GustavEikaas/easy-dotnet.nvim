local file_cache = require("easy-dotnet.modules.file-cache")
local logger = require("easy-dotnet.logger")
local M = {}

---@class MsbuildNetFramework
---@field use_iis_express boolean | nil Whether IIS Express is used (specific to .NET Framework projects)

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
---@field net_framework MsbuildNetFramework | nil .NET Framework-specific properties
---@field packageId string | nil Nuget package id
---@field generatePackageOnBuild boolean Whether to generate nuget package on build
---@field is_packable boolean is nuget package
---@field nuget_version string | nil nuget package version

local msbuild_properties_shared = {
  "OutputPath",
  "OutputType",
  "TargetExt",
  "AssemblyName",
  "TargetPath",
  "IsTestProject",
}

local msbuild_properties_framework = vim.list_extend({
  "TargetFrameworkVersion",
  "UseIISExpress",
}, msbuild_properties_shared)

local msbuild_properties_core = vim.list_extend({
  "TargetFramework",
  "TargetFrameworks",
  "GeneratePackageOnBuild",
  "IsPackable",
  "PackageId",
  "Version",
  "PackageOutputPath",
  "UserSecretsId",
  "TestingPlatformDotnetTestSupport",
}, msbuild_properties_shared)

---@param project_path string path to csproj file
---@return string
local function build_msbuild_command_framework(project_path)
  local cmd = { "msbuild", vim.fn.shellescape(project_path) }
  for _, prop in ipairs(msbuild_properties_framework) do
    table.insert(cmd, ("-getProperty:%s"):format(prop))
  end

  return table.concat(cmd, " ")
end

---@param project_path string path to csproj file
---@param target_framework string | nil which target framework to query for e.g 'net9.0'
---@return string
local function build_msbuild_command_core(project_path, target_framework)
  local cmd = { "dotnet", "msbuild", vim.fn.shellescape(project_path) }
  for _, prop in ipairs(msbuild_properties_core) do
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
  local target_framework = raw.TargetFramework or raw.TargetFrameworkVersion

  ---@type MsbuildProperties
  return {
    outputPath = normalized_path_or_nil(empty_string_to_nil(raw.OutputPath)),
    outputType = empty_string_to_nil(raw.OutputType),
    userSecretsId = empty_string_to_nil(raw.UserSecretsId),
    assemblyName = empty_string_to_nil(raw.AssemblyName),
    targetPath = normalized_path_or_nil(empty_string_to_nil(raw.TargetPath)),
    generatePackageOnBuild = string_to_boolean(raw.GeneratePackageOnBuild),
    packageId = empty_string_to_nil(raw.PackageId),
    is_packable = string_to_boolean(raw.IsPackable),
    nuget_version = empty_string_to_nil(raw.Version),
    packagePath = empty_string_to_nil(raw.PackageOutputPath),
    isTestProject = string_to_boolean(raw.IsTestProject),
    testingPlatformDotnetTestSupport = string_to_boolean(raw.TestingPlatformDotnetTestSupport),
    version = target_framework ~= nil and target_framework:gsub("%net", "") or nil,
    targetExt = empty_string_to_nil(raw.TargetExt),
    targetFramework = empty_string_to_nil(target_framework),
    targetFrameworks = (raw.TargetFrameworks ~= "" and raw.TargetFrameworks ~= nil) and vim.split(raw.TargetFrameworks, ";") or {},
    isMultiTarget = raw.TargetFrameworks ~= "" and raw.TargetFrameworks ~= nil,
    net_framework = {
      use_iis_express = string_to_boolean(raw.UseIISExpress),
    },
  }
end

---@class DotnetProject
---@field language "csharp" | "fsharp"
---@field display string
---@field path string
---@field name string
---@field version string | nil
---@field runnable boolean
---@field secrets string | nil
---@field get_dll_path function
---@field isTestProject boolean
---@field isNugetPackage boolean
---@field isTestPlatformProject boolean
---@field isConsoleProject boolean
---@field isWebProject boolean
---@field isWorkerProject boolean
---@field isWinProject boolean
---@field msbuild_props MsbuildProperties
---@field get_specific_runtime_definition fun(target_framework: string): DotnetProject
---@field get_all_runtime_definitions fun(): DotnetProject[]
---@field is_net_framework boolean
---@field type 'project' | 'project_framework'

---@class DotnetProjectFramework
---@field display string
---@field version string
---@field type 'project_framework'
---@field msbuild_props MsbuildProperties
---@field get_dll_path function

--- Extracts a pattern from an array of lines
---@param lines string[] Array of lines from a file
---@param pattern string Lua pattern to extract
---@return boolean
local function extract_from_lines(lines, pattern)
  if not lines or type(lines) ~= "table" then return false end

  for _, line in ipairs(lines) do
    local match = line:match(pattern)
    if match then return true end
  end

  return false
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
local function extract_project_name(path)
  local filename = vim.fs.basename(path)
  if filename == nil then return "Unknown" end
  local name = filename:gsub("%.csproj$", ""):gsub("%.fsproj$", "")
  return name
end

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
  local lines = vim.fn.readfile(project_file_path)
  local is_net_framework = M.is_dotnet_framework_project(lines)
  local cache_key = build_cache_key(project_file_path, target_framework)
  local maybe_cached = msbuild_cache[cache_key]
  if maybe_cached ~= nil then
    if on_finished and type(maybe_cached) ~= "number" then
      ---@cast maybe_cached MsbuildProperties
      on_finished(maybe_cached)
      return
    elseif type(maybe_cached) == "number" then
      vim.fn.jobwait({ maybe_cached })

      local resolved = msbuild_cache[cache_key]
      if not resolved or type(resolved) == "number" then error("Did wait for " .. cache_key .. " but value is still nil") end
      if on_finished and type(resolved) == "table" then on_finished(resolved) end
    end
  end

  local ext = vim.fn.fnamemodify(project_file_path, ":e"):lower()
  if ext ~= "csproj" and ext ~= "fsproj" then error(project_file_path .. " is not a known project file") end

  local command = is_net_framework and build_msbuild_command_framework(project_file_path) or build_msbuild_command_core(project_file_path, target_framework)
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

local function get_or_wait_or_set_cached_value(project_file_path, is_net_framework, target_framework)
  local cache_key = build_cache_key(project_file_path, target_framework)
  local cached = msbuild_cache[cache_key]

  if type(cached) == "table" then return cached end

  if type(cached) == "number" then
    vim.fn.jobwait({ cached })
    return msbuild_cache[cache_key]
  end

  if not cached or type(cached) ~= "table" then
    local command = is_net_framework and build_msbuild_command_framework(project_file_path) or build_msbuild_command_core(project_file_path, target_framework)
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
  local result = file_cache.get(project_file_path, function(lines)
    local is_net_framework = M.is_dotnet_framework_project(lines)
    local msbuild_props = get_or_wait_or_set_cached_value(project_file_path, is_net_framework)
    local display = extract_project_name(project_file_path)
    local name = display
    local language = project_file_path:match("%.csproj$") and "csharp" or project_file_path:match("%.fsproj$") and "fsharp" or "unknown"
    local is_web_project = M.is_web_project(lines)
    local is_worker_project = M.is_worker_project(lines)
    local is_console_project = string.lower(msbuild_props.outputType or "") == "exe"
    local is_test_project = msbuild_props.isTestProject or M.is_directly_referencing_test_packages(lines) or M.is_net_framework_test_project(lines)
    local is_test_platform_project = msbuild_props.testingPlatformDotnetTestSupport
    local is_win_project = string.lower(msbuild_props.outputType or "") == "winexe"
    local is_nuget_package = msbuild_props.generatePackageOnBuild or msbuild_props.is_packable
    local maybe_secret_guid = msbuild_props.userSecretsId
    local version = msbuild_props.version

    if version then display = display .. "@" .. version end

    if language == "csharp" then
      display = display .. " 󰙱"
    elseif language == "fsharp" then
      display = display .. " 󰫳"
    end

    if is_test_project then display = display .. " 󰙨" end
    if is_nuget_package then display = display .. " " end
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
      runnable = is_web_project or is_worker_project or is_console_project or is_win_project or msbuild_props.net_framework.use_iis_express,
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
      isNugetPackage = is_nuget_package,
      isWorkerProject = is_worker_project,
      isWebProject = is_web_project,
      isWinProject = is_win_project,
      is_net_framework = is_net_framework,
      net_framework = msbuild_props.net_framework,
      msbuild_props = msbuild_props,
      type = "project",
      get_all_runtime_definitions = nil,
      get_specific_runtime_definition = nil,
    }

    ---@param target_framework string specified as e.g net8.0
    ---@return DotnetProjectFramework
    project.get_specific_runtime_definition = function(target_framework)
      if project.is_net_framework then return project end
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
      if project.is_net_framework then return { project } end
      if not project.msbuild_props.isMultiTarget then return { project } end
      return vim.tbl_map(function(target) return project.get_specific_runtime_definition(target) end, project.msbuild_props.targetFrameworks)
    end
    return project
  end)

  return result
end

---@param project_file_lines string[]
---@return boolean
M.is_directly_referencing_test_packages = function(project_file_lines)
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
    if extract_from_lines(project_file_lines, pattern) then return true end
  end

  return false
end

---@param project_file_lines string[]
---@return boolean
M.is_dotnet_framework_project = function(project_file_lines)
  return not vim.iter(project_file_lines):any(function(line) return line:match("<Project%s+Sdk=") end)
end

---@param project_file_lines string[]
---@return boolean
M.is_web_project = function(project_file_lines) return extract_from_lines(project_file_lines, '<Project%s+Sdk="Microsoft.NET.Sdk.Web"') end

---@param project_file_lines string[]
---@return boolean
M.is_worker_project = function(project_file_lines) return extract_from_lines(project_file_lines, '<Project%s+Sdk="Microsoft.NET.Sdk.Worker"') end

M.is_net_framework_test_project = function(project_file_lines)
  return extract_from_lines(project_file_lines, [[<Service Include="{B4F97281-0DBD-4835-9ED8-7DFB966E87FF}" />]])
    or extract_from_lines(project_file_lines, [[<ProjectTypeGuids>.*{3AC096D0%-A1C2%-E12C%-1390%-A8335801FDAB}.*</ProjectTypeGuids>]])
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
---@return string | nil
M.find_project_file = function() return M.find_csproj_file() or M.find_fsproj_file() end

return M
