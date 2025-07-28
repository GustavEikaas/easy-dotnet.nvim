local M = {}
local picker = require("easy-dotnet.picker")
local parsers = require("easy-dotnet.parsers")
local logger = require("easy-dotnet.logger")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local error_messages = require("easy-dotnet.error-messages")

---Runs a dotnet project with the given arguments using the terminal runner.
---
---This is a wrapper around `term(path, "run", args)`.
---
---@param project DotnetProject: The full path to the Dotnet project.
---@param args string: Additional arguments to pass to `dotnet watch`.
---@param term function: terminal callback
local function watch_project(project, args, term)
  args = args or ""
  local arg = ""
  if project.type == "project_framework" then arg = arg .. " --framework " .. project.msbuild_props.targetFramework end
  term(project.path, "watch", arg .. " " .. args)
end

local pick_project_without_solution = function()
  local csproject_path = csproj_parse.find_project_file()
  if not csproject_path then logger.error(error_messages.no_runnable_projects_found) end
  local project = csproj_parse.get_project_from_project_file(csproject_path)
  local project_framework = picker.pick_sync(nil, project.get_all_runtime_definitions(), "Watch project")
  return project_framework
end

---@param term function
local function csproj_fallback(term, args)
  local project = pick_project_without_solution()
  watch_project(project, args, term)
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
    csproj_fallback(term, args)
    return
  end

  local default = default_manager.check_default_project(solution_file_path, "watch")
  if default ~= nil and use_default == true then
    if default.type == "solution" then error("Type solution is not supported for dotnet watch") end
    watch_project(default.project, args, term)
    return
  end

  local projects = sln_parse.get_projects_and_frameworks_flattened_from_sln(solution_file_path, function(i) return i.runnable == true and not i.is_net_framework end)

  if #projects == 0 then
    logger.error(error_messages.no_runnable_projects_found)
    return
  end
  picker.picker(nil, projects, function(i)
    watch_project(i, args, term)
    default_manager.set_default_project(i, solution_file_path, "watch")
  end, "Run project")
end

return M
