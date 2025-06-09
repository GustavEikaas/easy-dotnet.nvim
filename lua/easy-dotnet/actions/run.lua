local M = {}
local picker = require("easy-dotnet.picker")
local parsers = require("easy-dotnet.parsers")
local logger = require("easy-dotnet.logger")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local error_messages = require("easy-dotnet.error-messages")
local polyfills = require("easy-dotnet.polyfills")

---@param project DotnetProject
local function build_iis_command(project)
  local sln_path = sln_parse.find_solution_file()
  if not sln_path then error("No .sln file found. Ensure you're inside a valid solution.") end

  local sln_dir = vim.fs.dirname(sln_path)
  local sln_file_name = vim.fn.fnamemodify(sln_path, ":t:r")
  local site_name = vim.fn.fnamemodify(project.path, ":t:r")

  local config_path = string.format("%s/.vs/%s/config/applicationhost.config", sln_dir, sln_file_name)

  if vim.fn.filereadable(config_path) == 0 then
    error(string.format("Missing applicationhost.config at %s. Open the project in Visual Studio and run it once to generate the appropriate IIS Express config.", config_path))
  end

  local cmd = string.format('iisexpress.exe /config:"%s" /site:%s /apppool:Clr4IntegratedAppPool', config_path, site_name)

  return cmd
end

---Runs a dotnet project with the given arguments using the terminal runner.
---
---This is a wrapper around `term(path, "run", args)`.
---
---@param project DotnetProject: The full path to the Dotnet project.
---@param args string: Additional arguments to pass to `dotnet run`.
---@param term function: terminal callback
local function run_project(project, args, term)
  args = args or ""
  local arg = ""
  if project.type == "project_framework" then arg = arg .. " --framework " .. project.msbuild_props.targetFramework end

  local cmd = project.is_net_framework == false and string.format("dotnet run --project %s %s", project.path, args)
    or project.msbuild_props.net_framework.use_iis_express and build_iis_command(project)
    or project.msbuild_props.targetPath
    or error("Failed to compute run command for " .. project.path)

  ---@type DotnetActionContext
  local context = { command = cmd, is_net_framework = project.is_net_framework }

  term(project.path, "run", arg .. " " .. args, context)
end

local pick_project_without_solution = function()
  local csproject_path = csproj_parse.find_project_file()
  if not csproject_path then logger.error(error_messages.no_runnable_projects_found) end
  local project = csproj_parse.get_project_from_project_file(csproject_path)
  local project_framework = picker.pick_sync(nil, project.get_all_runtime_definitions(), "Run project")
  return project_framework
end

---@param term function
local function csproj_fallback_run(term, args)
  local project = pick_project_without_solution()
  run_project(project, args, term)
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
---@return DotnetProject: The selected or default DotnetProject.
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
  ---@type DotnetProject
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
M.run_project_picker = function(term, use_default, args)
  term = term or require("easy-dotnet.options").options.terminal
  use_default = use_default or false
  args = args or ""
  local default_manager = require("easy-dotnet.default-manager")
  local solution_file_path = sln_parse.find_solution_file()
  if solution_file_path == nil then
    csproj_fallback_run(term, args)
    return
  end

  local project = pick_project_framework(use_default)
  run_project(project, args, term)

  if not use_default then default_manager.set_default_project(project, solution_file_path, "run") end
end

---@param project DotnetProject
local function pick_profile(project)
  local path = polyfills.fs.joinpath(vim.fs.dirname(project.path), "Properties/launchSettings.json")
  --In case of OUT OF MEM, this would be another way: cat launchSettings.json | jq '.profiles | to_entries[] | select(.value.commandName == \"Project\") | .key'
  local success, content = pcall(function() return table.concat(vim.fn.readfile(path), "\n") end)
  if not success then
    logger.trace("No launchSettings file found")
    return nil
  end

  local decodeSuccess, json = pcall(vim.fn.json_decode, content)
  if not decodeSuccess then error("Failed to decode json in launchSettings.json") end

  local options = {}
  for key, value in pairs(json.profiles) do
    if value.commandName and value.commandName == "Project" then table.insert(options, { display = key }) end
  end

  local profile = picker.pick_sync(nil, options, "Pick profile")
  if not profile then error("No profile selected") end
  return profile.display
end

---@param use_default boolean
---@param project DotnetProject
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
M.run_project_with_profile = function(term, use_default, args)
  term = term or require("easy-dotnet.options").options.terminal
  use_default = use_default or false
  args = args or ""
  local project, solution_file_path = pick_project_framework(use_default)
  if not project then error("Failed to select project") end
  local profile = get_or_pick_profile(use_default, project, solution_file_path)
  local arg = profile and string.format("--launch-profile %s", vim.fn.shellescape(profile)) or ""
  run_project(project, arg .. " " .. args, term)
end

return M
