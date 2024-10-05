local M = {}
local extensions = require("easy-dotnet.extensions")
local picker = require("easy-dotnet.picker")
local parsers = require("easy-dotnet.parsers")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local error_messages = require("easy-dotnet.error-messages")

---@param use_default boolean
---@return DotnetProject, string | nil
local function pick_project(use_default)
  local default_manager = require("easy-dotnet.default-manager")
  local solution_file_path = sln_parse.find_solution_file()
  if solution_file_path == nil then
    local csproject_path = csproj_parse.find_project_file()
    if not csproject_path then
      vim.notify(error_messages.no_runnable_projects_found)
    end
    local project = csproj_parse.get_project_from_project_file(csproject_path)
    return project, nil
  end

  local default = default_manager.check_default_project(solution_file_path, "run")
  if default ~= nil and use_default == true then
    return default, solution_file_path
  end

  local projects = extensions.filter(sln_parse.get_projects_from_sln(solution_file_path), function(i)
    return i.runnable == true
  end)

  if #projects == 0 then
    vim.notify(error_messages.no_runnable_projects_found)
    return
  end
  local project = picker.pick_sync(nil, projects, "Run project")
  if not project then
    vim.notify("No project selected")
    return
  end
  default_manager.set_default_project(project, solution_file_path, "run")
  return project, solution_file_path
end

---@param term function
local function csproj_fallback(term)
  local csproj_path = csproj_parse.find_project_file()
  if (csproj_path == nil) then
    vim.notify(error_messages.no_project_definition_found)
    return
  end
  picker.picker(nil, { { name = csproj_path, display = csproj_path, path = csproj_path } },
    function(i) term(i.path, "run") end, "Run project")
end

---@param term function
---@param use_default boolean
---@param args string | nil
M.run_project_picker = function(term, use_default, args)
  local default_manager = require("easy-dotnet.default-manager")
  local solution_file_path = sln_parse.find_solution_file()
  if solution_file_path == nil then
    csproj_fallback(term)
    return
  end

  local default = default_manager.check_default_project(solution_file_path, "run")
  if default ~= nil and use_default == true then
    term(default.path, "run", args)
    return
  end

  local projects = extensions.filter(sln_parse.get_projects_from_sln(solution_file_path), function(i)
    return i.runnable == true
  end)

  if #projects == 0 then
    vim.notify(error_messages.no_runnable_projects_found)
    return
  end
  picker.picker(nil, projects, function(i)
    term(i.path, "run", args)
    default_manager.set_default_project(i, solution_file_path, "run")
  end, "Run project")
end



---@param project DotnetProject
local function pick_profile(project)
  local path = vim.fs.joinpath(vim.fs.dirname(project.path), "Properties/launchSettings.json")
  local success, json = pcall(vim.fn.json_decode, table.concat(vim.fn.readfile(path), "\n"))
  if not success then
    error(string.format("Failed to read %s", path))
  end
  local options = {}
  for key, value in pairs(json.profiles) do
    if value.commandName and value.commandName == "Project" then
      table.insert(options, { display = key })
    end
  end

  local profile = picker.pick_sync(nil, options, "Pick profile")
  if not profile then
    error("No profile selected")
  end
  return profile.display
end


---@param use_default boolean
---@param project DotnetProject
---@param solution_file_path string | nil
---@return string
local function get_or_pick_profile(use_default, project, solution_file_path)
  if use_default and solution_file_path then
    local default_profile = require("easy-dotnet.default-manager").get_default_launch_profile(solution_file_path, project)
    if default_profile and default_profile.profile then
      return default_profile.profile
    end
  end
  local profile = pick_profile(project)
  if not profile then
    error("Failed to select profile")
  end
  if use_default and solution_file_path then
    require("easy-dotnet.default-manager").set_default_launch_profile(project, solution_file_path, profile)
  end

  return profile
end

---@param use_default boolean
M.run_project_with_profile = function(term, use_default)
  local project, solution_file_path = pick_project(use_default)
  if not project then
    error("Failed to select project")
  end
  local profile = get_or_pick_profile(use_default, project, solution_file_path)
  term(project.path, "run", string.format("--launch-profile '%s'", profile))
end

return M
