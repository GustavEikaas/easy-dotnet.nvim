local M = {}
local picker = require("easy-dotnet.picker")
local parsers = require("easy-dotnet.parsers")
local logger = require("easy-dotnet.logger")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local error_messages = require("easy-dotnet.error-messages")
local polyfills = require("easy-dotnet.polyfills")


---@param projects DotnetProject[]
local function flatten_project_frameworks(projects)
  local project_frameworks = {}

  for _, project in ipairs(projects) do
    local defs = project.get_all_runtime_definitions()
    if defs then
      for _, def in ipairs(defs) do
        table.insert(project_frameworks, def)
      end
    end
  end
  
  return project_frameworks
end

---@param use_default boolean
---@return DotnetProject, string | nil, string | nil
local function pick_project_and_framework(use_default)
  local default_manager = require("easy-dotnet.default-manager")
  local solution_file_path = sln_parse.find_solution_file()
  if solution_file_path == nil then
    local csproject_path = csproj_parse.find_project_file()
    if not csproject_path then logger.error(error_messages.no_runnable_projects_found) end
    local project = csproj_parse.get_project_from_project_file(csproject_path)
    local project_framework = picker.pick_sync(nil, project.get_all_runtime_definitions(), "Run project")
    return project_framework, nil, project_framework.msbuild_props.targetFramework
  end

  local default, framework = default_manager.check_default_project(solution_file_path, "run")

  if default ~= nil and use_default == true then
    if default.msbuild_props.isMultiTarget and not framework then
      local opts = vim.tbl_map(function(i) return { display = i.msbuild_props.targetFramework } end, default.get_all_runtime_definitions())
      if #opts == 0 then error("Failed to get project definitions for " .. default.name) end
      local selected_framework = picker.pick_sync(nil, opts, "pick target framework", true)
      return default, solution_file_path, selected_framework.msbuild_props.targetFramework
    else
      return default, solution_file_path, framework
    end
  end

  local projects = polyfills.tbl_filter(function(i) return i.runnable == true end, sln_parse.get_projects_from_sln(solution_file_path))

  if #projects == 0 then
    logger.error(error_messages.no_runnable_projects_found)
    return
  end

  local project_frameworks = flatten_project_frameworks(projects)

  ---@type DotnetProject
  local project_framework = picker.pick_sync(nil, project_frameworks, "Run project")
  if not project_framework then
    logger.error("No project selected")
    return
  end
  default_manager.set_default_project({ project = project_framework.name, target_framework = project_framework.msbuild_props.targetFramework }, solution_file_path, "run")
  return project_framework, solution_file_path, project_framework.msbuild_props.targetFramework
end

---@param term function
local function csproj_fallback(term, args)
  local csproj_path = csproj_parse.find_project_file()
  if csproj_path == nil then
    logger.error(error_messages.no_project_definition_found)
    return
  end
  local project = csproj_parse.get_project_from_project_file(csproj_path)
  local options = vim.tbl_map(function(i) return { display = i.name .. "@" .. i.version, path = csproj_path, framework = i.msbuild_props.targetFramework } end, project.get_all_runtime_definitions())
  picker.picker(nil, options, function(i)
    args = args .. " --framework " .. i.framework
    term(i.path, "run", args)
  end, "Run project")
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

  local default, target_framework = default_manager.check_default_project(solution_file_path, "run")
  if default ~= nil and use_default == true then
    if default.msbuild_props.isMultiTarget and not target_framework then
      local opts = vim.tbl_map(function(i) return { display = i.msbuild_props.targetFramework } end, default.get_all_runtime_definitions())
      local selected_framework = picker.pick_sync(nil, opts, "Pick target framework", true)
      args = args .. " --framework " .. selected_framework
      term(default.path, "run", args)
    else
      term(default.path, "run", args)
    end
    return
  end

  local projects = sln_parse.get_projects_from_sln(solution_file_path)

  local projects_frameworks = flatten_project_frameworks(projects)

  local project_framework = polyfills.tbl_filter(function(i) return i.runnable == true end, projects_frameworks)

  if #project_framework == 0 then
    logger.error(error_messages.no_runnable_projects_found)
    return
  end
  picker.picker(nil, project_framework, function(i)
    if i.msbuild_props.isMultiTarget then args = args .. " --framework " .. i.msbuild_props.targetFramework end
    term(i.path, "run", args)
    default_manager.set_default_project({ project = i.name, target_framework = i.msbuild_props.targetFramework }, solution_file_path, "run")
  end, "Run project")
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
  local project, solution_file_path, target_framework = pick_project_and_framework(use_default)
  print(target_framework)
  if not project then error("Failed to select project") end
  local profile = get_or_pick_profile(use_default, project, solution_file_path)
  local arg = profile and string.format("--launch-profile '%s'", profile) or ""
  if target_framework then arg = arg .. " --framework " .. target_framework end
  term(project.path, "run", arg .. " " .. args)
end

return M
