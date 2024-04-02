local M = {}
local extensions = require("easy-dotnet.extensions")
local csproj_parse = require("easy-dotnet.csproj-parse")
local sln_parse = require("easy-dotnet.sln-parse")
local picker = require("easy-dotnet.picker")

local function csproj_fallback(on_select)
  local csproj_path = csproj_parse.find_csproj_file()
  if (csproj_path == nil) then
    vim.notify("No .sln file or .csproj file found")
  end
  picker.picker(nil, { { name = csproj_path, display = csproj_path, path = csproj_path } }, on_select, "Run project")
end

M.run_project_picker = function(on_select)
  local solutionFilePath = sln_parse.find_solution_file()
  if solutionFilePath == nil then
    csproj_fallback(on_select)
    return
  end
  local projects = extensions.filter(sln_parse.get_projects_from_sln(solutionFilePath), function(i)
    return i.runnable == true
  end)

  if #projects == 0 then
    vim.notify("No runnable projects found")
    return
  end
  picker.picker(nil, projects, on_select, "Run project")
end

return M
