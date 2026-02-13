local file_cache = require("easy-dotnet.modules.file-cache")
local client = require("easy-dotnet.rpc.rpc").global_rpc_client
local logger = require("easy-dotnet.logger")
local M = {}

---@class easy-dotnet.MSBuild.Properties
---@field outputPath string | nil Normalized path to the build output directory (e.g., "bin/Debug/net9.0/")
---@field outputType string | nil Type of output, typically "Exe" or "Library"
---@field targetExt string | nil File extension of the built output (e.g., ".dll")
---@field assemblyName string | nil The name of the resulting assembly
---@field targetFramework string | nil The target framework moniker (e.g., "net9.0")
---@field targetFrameworks string[] | nil The target framework list [net9.0,net8.0]
---@field isTestProject boolean Whether the project is a test project ("true"/"false")
---@field isTestingPlatformApplication boolean Whether the project is a Microsoft.Testing.Platform test project
---@field userSecretsId string | nil The GUID used for User Secrets configuration
---@field testingPlatformDotnetTestSupport boolean Custom property, likely used by test tooling
---@field targetPath string | nil Full path to the built output artifact
---@field version string | nil TargetVersion without net (e.g '8.0')
---@field isMultiTarget boolean Does it target multiple versions
---@field packageId string | nil Nuget package id
---@field generatePackageOnBuild boolean Whether to generate nuget package on build
---@field isPackable boolean is nuget package
---@field nugetVersion string | nil nuget package version
---@field isWebProject boolean
---@field isWorkerProject boolean
---@field isNetFramework boolean
---@field useIISExpress boolean
---@field projectName string
---@field language "csharp" \ "fsharp" \ "unknown"
---@field runCommand string
---@field buildCommand string
---@field testCommand string

---@class easy-dotnet.Project.Project
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
---@field msbuild_props easy-dotnet.MSBuild.Properties
---@field get_specific_runtime_definition fun(target_framework: string): easy-dotnet.Project.Project
---@field get_all_runtime_definitions fun(): easy-dotnet.Project.Project[]
---@field type 'project' | 'project_framework'

---@class easy-dotnet.Project.Framework
---@field display string
---@field version string
---@field type 'project_framework'
---@field msbuild_props easy-dotnet.MSBuild.Properties
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
  local co = coroutine.running()
  client:initialize(function()
    client.msbuild:msbuild_list_project_reference(project_path, function(projects)
      local project_names = vim.tbl_map(function(i) return vim.fn.fnamemodify(i, ":t:r") end, projects)
      coroutine.resume(co, project_names)
    end)
  end)
  return coroutine.yield()
end

---@type table<string, easy-dotnet.MSBuild.Properties | {pending: true, waiters: fun(MsbuildProperties)[]}>
local msbuild_cache = {}

---@param project_file_path string
---@param target_framework string | nil which target framework to query for e.g 'net9.0'
local function build_cache_key(project_file_path, target_framework) return target_framework and string.format("%s@%s", project_file_path, target_framework) or project_file_path end

--- Build and cache MSBuild properties for a project file
---@param project_file_path string
---@param target_framework string | nil which target framework to query for e.g 'net9.0'
---@param on_finished fun(props: easy-dotnet.MSBuild.Properties)? optional callback
function M.preload_msbuild_properties(project_file_path, on_finished, target_framework)
  assert(project_file_path, "Project file path cannot be nil")
  local cache_key = build_cache_key(project_file_path, target_framework)
  local maybe_cached = msbuild_cache[cache_key]

  if maybe_cached and maybe_cached.pending == nil then
    if on_finished then on_finished(maybe_cached) end
    return
  end

  if maybe_cached and maybe_cached.pending then
    if on_finished then table.insert(maybe_cached.waiters, on_finished) end
    return
  end

  msbuild_cache[cache_key] = { pending = true, waiters = {} }
  if on_finished then table.insert(msbuild_cache[cache_key].waiters, on_finished) end

  client:initialize(function()
    client.msbuild:msbuild_query_properties({ targetPath = project_file_path, targetFramework = target_framework }, function(properties)
      local entry = msbuild_cache[cache_key]
      msbuild_cache[cache_key] = properties

      if not target_framework and properties.isMultiTarget and #properties.targetFrameworks > 1 then
        for _, tr in ipairs(properties.targetFrameworks) do
          M.preload_msbuild_properties(project_file_path, nil, tr)
        end
      end

      for _, cb in ipairs(entry.waiters or {}) do
        cb(properties)
      end
    end)
  end)
