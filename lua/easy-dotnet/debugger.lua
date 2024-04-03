local M = {}
local extensions = require("easy-dotnet.extensions")
local csproj_parse = require("easy-dotnet.csproj-parse")
local sln_parse = require("easy-dotnet.sln-parse")
local picker = require("easy-dotnet.picker")

M.get_debug_dll = function()
  local sln_file = sln_parse.find_solution_file()
  local result = sln_file ~= nil and M.get_dll_for_solution_project(sln_file) or M.get_dll_for_csproject_project()
  local dll = "." .. result.dll:sub(result.dll:find("\\bin"), -1)
  vim.cmd("cd " .. result.project_directory)
  vim.notify("Started debugging " .. dll .. " in " .. result.project_directory)
  print(dll)

  return dll
end

local function find_dll_from_bin(folder, filename)
  if filename == ".dll" then
    error("Cant find .dll")
  end
  local dlls = require("plenary.scandir").scan_dir({ folder }, {
    search_pattern = function(i)
      return i:match(filename)
    end,
    depth = 6
  })
  if #dlls == 0 then
    error("Failed to find " .. filename .. " did you forget to build")
  end
  return dlls[1], folder
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
  return {
    dll = find_dll_from_bin(path, filename),
    project_directory = path
  }
end

M.get_dll_for_csproject_project = function()
  local project_file = csproj_parse.find_csproj_file()
  if project_file == nil then
    error("No project or solution file found")
  end
  local left_part = string.match(project_file, "(.-)%.")
  return {
    dll = find_dll_from_bin(".", left_part .. ".dll"),
    project_directory = "."
  }
end

return M
