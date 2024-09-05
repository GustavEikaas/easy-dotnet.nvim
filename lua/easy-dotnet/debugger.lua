local M = {}
local extensions = require("easy-dotnet.extensions")
local picker = require("easy-dotnet.picker")
local parsers = require("easy-dotnet.parsers")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser

M.get_debug_dll = function()
  local sln_file = sln_parse.find_solution_file()
  local result = sln_file ~= nil and M.get_dll_for_solution_project(sln_file) or M.get_dll_for_project()
  local relative_dll_path = vim.fs.joinpath(vim.fn.getcwd(), result.dll)
  local relative_project_path = vim.fs.joinpath(vim.fn.getcwd(), result.project)
  return {
    dll_path = result.dll,
    project_path = result.project,
    project_name = result.projectName,
    relative_dll_path = relative_dll_path,
    relative_project_path = relative_project_path
  }
end

M.get_environment_variables = function(project_name, relative_project_path)
  local launchSettings = vim.fs.joinpath(relative_project_path, "Properties", "launchSettings.json")

  local stat = vim.loop.fs_stat(launchSettings)
  if stat == nil then
    return nil
  end

  local success, result = pcall(vim.fn.json_decode, vim.fn.readfile(launchSettings, ""))
  if not success then
    return nil, "Error parsing JSON: " .. result
  end

  local launchProfile = result.profiles[project_name]

  if launchProfile == nil then
    return nil
  end

  --TODO: Is there more env vars in launchsetttings.json?
  launchProfile.environmentVariables["ASPNETCORE_URLS"] = launchProfile.applicationUrl
  return launchProfile.environmentVariables
end

M.get_dll_for_solution_project = function(sln_file)
  local projects = sln_parse.get_projects_from_sln(sln_file)
  ---@type DotnetProject[]
  local runnable_projects = extensions.filter(projects, function(i)
    return i.runnable == true
  end)

  ---@type DotnetProject
  local project
  if #runnable_projects == 0 then
    error("No runnable projects found")
  elseif #runnable_projects > 1 then
    project = picker.pick_sync(nil, runnable_projects, "Select project to debug")
  end

  project = project or runnable_projects[1]

  if project == nil then
    error("No project selected")
  end

  -- local path = project.path:gsub("([^\\/]+)%.csproj$", "")
  local path = vim.fs.dirname(project.path)
  return {
    dll = project.dll_path,
    project = path,
    projectName = project.name
  }
end

M.get_dll_for_project = function()
  local project_file_path = csproj_parse.find_project_file()
  if project_file_path == nil then
    error("No project or solution file found")
  end
  local project = csproj_parse.get_project_from_project_file(project_file_path)
  local path = vim.fs.dirname(project.path)
  return {
    projectName = project.name,
    dll = project.dll_path,
    project = path
  }
end

return M
