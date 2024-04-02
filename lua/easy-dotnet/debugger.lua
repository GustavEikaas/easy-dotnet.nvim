local M = {}
local extensions = require("easy-dotnet.extensions")
local csproj_parse = require("easy-dotnet.csproj-parse")
local sln_parse = require("easy-dotnet.sln-parse")
local picker = require("easy-dotnet.picker")

M.get_debug_dll = function()
  local sln_file = sln_parse.find_solution_file()
  local dll = sln_file ~= nil and M.get_dll_for_solution_project(sln_file) or M.get_dll_for_csproject_project()

  vim.notify("Started debugging " .. dll)
  print(dll)
  return dll
end

local function find_dll_from_bin(folder, filename)
  return require("plenary.scandir").scan_dir({ folder }, { search_pattern = filename, depth = 6 })[1]
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
    dll_name = require("easy-dotnet.picker").pick_sync(nil, runnable_projects, "Select project to debug")
  end

  dll_name = dll_name or runnable_projects[1]

  local path = dll_name.path
  local lastIndex = path:find("[^/]*$")
  local newPath = path:sub(1, lastIndex - 1) .. "bin"
  local filename = dll_name.name .. ".dll"
  return find_dll_from_bin(newPath, filename)
end

M.get_dll_for_csproject_project = function()
  local project_file = csproj_parse.find_csproj_file()
  if project_file == nil then
    error("No project or solution file found")
  end
  local left_part = string.match(project_file, "(.-)%.")

  return find_dll_from_bin(".", left_part .. ".dll")
end

return M