end

function M.invalidate(project_file_path, target_framework)
  local cache_key = build_cache_key(project_file_path, target_framework)
  local cached = msbuild_cache[cache_key]
  if type(cached) == "table" then msbuild_cache[cache_key] = nil end
  file_cache.invalidate(project_file_path)
end

--- Coroutine-friendly get: yields until properties are available
---@param project_file_path string
---@param target_framework string|nil
---@return easy-dotnet.MSBuild.Properties
function M.get_or_wait_or_set_cached_value(project_file_path, target_framework)
  local cache_key = build_cache_key(project_file_path, target_framework)
  local cached = msbuild_cache[cache_key]

  if cached and cached.pending == nil then return cached end

  local co = coroutine.running()
  assert(co, "get_or_wait_or_set_cached_value must be called inside a coroutine")

  local function resume_cb(props) coroutine.resume(co, props) end

  if cached and cached.pending then
    table.insert(cached.waiters, resume_cb)
  else
    M.preload_msbuild_properties(project_file_path, resume_cb, target_framework)
  end

  return coroutine.yield()
end

-- Get the project definition from a csproj/fsproj file
---@param project_file_path string
---@return easy-dotnet.Project.Project
M.get_project_from_project_file = function(project_file_path)
  local result = file_cache.get(project_file_path, function()
    local msbuild_props = M.get_or_wait_or_set_cached_value(project_file_path)
    vim.print(msbuild_props)
    local display = msbuild_props.projectName
    local name = display
    local language = msbuild_props.language
    local is_web_project = msbuild_props.isWebProject
    local is_worker_project = msbuild_props.isWorkerProject
    local is_console_project = string.lower(msbuild_props.outputType) == "exe"
    local is_test_project = msbuild_props.isTestProject and not msbuild_props.isTestingPlatformApplication
    local is_test_platform_project = msbuild_props.isTestingPlatformApplication
    local is_win_project = string.lower(msbuild_props.outputType) == "winexe"
    local is_nuget_package = msbuild_props.generatePackageOnBuild or msbuild_props.isPackable
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

    ---@type easy-dotnet.Project.Project
    local project = {
      display = display,
      path = project_file_path,
      language = language,
      name = name,
      version = version,
      runnable = is_web_project or is_worker_project or is_console_project or is_win_project or msbuild_props.useIISExpress,
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
      msbuild_props = msbuild_props,
      type = "project",
      get_all_runtime_definitions = nil,
      get_specific_runtime_definition = nil,
    }

    ---@param target_framework string specified as e.g net8.0
    ---@return easy-dotnet.Project.Framework
    project.get_specific_runtime_definition = function(target_framework)
      if not project.msbuild_props.isMultiTarget then return project end
      --TODO: validate that arg is a valid targetFramework on the project
      local msbuild_target_framework_props = M.get_or_wait_or_set_cached_value(project_file_path, target_framework)
      local runtime_version = target_framework:gsub("%net", "")
      ---@type easy-dotnet.Project.Framework
      local project_framework = {
        display = project.display .. "@" .. runtime_version,
        get_dll_path = function() return msbuild_target_framework_props.targetPath end,
        version = msbuild_target_framework_props.version,
        dll_path = msbuild_target_framework_props.targetPath,
        type = "project_framework",
        ---@type easy-dotnet.MSBuild.Properties
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
