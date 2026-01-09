local M = {}
local picker = require("easy-dotnet.picker")
local constants = require("easy-dotnet.constants")
local parsers = require("easy-dotnet.parsers")
local logger = require("easy-dotnet.logger")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local error_messages = require("easy-dotnet.error-messages")
local client = require("easy-dotnet.rpc.rpc").global_rpc_client

---Runs a dotnet project with the given arguments using the terminal runner.
---
---This is a wrapper around `term(path, "run", args)`.
---
---@param project easy-dotnet.Project.Project: The full path to the Dotnet project.
---@param args string: Additional arguments to pass to `dotnet run`.
---@param term function: terminal callback
---@param profile string | nil: name of launch profile
local function run_project(project, args, term, attach_debugger, profile)
  if attach_debugger == true then
    require("easy-dotnet.actions.build").rpc_build_quickfix(project.path, nil, nil, function(res)
      if res then
        client.debugger:debugger_start(
          { targetPath = project.path, launchProfileName = profile, targetFramework = nil, configuration = nil },
          function(debugger_config)
            require("dap").run({ type = constants.debug_adapter_name, name = constants.debug_adapter_name, request = "attach", host = "127.0.0.1", port = debugger_config.port }, { new = true })
          end
        )
      end
    end)
  else
    args = args or ""
    local arg = ""
    if project.type == "project_framework" then arg = arg .. " --framework " .. project.msbuild_props.targetFramework end
    local cmd = project.msbuild_props.runCommand
    term(project.path, "run", arg .. " " .. args, { cmd = cmd })
  end
end

---@return easy-dotnet.Project.Project | nil
local pick_project_without_solution = function()
  local csproject_path = csproj_parse.find_project_file()
  if not csproject_path then return nil end
  local project = csproj_parse.get_project_from_project_file(csproject_path)
  local project_framework = picker.pick_sync(nil, project.get_all_runtime_definitions(), "Run project")
  return project_framework
end

local single_file_fallback = function(term, args)
  client:initialize(function()
    local bufname = vim.api.nvim_buf_get_name(0)
    local ext = vim.fn.fnamemodify(bufname, ":e")
    local supports_single_file = require("easy-dotnet.rpc.dotnet-client").supports_single_file_execution

    if ext == "cs" and supports_single_file then
      local cmd_str = string.format("dotnet run %s %s", bufname, args)
      term(bufname, "run", args, { cmd = cmd_str })
    else
      logger.error(error_messages.no_runnable_projects_found)
    end
  end)
end

---@param term function
local function csproj_fallback_run(term, args, attach_debugger)
  local project = pick_project_without_solution()
  if project then
    run_project(project, args, term, attach_debugger)
    return
  end

  single_file_fallback(term, args)
end

---Prompts the user to select a runnable DotnetProject (with framework),
---optionally using a default if configured and allowed.
---
---This function looks for a solution file, checks if a default runnable project
---is defined, and if so, uses it (if `use_default` is `true`). Otherwise, it
---presents the user with a picker of all runnable projects and their frameworks.
---If no solution file is found, falls back to picking a project without one.
---
---If a project is selected, the default is updated for future invocations.
---
---@param use_default boolean: If true, allows using the stored default project if available.
---@return easy-dotnet.Project.Project | nil: The selected or default DotnetProject.
---@return string|nil: The path to the solution file, or nil if no solution is used.
local function pick_project_framework(use_default)
  local default_manager = require("easy-dotnet.default-manager")
  local solution_file_path = sln_parse.find_solution_file()
  if solution_file_path == nil then return pick_project_without_solution(), nil end

  local default = default_manager.check_default_project(solution_file_path, "run")

  if default ~= nil and use_default == true then
    if default.type == "solution" then error("Type solution is not supported for dotnet run") end
    return default.project, solution_file_path
  end

  local projects = sln_parse.get_projects_and_frameworks_flattened_from_sln(solution_file_path, function(i) return i.runnable == true end)

  if #projects == 0 then error(error_messages.no_runnable_projects_found) end
  ---@type easy-dotnet.Project.Project
  local project_framework = picker.pick_sync(nil, projects, "Run project")
  if not project_framework then
    logger.error("No project selected")
    return
  end
  default_manager.set_default_project(project_framework, solution_file_path, "run")
  return project_framework, solution_file_path
end

---@param term function | nil
---@param use_default boolean | nil
---@param args string | nil
M.run_project_picker = function(term, use_default, args, attach_debugger)
  term = term or require("easy-dotnet.options").options.terminal
  use_default = use_default or false
  args = args or ""
  local default_manager = require("easy-dotnet.default-manager")
  local solution_file_path = sln_parse.find_solution_file()
  if solution_file_path == nil then
    csproj_fallback_run(term, args, attach_debugger)
    return
  end

  local project = pick_project_framework(use_default)
  if not project then return end

  run_project(project, args, term, attach_debugger)

  if not use_default then default_manager.set_default_project(project, solution_file_path, "run") end
end

---@param project easy-dotnet.Project.Project
local function pick_profile(project)
  local co = coroutine.running()
  assert(co, "coroutine required for getting launch profiles")

  client:initialize(function()
    client.launch_profiles:get_launch_profiles(vim.fs.dirname(project.path), function(res)
      local values = vim.tbl_filter(function(value) return value.value.commandName == "Project" end, res)
      coroutine.resume(co, values)
    end, { on_crash = function() coroutine.resume(co) end })
  end)

  local profiles = coroutine.yield()
  if not profiles or #profiles == 0 then return nil end
  local options = vim.tbl_map(function(value) return { display = value.name } end, profiles)

  local profile = picker.pick_sync(nil, options, "Pick profile")
  if not profile then error("No profile selected") end
  return profile.display
end

---@param use_default boolean
---@param project easy-dotnet.Project.Project
---@param solution_file_path string | nil
---@return string | nil
local function get_or_pick_profile(use_default, project, solution_file_path)
  if use_default and solution_file_path then
    local default_profile = require("easy-dotnet.default-manager").get_default_launch_profile(solution_file_path, project)
    if default_profile and default_profile.profile then return default_profile.profile end
  end
  local profile = pick_profile(project)
  if not profile then return nil end
  if use_default and solution_file_path then require("easy-dotnet.default-manager").set_default_launch_profile(project, solution_file_path, profile) end

  return profile
end

---@param use_default boolean
M.run_project_with_profile = function(term, use_default, args, attach_debugger)
  term = term or require("easy-dotnet.options").options.terminal
  use_default = use_default or false
  args = args or ""
  local project, solution_file_path = pick_project_framework(use_default)
  if not project then
    single_file_fallback(term, args)
    return
  end
  local profile = get_or_pick_profile(use_default, project, solution_file_path)
  local arg = profile and string.format("--launch-profile %s", vim.fn.shellescape(profile)) or ""
  run_project(project, arg .. " " .. args, term, attach_debugger, profile)
end

return M
