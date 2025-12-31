local M = {}

local picker = require("easy-dotnet.picker")
local client = require("easy-dotnet.rpc.rpc").global_rpc_client
local error_messages = require("easy-dotnet.error-messages")
local logger = require("easy-dotnet.logger")
local parsers = require("easy-dotnet.parsers")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local polyfills = require("easy-dotnet.polyfills")

local function select_profile(profiles, result)
  local profile_name = picker.pick_sync(nil, polyfills.tbl_map(function(i) return { display = i, value = i } end, profiles), "Pick launch profile", true)
  return result[profile_name.value]
end

local function select_launch_profile_name(project_path)
  local launch_profiles = M.get_launch_profiles(project_path)

  if launch_profiles == nil then return nil end

  local profiles = polyfills.tbl_keys(launch_profiles)
  if #profiles == 0 then return nil end

  local profile_name = picker.pick_sync(nil, polyfills.tbl_map(function(i) return { display = i, value = i } end, profiles), "Pick launch profile", true)
  return profile_name.value
end

---@param use_default boolean
---@return easy-dotnet.Project.Project, string | nil
local function pick_project(use_default)
  local default_manager = require("easy-dotnet.default-manager")
  local solution_file_path = sln_parse.find_solution_file()
  if solution_file_path == nil then
    local csproject_path = csproj_parse.find_project_file()
    if not csproject_path then logger.error(error_messages.no_runnable_projects_found) end
    local project = csproj_parse.get_project_from_project_file(csproject_path)
    local selected = picker.pick_sync(nil, project.get_all_runtime_definitions(), "Select TargetFramework", true)
    return selected, nil
  end

  local default = default_manager.check_default_project(solution_file_path, "debug")
  if default ~= nil and use_default == true then return default.project, solution_file_path end

  local projects = sln_parse.get_projects_and_frameworks_flattened_from_sln(solution_file_path, function(project) return project.runnable end)

  if #projects == 0 then
    logger.error(error_messages.no_runnable_projects_found)
    return
  end
  local project = picker.pick_sync(nil, projects, "Debug project")
  if not project then
    logger.error("No project selected")
    return
  end
  default_manager.set_default_project(project, solution_file_path, "debug")
  return project, solution_file_path
end

M.get_debug_dll = function(default)
  local sln_file = sln_parse.find_solution_file()
  local result = sln_file ~= nil and M.get_dll_for_solution_project(default) or M.get_dll_for_project()
  local target_path = result.dll
  local absolute_project_path = result.project

  return {
    target_path = target_path,
    absolute_project_path = absolute_project_path,
    --OBSOLETE kept for backwards compat
    dll_path = target_path,
    project_path = result.project,
    project_name = result.projectName,
    relative_dll_path = target_path,
    relative_project_path = absolute_project_path,
  }
end

---@class easy-dotnet.Debugger.PrepareResult
---@field path string
---@field target_framework_moniker string | nil
---@field configuration string | nil
---@field launch_profile string | nil

---@param use_default boolean
M.prepare_debugger = function(use_default)
  local project = pick_project(use_default)
  --TODO: pick configuration?
  local co = coroutine.running()
  client.msbuild:msbuild_build({ targetPath = project.path, targetFramework = project.msbuild_props.targetFramework }, function(res) coroutine.resume(co, res.success) end, {
    on_crash = function() coroutine.resume(co, false) end,
  })
  local build_res = coroutine.yield()

  if build_res == false then
    --TODO: add build errors to qf list
    error("Aborting debug session due to build failure")
    return nil
  end

  local launch_profile_name = select_launch_profile_name(vim.fs.dirname(project.path))

  client.debugger:debugger_start(
    { targetPath = project.path, targetFramework = project.msbuild_props.targetFramework, configuration = "Debug", launchProfileName = launch_profile_name },
    function(res) coroutine.resume(co, res.port) end,
    {
      on_crash = function()
        logger.error("Debugger failed to start")
        coroutine.resume(co)
      end,
    }
  )
  local curr_debugger_port = coroutine.yield()

  return curr_debugger_port
end

local function run_job_sync(cmd)
  local result = {}
  local co = coroutine.running()

  vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    on_stdout = function(_, data, _)
      for _, line in ipairs(data) do
        local match = string.match(line, "Process Id: (%d+)")
        if match then
          result.process_id = tonumber(match)
          coroutine.resume(co)
          return
        end
      end
    end,
  })

  coroutine.yield()

  return result
end

---@param path string
local function start_test_process(path)
  local command = string.format("dotnet test %s --environment=VSTEST_HOST_DEBUG=1", path)
  local res = run_job_sync(command)
  if not res.process_id then error("Failed to start process") end
  return res.process_id
end

M.start_debugging_test_project = function(project_path)
  local sln_file = sln_parse.find_solution_file()
  assert(sln_file, "Failed to find a solution file")
  local test_projects = sln_parse.get_projects_and_frameworks_flattened_from_sln(sln_file, function(i) return i.isTestProject end)
  local test_project = project_path and project_path or picker.pick_sync(nil, test_projects, "Pick test project").path
  assert(test_project, "No project selected")

  local process_id = start_test_process(test_project)
  return {
    process_id = process_id,
    cwd = vim.fs.dirname(test_project),
  }
end

M.get_launch_profiles = function(relative_project_path)
  local co = coroutine.running()

  client:initialize(function()
    client.launch_profiles:get_launch_profiles(relative_project_path, function(res) coroutine.resume(co, res) end, {
      on_crash = function() coroutine.resume(co) end,
    })
  end)
  local profiles = coroutine.yield()
  local dictionary = {}
  for _, entry in ipairs(profiles) do
    dictionary[entry.name] = entry.value
  end

  return dictionary
end

M.get_environment_variables = function(project_name, relative_project_path, autoselect)
  if autoselect == nil then autoselect = true end

  local launch_profiles = M.get_launch_profiles(relative_project_path)

  if launch_profiles == nil then return nil end

  local profiles = polyfills.tbl_keys(launch_profiles)

  local launch_profile = (not autoselect and #profiles > 0) and select_profile(profiles, launch_profiles) or launch_profiles[project_name]

  if launch_profile == nil then return nil end

  --TODO: Is there more env vars in launchsetttings.json?
  launch_profile.environmentVariables["ASPNETCORE_URLS"] = launch_profile.applicationUrl
  return launch_profile.environmentVariables
end

M.get_dll_for_solution_project = function(default)
  if default == nil then default = false end
  local project = pick_project(default)
  local path = vim.fs.dirname(project.path)
  return {
    dll = project.get_dll_path(),
    project = path,
    projectName = project.name,
  }
end

M.get_dll_for_project = function()
  local project_file_path = csproj_parse.find_project_file()
  if project_file_path == nil then error("No project or solution file found") end
  local project = csproj_parse.get_project_from_project_file(project_file_path)
  local selected = picker.pick_sync(nil, project.get_all_runtime_definitions(), "Select TargetFramework", true)
  return {
    projectName = selected.name,
    dll = selected.get_dll_path(),
    project = vim.fs.dirname(selected.path),
  }
end

return M
