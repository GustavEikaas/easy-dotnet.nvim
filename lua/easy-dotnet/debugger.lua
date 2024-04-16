local M = {}
local extensions = require("easy-dotnet.extensions")
local picker = require("easy-dotnet.picker")
local parsers = require("easy-dotnet.parsers")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser

M.get_debug_dll = function()
  local sln_file = sln_parse.find_solution_file()
  local result = sln_file ~= nil and M.get_dll_for_solution_project(sln_file) or M.get_dll_for_csproject_project()

  return {
    dll_path = result.dll,
    project_path = result.project,
    project_name = result.projectName
  }
end

M.get_environment_variables = function(projectName)
  local dlls = require("plenary.scandir").scan_dir({ "Properties" }, {
    search_pattern = function(i)
      return i:match("launchSettings.json")
    end,
    depth = 6
  })

  if #dlls == 0 then
    return nil
  end

  local launchSettings = dlls[1]

  local success, result = pcall(vim.fn.json_decode, vim.fn.readfile(launchSettings, ""))
  if not success then
    return nil, "Error parsing JSON: " .. result
  end

  local launchProfile = result.profiles[projectName]

  if launchProfile == nil then
    return nil
  end

  launchProfile.environmentVariables["ASPNETCORE_URLS"] = launchProfile.applicationUrl
  return launchProfile.environmentVariables
end

local function find_dll_from_bin(folder, filename, project_folder)
  local cwd = vim.fn.getcwd()
  vim.cmd("cd " .. project_folder)

  if filename == ".dll" then
    error("Cant find .dll")
  end
  local dlls = require("plenary.scandir").scan_dir({ folder }, {
    search_pattern = function(i)
      return i:match(filename)
    end,
    depth = 6
  })

  vim.cmd("cd " .. cwd)
  if #dlls == 0 then
    error("Failed to find " .. filename .. " did you forget to build")
  end
  return dlls[1]
end

M.get_dll_for_solution_project = function(sln_file)
  local projects = sln_parse.get_projects_from_sln(sln_file)
  local runnable_projects = extensions.filter(projects, function(i)
    return i.runnable == true
  end)
  local dll_name
  if #runnable_projects == 0 then
    error("No runnable projects found")
  elseif #runnable_projects > 1 then
    dll_name = picker.pick_sync(nil, runnable_projects, "Select project to debug")
  end

  dll_name = dll_name or runnable_projects[1]

  if dll_name == nil then
    error("No project selected")
  end
  local path = dll_name.path:gsub("([^\\/]+)%.csproj$", "")
  local filename = dll_name.name .. ".dll"
  local dll = find_dll_from_bin("bin", filename, path)
  return {
    dll = dll,
    project = path,
    projectName = dll_name.name
  }
end

M.get_dll_for_csproject_project = function()
  local project_file_path = csproj_parse.find_csproj_file()
  if project_file_path == nil then
    error("No project or solution file found")
  end
  local project = csproj_parse.get_project_from_csproj(project_file_path)
  local path = project.path:gsub("([^\\/]+)%.csproj$", "")
  local dll = find_dll_from_bin("bin", project.name .. ".dll", path)
  return {
    dll = dll,
    project = path,
    projectName = project.name
  }
end

return M
