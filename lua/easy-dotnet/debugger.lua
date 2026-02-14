local M = {}

local picker = require("easy-dotnet.picker")
local client = require("easy-dotnet.rpc.rpc").global_rpc_client
local error_messages = require("easy-dotnet.error-messages")
local logger = require("easy-dotnet.logger")
local parsers = require("easy-dotnet.parsers")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local polyfills = require("easy-dotnet.polyfills")

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
  local solution_file_path = sln_parse.try_get_selected_solution_file()
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

return M
